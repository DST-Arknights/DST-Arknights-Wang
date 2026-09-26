-- ════════════════════════════════════════════════════════
-- 连星连接光束（棋子之间的"电线"）
-- 两棋子中点生成一段光束，由 electricconnector 的 ConnectTo 创建
--   ConnectTo → SpawnPrefab("piece_link_field") → fx:SetBeam(距离, 朝向角)
-- 读档重连：electricconnector.LoadPostPass 重连时重新生成并 SetBeam
-- 碰线触电：复用原版 fence_electric_field 的窄三角碰撞网格 + electrocute 事件
-- 视觉保留本模组单线版本；玩法碰撞与原版麻刺节点电场一致
-- ════════════════════════════════════════════════════════

local assets = {
  Asset("ANIM", "anim/fence_electric_field_fx.zip"),
}

-- 光束分段的 FX（一段 bolt 动画，沿光束方向拉伸，跟随"marker"符号定位）
local function CreateSegFx(seg, rot, scale, pos_y)
  local fx = CreateEntity()
  fx:AddTag("FX")
  fx:AddTag("NOCLICK")
  fx.entity:SetCanSleep(false)
  fx.persists = false
  fx.entity:AddTransform()
  fx.entity:AddAnimState()
  fx.entity:AddFollower()
  fx.AnimState:SetBuild("fence_electric_field_fx")
  fx.AnimState:SetBank("fence_electric_field_fx")
  fx.AnimState:PlayAnimation("beam", true)
  fx.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
  fx.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
  fx.AnimState:SetScale(scale, 1)
  fx.AnimState:SetMultColour(1, 1, 1, 0.4 + math.random() * 0.1)
  fx.AnimState:UsePointFiltering(true)
  fx.Transform:SetRotation(rot)
  fx.entity:SetParent(seg.entity)
  fx.Follower:FollowSymbol(seg.GUID, "marker", 0, pos_y, 0)
  fx.AnimState:SetFrame(math.random(fx.AnimState:GetCurrentAnimationNumFrames()) - 1)
  return fx
end

-- 光束中间的分段锚点（链在 field 实体下，局部坐标沿光束排列）
local function CreateSegAt(inst, x, z, rot, scale, isend)
  local seg = CreateEntity()
  seg:AddTag("FX")
  seg:AddTag("NOCLICK")
  seg.entity:SetCanSleep(false)
  seg.persists = false
  seg.entity:AddTransform()
  seg.entity:AddAnimState()
  seg.entity:SetParent(inst.entity)
  seg.Transform:SetPosition(x, 0, z)
  seg.AnimState:SetBuild("fence_electric_field_fx")
  seg.AnimState:SetBank("fence_electric_field_fx")
  seg.AnimState:PlayAnimation("follow_marker_fence_2")
  seg.persists = false
  seg.fx = CreateSegFx(seg, rot, scale, 40)
  return seg
end

local function ClearSegs(inst)
  if inst.segs then
    for i, v in ipairs(inst.segs) do
      v:Remove()
    end
    inst.segs = nil
  end
  if not TheWorld.ismastersim then
    return
  end
  inst.SoundEmitter:KillSound("linked_lp")
  inst.Physics:SetCollides(true)
  inst.Physics:SetCollisionCallback(nil)
end

local MAX_LEN = 15  -- 与 SetBeam 归一化基准一致（原版同值）
local SEG_LEN = 2.15
local TARGET_SPACING = 4
local TARGET_RANGE = 0.1 -- 原版电场线两侧各 0.1 的碰撞宽度

local SHOCK_COOLDOWNS = {
  DEFAULT = 1,
  CHARACTER = 2,
  EPIC = 3,
}

local SHOCK_DAMAGE = {
  PLAYER = 5,
  DEFAULT = 10,
  EPIC = 20,
}

local function ObjectNonPermanence(inst)
  inst:RemoveEventCallback("onremove", ObjectNonPermanence, inst.panic_electric_field)
  inst.panic_electric_field = nil
end

local function ClearForgetTask(inst)
  if inst.forget_field_task ~= nil then
    inst.forget_field_task:Cancel()
    inst.forget_field_task = nil
  end
end

local function GetShockCooldown(inst)
  return (inst:HasTag("character") and SHOCK_COOLDOWNS.CHARACTER
      or inst:HasTag("epic") and SHOCK_COOLDOWNS.EPIC
      or SHOCK_COOLDOWNS.DEFAULT)
      + (inst._electrocute_resist or 0)
end

local function GetShockDamage(inst)
  return inst:HasTag("player") and SHOCK_DAMAGE.PLAYER
      or inst:HasTag("epic") and SHOCK_DAMAGE.EPIC
      or SHOCK_DAMAGE.DEFAULT
end

local BrainCommon = require("brains/braincommon")

local function DoCollideShock(other, inst)
  local t = GetTime()
  if (inst.targets[other] or -math.huge) < t
      and other:IsValid() and not other:IsInLimbo() then
    other:PushEventImmediate("electrocute", {
      duration = TUNING.ELECTROCUTE_SHORT_DURATION,
      noburn = true,
    })

    -- 电网本身作为环境伤害，不制造仇恨目标；伤害与本次触电共用冷却。
    if other.components.health ~= nil
        and not other.components.health:IsDead()
        and other.components.combat ~= nil then
      other.components.combat:GetAttacked(nil, GetShockDamage(other), nil, "electric")
    end

    if other.sg ~= nil and other.sg:HasStateTag("electrocute") then
      ClearForgetTask(other)

      if BrainCommon.HasElectricFencePanicTriggerNode(other)
          and other.panic_electric_field ~= inst then
        other:PushEvent("shocked_by_new_field", inst)
        other.panic_electric_field = inst
        other:ListenForEvent("onremove", ObjectNonPermanence, inst)
      end

      other.forget_field_task = other:DoTaskInTime(
        TUNING.ELECTRIC_FIELD_MOB_PANICTIME,
        ObjectNonPermanence
      )
    end

    inst.targets[other] = t + GetShockCooldown(other)
  end

  other.do_collide_shock_task = nil
end

-- 原版技巧：Physics:SetCollides(false) 后碰撞回调仍会触发，
-- 因此电场可以检测穿越但不会真的把角色挡住。
local function OnCollisionCallback(inst, other)
  if other == nil or not other:IsValid() or not inst:IsValid() then
    return
  end

  if other.do_collide_shock_task == nil then
    -- 下一帧处理，避开 physics callback 内直接改状态。
    other.do_collide_shock_task = other:DoTaskInTime(0, DoCollideShock, inst)
  end
end

local function AddPlane(triangles, x0, y0, z0, x1, y1, z1)
  table.insert(triangles, x0)
  table.insert(triangles, y0)
  table.insert(triangles, z0)

  table.insert(triangles, x0)
  table.insert(triangles, y1)
  table.insert(triangles, z0)

  table.insert(triangles, x1)
  table.insert(triangles, y0)
  table.insert(triangles, z1)

  table.insert(triangles, x1)
  table.insert(triangles, y0)
  table.insert(triangles, z1)

  table.insert(triangles, x0)
  table.insert(triangles, y1)
  table.insert(triangles, z0)

  table.insert(triangles, x1)
  table.insert(triangles, y1)
  table.insert(triangles, z1)
end

local function BuildFieldMesh(halflen, rot)
  local triangles = {}
  local cos_rot = math.cos(rot)
  local sin_rot = math.sin(rot)
  local cos_rot_op = math.cos(rot + HALFPI)
  local sin_rot_op = math.sin(rot + HALFPI)

  local x0, z0 = halflen * cos_rot, halflen * -sin_rot
  local x1, z1 = -halflen * cos_rot, -halflen * -sin_rot
  local x2, z2 = x0, z0
  local x3, z3 = x1, z1

  x0, z0 = x0 + cos_rot_op * TARGET_RANGE, z0 - sin_rot_op * TARGET_RANGE
  x1, z1 = x1 + cos_rot_op * TARGET_RANGE, z1 - sin_rot_op * TARGET_RANGE
  x2, z2 = x2 - cos_rot_op * TARGET_RANGE, z2 + sin_rot_op * TARGET_RANGE
  x3, z3 = x3 - cos_rot_op * TARGET_RANGE, z3 + sin_rot_op * TARGET_RANGE

  AddPlane(triangles, x0, 0, z0, x1, 5, z1)
  AddPlane(triangles, x2, 0, z2, x3, 5, z3)
  return triangles
end

-- 按 len/rot 重建光束分段链（net 变量变化 / 唤醒时触发）
local function RefreshSegs(inst)
  local len = inst.len:value() / 255 * MAX_LEN
  local rot = inst.rot:value() / 255 * 360
  local theta = rot * DEGREES
  local costheta = math.cos(theta)
  local sintheta = math.sin(theta)

  if inst.segs == nil and not TheNet:IsDedicated() then
    inst.segs = {}
    local num = math.max(1, math.floor(len / SEG_LEN + 0.5))
    local scale = len / (num * SEG_LEN)
    local spacing = len / num
    local dx = spacing * costheta
    local dz = -spacing * sintheta
    local dstart = (1 - num) / 2
    local x = dx * dstart
    local z = dz * dstart
    for i = 1, num do
      inst.segs[i] = CreateSegAt(inst, x, z, rot, scale, i == 1 or i == num)
      x = x + dx
      z = z + dz
    end
  end

  if not TheWorld.ismastersim then
    return
  end

  if not inst.SoundEmitter:PlayingSound("linked_lp") then
    inst.SoundEmitter:PlaySound("dontstarve/common/together/electric_fence/linked_lp", "linked_lp")
  end

  inst.Physics:SetTriangleMesh(BuildFieldMesh(len * 0.5, rot * DEGREES))
  inst.Physics:SetCollides(false)
  inst.Physics:SetCollisionCallback(OnCollisionCallback)

  if inst.targetx == nil then
    inst.targetx = {}
    inst.targetz = {}
    local num = math.floor(len / TARGET_SPACING) + 1
    local dx = TARGET_SPACING * costheta
    local dz = -TARGET_SPACING * sintheta
    local dstart = (1 - num) / 2
    local x, _, z = inst.Transform:GetWorldPosition()
    x = x + dx * dstart
    z = z + dz * dstart
    for i = 1, num do
      inst.targetx[i] = x
      inst.targetz[i] = z
      x = x + dx
      z = z + dz
    end
  end
end

local function OnBeamDirty(inst)
  ClearSegs(inst)
  RefreshSegs(inst)
end

-- 拉出一根从(0,0)到(len,朝向角)的光束；由 electricconnector:ConnectTo 调用
local function SetBeam(inst, len, rot)
  inst.len:set_local(0) -- force dirty，位置变化时也会触发重建
  inst.len:set(math.min(255, math.floor(len / MAX_LEN * 255 + 0.5)))
  inst.rot:set(math.floor((rot < 0 and rot + 360 or rot) / 360 * 255 + 0.5))
  if not inst:IsAsleep() then
    OnBeamDirty(inst)
  end
end

local function ForcePhysicsUpdate(inst)
  -- 原版用于让静止实体也持续刷新与电场 mesh 的接触。
  inst.Physics:Stop()
end

local UPDATE_PERIOD = 1
local function OnEntityWake(inst)
  RefreshSegs(inst)
  if inst.update_physics_task ~= nil then
    inst.update_physics_task:Cancel()
  end
  inst.update_physics_task = inst:DoPeriodicTask(UPDATE_PERIOD, ForcePhysicsUpdate)
end

local function OnEntitySleep(inst)
  if inst.update_physics_task ~= nil then
    inst.update_physics_task:Cancel()
    inst.update_physics_task = nil
  end
  ClearSegs(inst)
end

local function SetUpPhysics(inst)
  inst.entity:AddPhysics()
  inst.Physics:SetMass(0)
  inst.Physics:SetCollisionGroup(COLLISION.GROUND)
  inst.Physics:SetCollisionMask(
    COLLISION.OBSTACLES,
    COLLISION.CHARACTERS,
    COLLISION.FLYERS,
    COLLISION.GIANTS
  )
  inst.Physics:SetCollides(false)
  inst.Physics:SetDontRemoveOnSleep(true)
end

local function CanMouseThrough()
  return true, false
end

local function fn()
  local inst = CreateEntity()

  inst.entity:AddTransform()
  inst.entity:AddSoundEmitter()
  inst.entity:AddNetwork()

  SetUpPhysics(inst)

  inst:AddTag("CLASSIFIED")
  inst:AddTag("notarget")
  inst:AddTag("no_collision_callback_for_other")

  inst.len = net_byte(inst.GUID, "piece_link_field.len", "beamdirty")
  inst.rot = net_byte(inst.GUID, "piece_link_field.rot", "beamdirty")

  inst.CanMouseThrough = CanMouseThrough

  inst.entity:SetPristine()

  if not TheWorld.ismastersim then
    inst:ListenForEvent("beamdirty", OnBeamDirty)
    return inst
  end

  inst.Physics:SetCollisionCallback(OnCollisionCallback)
  inst.targets = {}

  inst.SetBeam = SetBeam
  inst.OnEntitySleep = OnEntitySleep
  inst.OnEntityWake = OnEntityWake

  inst.persists = false

  return inst
end

return Prefab("piece_link_field", fn, assets)
