-- ════════════════════════════════════════════════════════
-- 拈子剑（望的武器）
-- 近战武器，攻击附带 1 格溅射伤害；可锤建筑但不破坏（HAMMER 效率 0）
-- 右键点击地面落子：消耗背包一枚黑子，目标点生成部署态棋子（播 ChuXian 出现动画）
-- 无耐久设定
-- ════════════════════════════════════════════════════════

local SPLASH_RANGE = 1 -- 攻击溅射范围（目标周围 1 格）

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

-- 攻击命中后，对目标周围 1 格内其他可攻击生物造成溅射伤害（主目标不重复）
local function OnAttack(inst, attacker, target)
  if target == nil or not target:IsValid() then
    return
  end
  local x, y, z = target.Transform:GetWorldPosition()
  local ents = TheSim:FindEntities(x, y, z, SPLASH_RANGE, nil, { "INLIMBO", "playerghost" })
  local damage = inst.components.weapon:GetDamage(attacker, target)
  for _, ent in ipairs(ents) do
    if ent ~= target and ent:IsValid() and not ent:IsInLimbo()
        and ent.components.combat ~= nil and ent.components.combat:CanBeAttacked()
        and not (ent.components.health ~= nil and ent.components.health:IsDead()) then
      ent.components.combat:GetAttacked(attacker, damage)
    end
  end
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
