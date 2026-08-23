require "prefabutil"

-- ════════════════════════════════════════════════════════
-- 望的棋子（黑子）
-- 物品态（可堆叠 / 可装备投掷）→ 投掷落地转部署态
--   物品态   — 可入背包(堆叠 120) / 装备手上右键投掷(TOSS，水球模式)
--   部署态   — 地面建筑(structure)，可被锤子 / boss 摧毁
-- 投掷落地：生成 chester_transform_fx + wanda_attack_pocketwatch_old_fx
--           遮盖黑子出现，直接播放未激活动画(WeiJiHuo)
-- 引爆：主动(1技能) / 被动(被摧毁) 两种范围伤害，参考火药爆炸
-- 动画来源: animSource/piece/piece.scml
--   idle     — 物品态（普通物品丢地上的表现）
--   XuanZuan — 投掷飞行旋转
--   ChuXian  — 出现（已不再用于部署）
--   WeiJiHuo — 未激活（部署态待机）
--   JiHuo    — 激活
-- ════════════════════════════════════════════════════════

-- 物理效果数值（一般不改动，直接放预制体；可调整数值放 modmain）
local THROW_SPEED = 15    -- 投掷水平速度
local THROW_GRAVITY = -35 -- 投掷重力（抛物线）
local THROW_AOE = 1       -- 落地伤害范围

-- 爆炸数值（modmain 可调）
local EXPLODE_RANGE = TUNING.WANG.PIECE_EXPLODE_RANGE or 4 -- 爆炸半径

RegisterInventoryItemAtlas("images/inventoryimages/piece.xml", "piece.tex")

local assets = {
  Asset("ANIM", "anim/piece.zip"),
  Asset("ANIM", "anim/swap_piece.zip"),
  Asset("ATLAS", "images/inventoryimages/piece.xml"),
}

local prefabs = {}

-- ────────────────────────────────────────────────────────
-- 爆炸相关（参考游戏源码 explosive 组件 + 凯尔希二技能子弹）
-- ────────────────────────────────────────────────────────

-- 爆炸命中敌人时，敌人身上播放的两个特效
local function SpawnHitEnemyFx(ent)
  local x, y, z = ent.Transform:GetWorldPosition()
  local fx1 = SpawnPrefab("wanda_attack_shadowweapon_old_fx")
  if fx1 ~= nil then fx1.Transform:SetPosition(x, y, z) end
  local fx2 = SpawnPrefab("fx_dock_pop")
  if fx2 ~= nil then fx2.Transform:SetPosition(x, y, z) end
end

-- 主动爆炸额外摧毁周围建造物（参考凯尔希二技能子弹命中：collapse_small + workable:Destroy）
-- 不含已部署棋子，避免连锁引爆
local DESTROY_TAGS = { "CHOP_workable", "MINE_workable", "HAMMER_workable", "DIG_workable" }
local function DestroySurroundingBuildings(inst, source)
  local x, y, z = inst.Transform:GetWorldPosition()
  local ents = TheSim:FindEntities(x, y, z, EXPLODE_RANGE, nil,
    { "insect", "INLIMBO", "wang_piece_deployed" }, DESTROY_TAGS)
  for _, ent in ipairs(ents) do
    if ent.components.workable ~= nil and ent.components.workable:CanBeWorked() then
      SpawnPrefab("collapse_small").Transform:SetPosition(ent.Transform:GetWorldPosition())
      repeat
        ent.components.workable:Destroy(source)
      until not (ent:IsValid() and ent.components.workable ~= nil and ent.components.workable:CanBeWorked())
    end
  end
end

-- 范围伤害（参考火药爆炸 explosive 组件：范围内所有可攻击目标）
--   source  伤害来源（主动=施法者记击杀；被动=棋子自身不记名）
--   suggest 被动时吸引仇恨的对象（摧毁者）
local function AoEExplode(inst, source, damage, active, suggest)
  if active then
    DestroySurroundingBuildings(inst, source)
  end

  local x, y, z = inst.Transform:GetWorldPosition()
  local ents = TheSim:FindEntities(x, y, z, EXPLODE_RANGE, nil, { "INLIMBO", "notarget" })
  for _, ent in ipairs(ents) do
    if ent ~= inst and not ent:IsInLimbo() and ent:IsValid()
        and not (ent.components.health ~= nil and ent.components.health:IsDead())
        and ent.components.combat ~= nil and ent.components.combat:CanBeAttacked() then
      ent.components.combat:GetAttacked(source, damage)
      SpawnHitEnemyFx(ent)
      if suggest ~= nil and suggest ~= source and suggest:IsValid() then
        ent.components.combat:SuggestTarget(suggest)
      end
    end
  end
end

-- 爆炸特效：主动 = chester_transform_fx + wanda_attack_pocketwatch_old_fx（同投掷落地）
--            被动 = 仅 wanda_attack_pocketwatch_old_fx
local function SpawnExplodeFx(inst, active)
  local x, y, z = inst.Transform:GetWorldPosition()
  if active then
    local fx1 = SpawnPrefab("chester_transform_fx")
    if fx1 ~= nil then fx1.Transform:SetPosition(x, y, z) end
  end
  local fx2 = SpawnPrefab("wanda_attack_pocketwatch_old_fx")
  if fx2 ~= nil then fx2.Transform:SetPosition(x, y, z) end
end

-- ────────────────────────────────────────────────────────
-- 部署态：投掷落地后转地面建筑
-- ────────────────────────────────────────────────────────
local function SetDeployedState(inst)
  if inst._isdeployed then
    return
  end
  inst._isdeployed = true
  inst:AddTag("structure")
  inst:AddTag("wang_piece_deployed") -- 已部署标记：供 1 技能引爆检索
  RemovePhysicsColliders(inst)
  MakeObstaclePhysics(inst, 0.3)
  inst.Physics:Stop()
  inst.components.inventoryitem.canbepickedup = false
  inst.components.workable:SetWorkable(true)
  inst.AnimState:PlayAnimation("WeiJiHuo", true)
end

-- ────────────────────────────────────────────────────────
-- 投掷落地（complexprojectile onhit）：
-- 落点附近伤害 + 特效遮盖 + 转部署态（不播出现动画）
-- ────────────────────────────────────────────────────────
local function OnTossHit(inst, attacker)
  local x, y, z = inst.Transform:GetWorldPosition()

  local ents = TheSim:FindEntities(x, y, z, THROW_AOE, nil, { "INLIMBO", "playerghost" })
  for _, ent in ipairs(ents) do
    if ent ~= nil and ent:IsValid() and ent.components.combat ~= nil
        and attacker ~= nil and attacker:IsValid() then
      ent.components.combat:GetAttacked(attacker, TUNING.WANG.PIECE_THROW_DAMAGE)
    end
  end

  -- 特效遮盖黑子生成过程（同主动爆炸特效）
  SpawnExplodeFx(inst, true)

  SetDeployedState(inst)
end

-- ────────────────────────────────────────────────────────
-- 装备手上显示
-- ────────────────────────────────────────────────────────
local function onequip(inst, owner)
  owner.AnimState:OverrideSymbol("swap_object", "swap_piece", "swap_object")
  owner.AnimState:Show("ARM_carry")
  owner.AnimState:Hide("ARM_normal")
end

local function onunequip(inst, owner)
  owner.AnimState:ClearOverrideSymbol("swap_object")
  owner.AnimState:Hide("ARM_carry")
  owner.AnimState:Show("ARM_normal")
end

-- ────────────────────────────────────────────────────────
-- 部署态被锤子 / boss 摧毁 → 被动引爆（消耗品，不回收）
-- ────────────────────────────────────────────────────────
local function OnHammered(inst, worker)
  if inst._isdeployed then
    inst:PassiveExplode(worker, 1)  -- 被动引爆倍率 1（无技能加成）
  else
    inst:Remove()
  end
end

-- ────────────────────────────────────────────────────────
-- 主函数
-- ────────────────────────────────────────────────────────
local function fn()
  local inst = CreateEntity()

  inst.entity:AddTransform()
  inst.entity:AddAnimState()
  inst.entity:AddSoundEmitter()
  inst.entity:AddNetwork()

  MakeInventoryPhysics(inst)

  -- 物品态：普通物品的表现（背包/地上显示 idle）
  inst.AnimState:SetBank("piece")
  inst.AnimState:SetBuild("piece")
  inst.AnimState:PlayAnimation("idle", true)

  MakeInventoryFloatable(inst)

  -- 投掷相关（客户端也要有，用于右键菜单生成 TOSS 动作）
  inst:AddTag("projectile")
  inst:AddTag("complexprojectile")

  -- 瞄准圈（装备时由 playercontroller 创建，客户端组件）
  inst:AddComponent("reticule")
  inst.components.reticule.targetfn = function()
    return TheInput:GetWorldPosition()
  end

  inst.entity:SetPristine()

  if not TheWorld.ismastersim then
    return inst
  end

  inst._isdeployed = false

  inst:AddComponent("inspectable")

  inst:AddComponent("inventoryitem")

  -- 可堆叠（系统最大堆叠数）
  inst:AddComponent("stackable")
  inst.components.stackable.maxsize = TUNING.STACK_SIZE_PELLET

  -- 装备手上（equipstack：从堆叠分出单个装备，投掷即消耗一个）
  inst:AddComponent("equippable")
  inst.components.equippable.equipslot = EQUIPSLOTS.HANDS
  inst.components.equippable.equipstack = true
  inst.components.equippable:SetOnEquip(onequip)
  inst.components.equippable:SetOnUnequip(onunequip)

  -- 投掷：item 本身作为抛物线投掷物（waterballoon 模式）
  -- 投掷 = 消耗：TOSS 把装备的单个黑子丢出，落地转部署态，堆叠中其余保留
  inst:AddComponent("complexprojectile")
  inst.components.complexprojectile:SetHorizontalSpeed(THROW_SPEED)
  inst.components.complexprojectile:SetGravity(THROW_GRAVITY)
  inst.components.complexprojectile:SetLaunchOffset(Vector3(0.25, 1, 0))
  inst.components.complexprojectile:SetTargetOffset(Vector3(0, 1.5, 0)) -- 终点Y轴抬高，匹配部署飘浮动画
  inst.components.complexprojectile:SetOnHit(OnTossHit)
  -- 投掷飞行中播放旋转动画（新动画 XuanZuan）
  inst.components.complexprojectile:SetOnLaunch(function()
    inst.AnimState:PlayAnimation("XuanZuan", true)
  end)

  -- 部署态可被锤子 / boss 摧毁
  inst:AddComponent("workable")
  inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
  inst.components.workable:SetWorkLeft(1)
  inst.components.workable:SetOnFinishCallback(OnHammered)
  inst.components.workable:SetWorkable(false)

  -- 部署状态存档：读档后恢复为地面建筑
  inst.OnSave = function(inst, data)
    if inst._isdeployed then
      data.isdeployed = true
    end
  end
  inst.OnLoad = function(inst, data)
    if data ~= nil and data.isdeployed then
      SetDeployedState(inst)
    end
  end

  -- ────────────────────────────────────────────────────────
  -- 引爆方法（挂在棋子实例上，仅部署态有效）
  -- ────────────────────────────────────────────────────────

  -- 棋子基础伤害（内置，便于不同品质/类型扩展）
  inst._baseDamage = TUNING.WANG.PIECE_BASE_DAMAGE

  -- 主动引爆（1技能取势调用）：范围伤害 + 摧毁周围建造物 + 双特效
  -- multiplier: 技能倍率（如 0.9 / 1.1 / 1.3），实际伤害 = 基础伤害 × 倍率
  inst.ActiveExplode = function(_, source, multiplier)
    if not inst._isdeployed then return end
    local damage = inst._baseDamage * (multiplier or 1)
    AoEExplode(inst, source, damage, true)
    SpawnExplodeFx(inst, true)
    inst:Remove()
  end

  -- 被动引爆（被锤子 / boss 摧毁时触发）：范围伤害，仅单特效，不摧毁建造物
  -- multiplier: 倍率，默认 1（被动引爆无技能加成）
  inst.PassiveExplode = function(_, source, multiplier)
    if not inst._isdeployed then return end
    local damage = inst._baseDamage * (multiplier or 1)
    AoEExplode(inst, inst, damage, false, source)
    SpawnExplodeFx(inst, false)
    inst:Remove()
  end

  -- 落子部署（拈子剑右键使用）：转移到目标点 → 播 ChuXian 出现动画 → 部署态待机
  -- pos 需为 Vector3；仅主世界可调用
  inst.DeployPiece = function(_, pos)
    if inst._isdeployed then return end
    inst.Transform:SetPosition(pos.x, pos.y, pos.z)
    SetDeployedState(inst)
    inst.AnimState:PlayAnimation("ChuXian", false)
    inst.AnimState:PushAnimation("WeiJiHuo", true)
  end

  return inst
end

return Prefab("piece", fn, assets, prefabs)
