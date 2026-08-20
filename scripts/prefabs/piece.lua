require "prefabutil"

-- ════════════════════════════════════════════════════════
-- 望的棋子（黑子）
-- 单 prefab 三形态（物品态 / 部署态）：
--   物品态(未装备) — 可入背包 / 右键地面栽种(DEPLOY)
--   装备态         — 右键投掷(TOSS，水球模式)，item 本身抛物线飞出
--   部署态         — 地面建筑(structure)，可被锤子 / boss 摧毁
-- 投掷落地：对附近生物造成 PIECE_THROW_DAMAGE 伤害，并转为部署态
-- 动画来源: animSource/piece/piece.scml
--   ChuXian  — 出现（部署落地）
--   WeiJiHuo — 未激活（待机）
--   JiHuo    — 激活
-- ════════════════════════════════════════════════════════

RegisterInventoryItemAtlas("images/inventoryimages/piece.xml", "piece.tex")

local assets = {
  Asset("ANIM", "anim/piece.zip"),
  Asset("ANIM", "anim/swap_piece.zip"),
  Asset("ATLAS", "images/inventoryimages/piece.xml"),
}

local prefabs = {}

-- ────────────────────────────────────────────────────────
-- 形态切换
-- ────────────────────────────────────────────────────────
local function SetDeployedState(inst, playdeploy)
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
  if playdeploy then
    inst.AnimState:PlayAnimation("ChuXian")
    inst.AnimState:PushAnimation("WeiJiHuo", true)
  else
    inst.AnimState:PlayAnimation("WeiJiHuo", true)
  end
end

-- ────────────────────────────────────────────────────────
-- 栽种：未装备时右键地面（deployable.ondeploy）
-- ────────────────────────────────────────────────────────
local function OnDeploy(inst, pt, deployer)
  inst.Physics:Stop()
  inst.Physics:Teleport(pt:Get())
  SetDeployedState(inst, true)
end

-- ────────────────────────────────────────────────────────
-- 投掷落地（complexprojectile onhit）：落点附近 5 伤害 + 转部署态
-- ────────────────────────────────────────────────────────
local function OnTossHit(inst, attacker)
  local x, y, z = inst.Transform:GetWorldPosition()

  local ents = TheSim:FindEntities(x, y, z, TUNING.WANG.PIECE_THROW_AOE, nil, { "INLIMBO", "playerghost" })
  for _, ent in ipairs(ents) do
    if ent ~= nil and ent:IsValid() and ent.components.combat ~= nil
      and attacker ~= nil and attacker:IsValid() then
      ent.components.combat:GetAttacked(attacker, TUNING.WANG.PIECE_THROW_DAMAGE)
    end
  end

  SetDeployedState(inst, true)
end

-- ────────────────────────────────────────────────────────
-- deployable 组件：未装备时存在（右键=栽种），装备时移除（右键=投掷）
-- 移除后 replica 的 deploy mode 置 NONE，客户端 DEPLOY 动作消失、
-- deployable tag 也移除，TOSS 动作随之出现（componentactions 检查 tag）
-- ────────────────────────────────────────────────────────
local function ConfigureDeployable(inst)
  inst:AddComponent("deployable")
  inst.components.deployable.ondeploy = OnDeploy
  inst.components.deployable:SetDeployMode(DEPLOYMODE.DEFAULT)
  inst.components.deployable:SetDeploySpacing(DEPLOYSPACING.LESS)
end

local function RemoveDeployable(inst)
  if inst.components.deployable ~= nil then
    inst:RemoveComponent("deployable")
  end
end

-- ────────────────────────────────────────────────────────
-- 装备手上显示（占位：用黑子主体 symbol，缺专门的 swap_piece）
-- ────────────────────────────────────────────────────────
local function onequip(inst, owner)
  owner.AnimState:OverrideSymbol("swap_object", "swap_piece", "swap_object")
  owner.AnimState:Show("ARM_carry")
  owner.AnimState:Hide("ARM_normal")
  -- 装备后禁用栽种，右键变成投掷（TOSS）
  RemoveDeployable(inst)
end

local function onunequip(inst, owner)
  owner.AnimState:ClearOverrideSymbol("swap_object")
  owner.AnimState:Hide("ARM_carry")
  owner.AnimState:Show("ARM_normal")
  -- 回到背包后恢复栽种（部署态黑子不可拾取，不会走到这里）
  if not inst._isdeployed then
    ConfigureDeployable(inst)
  end
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
  inst:SetDeploySmartRadius(DEPLOYSPACING_RADIUS[DEPLOYSPACING.LESS] / 2)

  inst.AnimState:SetBank("piece")
  inst.AnimState:SetBuild("piece")
  inst.AnimState:PlayAnimation("WeiJiHuo", true)

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

  -- 初始为物品态：右键地面栽种
  ConfigureDeployable(inst)

  -- 装备手上
  inst:AddComponent("equippable")
  inst.components.equippable.equipslot = EQUIPSLOTS.HANDS
  inst.components.equippable:SetOnEquip(onequip)
  inst.components.equippable:SetOnUnequip(onunequip)

  -- 投掷：item 本身作为抛物线投掷物（waterballoon 模式）
  -- 投掷 = 消耗：TOSS 把 item 从手上丢出，落地转部署态，不再回到背包
  inst:AddComponent("complexprojectile")
  inst.components.complexprojectile:SetHorizontalSpeed(TUNING.WANG.PIECE_THROW_SPEED)
  inst.components.complexprojectile:SetGravity(TUNING.WANG.PIECE_THROW_GRAVITY)
  inst.components.complexprojectile:SetLaunchOffset(Vector3(0.25, 1, 0))
  inst.components.complexprojectile:SetOnHit(OnTossHit)

  -- 部署态可被锤子 / boss 摧毁
  inst:AddComponent("workable")
  inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
  inst.components.workable:SetWorkLeft(1)
  inst.components.workable:SetOnFinishCallback(OnHammered)
  inst.components.workable:SetWorkable(false)

  return inst
end

return Prefab("piece", fn, assets, prefabs),
  MakePlacer("piece_placer", "piece", "piece", "WeiJiHuo")
