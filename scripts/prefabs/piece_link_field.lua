-- ════════════════════════════════════════════════════════
-- 连星连接光束（棋子之间的"电线"）
-- 仅连接视觉：两棋子中点生成一段光束，由 electricconnector 的 ConnectTo 创建
--   ConnectTo → SpawnPrefab("piece_link_field") → fx:SetBeam(距离, 朝向角)
-- 读档重连：electricconnector.LoadPostPass 重连时重新生成并 SetBeam
-- 电击/触电特效后续接入（届时参考原版 fence_electric_field 加碰撞网格 + 电击回调）
-- 参考原版 prefabs/fence_electric_field.lua，去掉了电击与碰撞物理（仅连接效果）
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
  seg.fx = CreateSegFx(seg, rot, scale, 0)
  seg.fx2 = CreateSegFx(seg, rot, scale, 65)
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
end

local MAX_LEN = 15  -- 与 SetBeam 归一化基准一致（原版同值）
local SEG_LEN = 2.15

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

local function OnEntityWake(inst)
  RefreshSegs(inst)
end

local function OnEntitySleep(inst)
  ClearSegs(inst)
end

local function fn()
  local inst = CreateEntity()

  inst.entity:AddTransform()
  inst.entity:AddSoundEmitter()
  inst.entity:AddNetwork()

  inst:AddTag("CLASSIFIED")
  inst:AddTag("notarget")

  inst.len = net_byte(inst.GUID, "piece_link_field.len", "beamdirty")
  inst.rot = net_byte(inst.GUID, "piece_link_field.rot", "beamdirty")

  inst.entity:SetPristine()

  if not TheWorld.ismastersim then
    inst:ListenForEvent("beamdirty", OnBeamDirty)
    return inst
  end

  inst.SetBeam = SetBeam
  inst.OnEntitySleep = OnEntitySleep
  inst.OnEntityWake = OnEntityWake

  inst.persists = false

  return inst
end

return Prefab("piece_link_field", fn, assets)
