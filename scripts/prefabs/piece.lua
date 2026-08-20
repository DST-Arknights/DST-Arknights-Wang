require "prefabutil"

-- ════════════════════════════════════════════════════════
-- 望的棋子（黑子）
-- 物品态（可堆叠 / 可装备投掷）→ 投掷落地转部署态
--   物品态   — 可入背包(堆叠 120) / 装备手上右键投掷(TOSS，水球模式)
--   部署态   — 地面建筑(structure)，可被锤子 / boss 摧毁
-- 投掷落地：生成 chester_transform_fx + wanda_attack_pocketwatch_old_fx
--           遮盖黑子出现，直接播放未激活动画(WeiJiHuo)
-- 动画来源: animSource/piece/piece.scml
--   idle     — 物品态（普通物品丢地上的表现）
--   ChuXian  — 出现（已不再用于部署）
--   WeiJiHuo — 未激活（部署态待机）
--   JiHuo    — 激活
-- ════════════════════════════════════════════════════════

-- 物理效果数值（一般不改动，直接放预制体；可调整数值放 modmain）
local THROW_SPEED = 15    -- 投掷水平速度
local THROW_GRAVITY = -35 -- 投掷重力（抛物线）
local THROW_AOE = 1       -- 落地伤害范围

RegisterInventoryItemAtlas("images/inventoryimages/piece.xml", "piece.tex")

local assets = {
  Asset("ANIM", "anim/piece.zip"),
  Asset("ANIM", "anim/swap_piece.zip"),
  Asset("ATLAS", "images/inventoryimages/piece.xml"),
}

local prefabs = {}

-- ────────────────────────────────────────────────────────
-- 部署态：投掷落地后转地面建筑
-- ────────────────────────────────────────────────────────
local function SetDeployedState(inst)
  if inst._isdeployed then
    return
  end
  inst._isdeployed = true
  inst:AddTag("structure")
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

  -- 特效遮盖黑子生成过程
  local fx1 = SpawnPrefab("chester_transform_fx")
  if fx1 ~= nil then
    fx1.Transform:SetPosition(x, y, z)
  end
  local fx2 = SpawnPrefab("wanda_attack_pocketwatch_old_fx")
  if fx2 ~= nil then
    fx2.Transform:SetPosition(x, y, z)
  end

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
-- 部署态被锤子 / boss 摧毁（消耗品，不回收）
-- ────────────────────────────────────────────────────────
local function OnHammered(inst, worker)
  inst:Remove()
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
  inst.components.complexprojectile:SetOnHit(OnTossHit)

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

  return inst
end

return Prefab("piece", fn, assets, prefabs)
