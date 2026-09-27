-- ════════════════════════════════════════════════════════
-- 拈子剑（望的武器）
-- 近战武器，攻击附带 1 格溅射伤害；可锤建筑但不破坏（HAMMER 效率 0）
-- 右键点击地面落子：消耗背包一枚黑子，目标点生成部署态棋子（播 ChuXian 出现动画）
-- 无耐久设定
-- ════════════════════════════════════════════════════════

local SPLASH_RANGE = 1 -- 攻击溅射范围（目标周围 1 格）
local AREA_EXCLUDE_TAGS = { "INLIMBO", "notarget", "noattack", "flight", "invisible", "playerghost" }

RegisterInventoryItemAtlas("images/inventoryimages/nianzi_sword.xml", "nianzi_sword.tex")

local assets = {
  Asset("ANIM", "anim/nianzi_sword.zip"),
  Asset("ANIM", "anim/swap_nianzi_sword.zip"),
  Asset("ATLAS", "images/inventoryimages/nianzi_sword.xml"),
  Asset("ATLAS", "images/map_icons/nianzi_sword.xml")
}

local function onequip(inst, owner)
  owner.AnimState:OverrideSymbol("swap_object", "swap_nianzi_sword", "swap_nianzi_sword")
  owner.AnimState:Show("ARM_carry")
  owner.AnimState:Hide("ARM_normal")
end

local function onunequip(inst, owner)
  owner.AnimState:ClearOverrideSymbol("swap_object")
  owner.AnimState:Hide("ARM_carry")
  owner.AnimState:Show("ARM_normal")
end

-- 攻击命中后，复用原版 combat 的范围攻击逻辑：自动排除攻击者自己，并遵循原版目标/PVP判断与伤害计算。
local function OnAttack(inst, attacker, target)
  if target == nil or not target:IsValid()
      or attacker == nil or attacker.components.combat == nil then
    return
  end
  attacker.components.combat:DoAreaAttack(target, SPLASH_RANGE, inst, nil, nil, AREA_EXCLUDE_TAGS)
end

local function fn()
  local inst = CreateEntity()

  inst.entity:AddTransform()
  inst.entity:AddAnimState()
  inst.entity:AddSoundEmitter()
  inst.entity:AddNetwork()
  inst.entity:AddMiniMapEntity()
  inst.MiniMapEntity:SetIcon("nianzi_sword.tex")

  MakeInventoryPhysics(inst)

  inst.AnimState:SetBank("nianzi_sword")
  inst.AnimState:SetBuild("nianzi_sword")
  inst.AnimState:PlayAnimation("idle")

  inst:AddTag("weapon")

  -- 落子 POINT 采集器挂载组件（客户端同样加载，供右键地面生成落子动作）
  inst:AddComponent("nianzi_sword")

  -- 右键落子瞄准圈（客户端显示，targetfn 返回鼠标世界坐标）
  inst:AddComponent("reticule")
  inst.components.reticule.targetfn = function()
    return TheInput:GetWorldPosition()
  end

  inst.entity:SetPristine()

  if not TheWorld.ismastersim then
    return inst
  end

  inst:AddComponent("inventoryitem")

  inst:AddComponent("inspectable")
  inst.components.inspectable.descriptionfn = function()
    return STRINGS.CHARACTERS.WANG.NIANZI_SWORD_DESC
  end

  inst:AddComponent("weapon")
  inst.components.weapon:SetDamage(40)
  inst.components.weapon:SetOnAttack(OnAttack)

  -- 锤击能力：能对 HAMMER 可工作目标执行锤击，但效率 0 → 不破坏建筑
  inst:AddComponent("tool")
  inst.components.tool:SetAction(ACTIONS.HAMMER, 0)

  -- 无耐久（不挂 finiteuses）

  inst:AddComponent("equippable")
  inst.components.equippable:SetOnEquip(onequip)
  inst.components.equippable:SetOnUnequip(onunequip)

  return inst
end

return Prefab("nianzi_sword", fn, assets)
