-- ════════════════════════════════════════════════════════
-- 兽形棋盒（跟随容器，宠物式存在）
-- 动画：复用 kitcoon 的 bank 与 basic 动画，使用棋盒专属 build
-- 跟随：参考切斯特（brain 跟随 follower.leader），leader = 放下它的建造者/持有者
-- 拾取：inventoryitem canbepickedup(alive)，左键拾取进物品栏（右键打开由容器接管）
-- 容器：4 格储物，infinitestacksize = 无普通堆叠上限（容器组件 SetIgnoreMaxSize）
-- 宠物式存在（随主人上下线消失/重现，存档由主人管理）：
--   绑定时 persists=false，由主人 wang_chess_box_owner 捕获完整记录；
--   换绑后旧盒解除绑定并恢复 persists=true，作为普通地面实体保存。
--   进出背包事件（SetOnPutInInventoryFn/SetOnDroppedFn）驱动主人组件 TrackBox 记录模式
-- 交互（原版动作解析天然支持）：地面可拾取/打开，物品栏内可装备至头部
-- 穿戴：实体自身通过 FollowSymbol 挂到头部，不覆盖玩家动画符号
-- ════════════════════════════════════════════════════════
RegisterInventoryItemAtlas("images/inventoryimages/piece_box.xml", "piece_box.tex")

local brain = require "brains/piece_boxbrain"

local WRONG_ITEM_COMMENT_CHANCE = 0.5
local EQUIPPED_BRAIN_STOP_REASON = "piece_box_equipped"
local HAT_FOLLOW_OFFSET_X = 0
local HAT_FOLLOW_OFFSET_Y = -120
local HAT_FOLLOW_OFFSET_Z = 0

local assets = {
  Asset("ANIM", "anim/kitcoon_basic.zip"),
  Asset("ANIM", "anim/kitcoon_emotes.zip"),
  Asset("ANIM", "anim/kitcoon_jump.zip"),
  Asset("ANIM", "anim/piece_box_build.zip"),
  Asset("ATLAS", "images/inventoryimages/piece_box.xml"),
  Asset("ATLAS", "images/map_icons/piece_box.xml"),
}

local prefabs = {
  "piece_box_hat_fx",
}

-- ────────────────────────────────────────────────────────
-- 容器开关 → SG 播打开/关闭动画
-- ────────────────────────────────────────────────────────
local function OnOpen(inst)
  if inst.sg ~= nil
      and (inst.components.equippable == nil or not inst.components.equippable:IsEquipped()) then
    inst.sg:GoToState("open")
  end
end

local function OnClose(inst)
  if inst.sg ~= nil
      and (inst.components.equippable == nil or not inst.components.equippable:IsEquipped()) then
    inst.sg:GoToState("close")
  end
end

local function OnItemGet(inst, data)
  local item = data ~= nil and data.item or nil
  local user = inst.components.container.currentuser
  if item ~= nil and item.prefab ~= "piece"
      and user ~= nil and user:IsValid()
      and inst.components.container:IsOpenedBy(user)
      and user.components.talker ~= nil
      and math.random() < WRONG_ITEM_COMMENT_CHANCE then
    user.components.talker:Say(GetString(user, "ANNOUNCE_PIECE_BOX_WRONG_ITEM"))
  end
end

local function ShowOwnerHatSymbols(owner)
  owner.AnimState:ClearOverrideSymbol("headbase_hat")
  owner.AnimState:Show("HAT")
  owner.AnimState:Show("HAIR_HAT")
  owner.AnimState:Hide("HAIR_NOHAT")
  owner.AnimState:Hide("HAIR")

  if owner.isplayer then
    owner.AnimState:Hide("HEAD")
    owner.AnimState:Show("HEAD_HAT")
    owner.AnimState:Show("HEAD_HAT_NOHELM")
    owner.AnimState:Hide("HEAD_HAT_HELM")
  end
end

local function HideOwnerHatSymbols(owner)
  owner.AnimState:ClearOverrideSymbol("headbase_hat")
  owner.AnimState:ClearOverrideSymbol("swap_hat")
  owner.AnimState:Hide("HAT")
  owner.AnimState:Hide("HAIR_HAT")
  owner.AnimState:Show("HAIR_NOHAT")
  owner.AnimState:Show("HAIR")

  if owner.isplayer then
    owner.AnimState:Show("HEAD")
    owner.AnimState:Hide("HEAD_HAT")
    owner.AnimState:Hide("HEAD_HAT_NOHELM")
    owner.AnimState:Hide("HEAD_HAT_HELM")
  end
end

local function RemoveHatFx(inst)
  if inst._hatfx ~= nil then
    if inst._hatfx:IsValid() then
      inst._hatfx:Remove()
    end
    inst._hatfx = nil
  end
end

local function SpawnHatFx(inst, owner)
  RemoveHatFx(inst)
  local fx = SpawnPrefab("piece_box_hat_fx")
  if fx ~= nil then
    fx.entity:SetParent(owner.entity)
    fx.Follower:FollowSymbol(owner.GUID, "headbase",
      HAT_FOLLOW_OFFSET_X, HAT_FOLLOW_OFFSET_Y, HAT_FOLLOW_OFFSET_Z)
    inst._hatfx = fx
  end
end

local function OnEquip(inst, owner)
  if inst.components.container ~= nil then
    inst.components.container:Close(owner)
  end
  inst:ReturnToScene()
  inst:Hide()
  inst.Physics:SetActive(false)
  inst.DynamicShadow:Enable(false)
  inst.MiniMapEntity:SetEnabled(false)
  SpawnHatFx(inst, owner)
  ShowOwnerHatSymbols(owner)

  inst:StopBrain(EQUIPPED_BRAIN_STOP_REASON)
  if inst.sg ~= nil then
    inst.sg:GoToState("equipped")
  else
    inst.AnimState:PlayAnimation("idle_loop", true)
  end
end

local function OnUnequip(inst, owner)
  HideOwnerHatSymbols(owner)
  RemoveHatFx(inst)
  inst:RemoveFromScene()
  inst:RestartBrain(EQUIPPED_BRAIN_STOP_REASON)
end

local WAKE_TO_FOLLOW_DISTANCE = 14
local SLEEP_NEAR_LEADER_DISTANCE = 7

local function ShouldWakeUp(inst)
  return DefaultWakeTest(inst)
    or (inst.components.follower ~= nil
      and inst.components.follower:GetLeader() ~= nil
      and not inst.components.follower:IsNearLeader(WAKE_TO_FOLLOW_DISTANCE))
end

local function ShouldSleep(inst)
  return DefaultSleepTest(inst)
    and not (inst.sg ~= nil and inst.sg:HasStateTag("open"))
    and (inst.components.follower == nil
      or inst.components.follower:GetLeader() == nil
      or inst.components.follower:IsNearLeader(SLEEP_NEAR_LEADER_DISTANCE))
end

-- 按 userid 找在线玩家（读档/跨会话找回主人）
local function FindPlayerByUserid(userid)
  if userid ~= nil then
    for _, player in pairs(AllPlayers) do
      if player:IsValid() and player.userid == userid then
        return player
      end
    end
  end
  return nil
end

-- ────────────────────────────────────────────────────────
-- 拾取进物品栏：关闭容器、清旧主人登记、登记新主人为背包态
-- brain 由 inventoryitem HibernateLivingItem 自动休眠；绑定后存档由主人组件管理
-- ────────────────────────────────────────────────────────
local function OnPutInInventory(inst, owner)
  inst.components.inventoryitem.canbepickedup = false
  if inst.components.container ~= nil then
    inst.components.container:Close()
  end

  -- 清旧主人（棋盒之前跟随者）的组件登记
  local oldleader = inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
  if oldleader ~= nil and oldleader:IsValid() and oldleader.components.wang_chess_box_owner ~= nil then
    oldleader.components.wang_chess_box_owner:ClearBox(inst)
  end

  -- 记录新主人并登记为背包态：_pendingleader 瞬态，_owner_userid 持久（跨会话兜底）
  local grand = (owner ~= nil and owner.components.inventoryitem ~= nil) and owner.components.inventoryitem:GetGrandOwner() or owner
  if grand ~= nil and grand:HasTag("player") then
    inst.persists = false
    inst._pendingleader = grand
    inst._owner_userid = grand.userid
    grand.components.wang_chess_box_owner:TrackBox(inst, "inventory")
  else
    inst.persists = true
    inst._pendingleader = nil
    inst._owner_userid = nil
    if inst.components.follower ~= nil then
      inst.components.follower:SetLeader(nil)
    end
  end
end

-- ────────────────────────────────────────────────────────
-- 放下：跟随主人并登记到其组件为跟随态（存档由主人组件管理）
-- 主人来源：本次拾取记录 → 现有 follower leader → _owner_userid（跨会话找回）
-- ────────────────────────────────────────────────────────
local function OnDropped(inst)
  inst.components.inventoryitem.canbepickedup = true
  local leader = inst._pendingleader or inst.components.follower:GetLeader() or FindPlayerByUserid(inst._owner_userid)
  inst._pendingleader = nil
  if leader ~= nil and leader:IsValid() and inst.components.follower ~= nil then
    inst.persists = false
    inst.components.follower:SetLeader(leader)
    inst._owner_userid = leader:HasTag("player") and leader.userid or nil
    if leader.components.wang_chess_box_owner ~= nil then
      leader.components.wang_chess_box_owner:TrackBox(inst, "following")
    end
  else
    inst.persists = true
  end
  if inst.sg ~= nil then
    inst.sg:GoToState("idle")
  end
end

local function OnPickup(inst, pickupguy)
  if pickupguy ~= nil and pickupguy:HasTag("player")
      and pickupguy.components.wang_chess_box_owner ~= nil then
    local replace_equipped = pickupguy.components.wang_chess_box_owner:PrepareForBoxPickup(inst)
    if replace_equipped and pickupguy.components.inventory ~= nil then
      return pickupguy.components.inventory:Equip(inst) == true
    end
  end
end

local function UnbindOwner(inst)
  inst._pendingleader = nil
  inst._owner_userid = nil
  inst.persists = true
  if inst.components.follower ~= nil then
    inst.components.follower:SetLeader(nil)
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
  inst.entity:AddDynamicShadow()
  inst.entity:AddMiniMapEntity()
  inst.entity:AddNetwork()

  MakeCharacterPhysics(inst, 1, 0.5)
  inst.Physics:SetCollisionGroup(COLLISION.CHARACTERS)
  inst.Physics:SetCollisionMask(
    COLLISION.WORLD,
    COLLISION.OBSTACLES,
    COLLISION.CHARACTERS
  )

  inst:AddTag("companion")     -- 跟随者
  inst:AddTag("kitcoon")       -- 允许与其它 kitcoon 进行玩耍互动
  inst:AddTag("scarytoprey")
  inst:AddTag("notraptrigger")
  inst:AddTag("noauradamage")
  inst:AddTag("NOBLOCK")
  inst:AddTag("hat")
  inst:AddTag("waterproofer")

  inst.DynamicShadow:SetSize(1.5, 1)
  inst.MiniMapEntity:SetIcon("piece_box.tex")
  inst.MiniMapEntity:SetCanUseCache(false)
  inst.Transform:SetSixFaced()

  inst.AnimState:SetBuild("piece_box_build")
  inst.AnimState:SetBank("kitcoon")
  inst.AnimState:PlayAnimation("idle_loop", true)

  inst.entity:SetPristine()

  if not TheWorld.ismastersim then
    return inst
  end

  -- 无主地面棋盒由世界保存；绑定后切为主人组件嵌入存档。
  inst.persists = true

  inst:AddComponent("inspectable")
  inst.components.inspectable:RecordViews()

  -- 可拾取进物品栏（活物拾取）
  inst:AddComponent("inventoryitem")
  inst.components.inventoryitem.canbepickedup = true
  inst.components.inventoryitem.canbepickedupalive = true
  inst.components.inventoryitem.nobounce = true
  inst.components.inventoryitem:SetOnPickupFn(OnPickup)
  inst.components.inventoryitem:SetOnPutInInventoryFn(OnPutInInventory)
  inst.components.inventoryitem:SetOnDroppedFn(OnDropped)

  inst:AddComponent("equippable")
  inst.components.equippable.equipslot = EQUIPSLOTS.HEAD
  inst.components.equippable:SetOnEquip(OnEquip)
  inst.components.equippable:SetOnUnequip(OnUnequip)

  inst:AddComponent("insulator")
  inst.components.insulator:SetInsulation(120)

  inst:AddComponent("waterproofer")
  inst.components.waterproofer:SetEffectiveness(0.8)

  inst:AddComponent("sanityaura")
  inst.components.sanityaura.aura = TUNING.SANITYAURA_TINY

  -- 跟随移动
  inst:AddComponent("locomotor")
  inst.components.locomotor.walkspeed = 3
  inst.components.locomotor.runspeed = 7
  inst.components.locomotor.softstop = true
  inst.components.locomotor:SetTriggersCreep(false)
  inst.components.locomotor:SetAllowPlatformHopping(true)

  inst:AddComponent("follower")
  inst.components.follower.neverexpire = true
  inst.components.follower.keepleaderduringminigame = true

  -- Chester/kitcoon 的船只上下船链路。无 health 组件本身即不会受伤或死亡。
  inst:AddComponent("embarker")
  inst.components.embarker.embark_speed = inst.components.locomotor.walkspeed + 2
  inst:AddComponent("drownable")

  inst:AddComponent("sleeper")
  inst.components.sleeper.watchlight = true
  inst.components.sleeper:SetResistance(3)
  inst.components.sleeper.testperiod = GetRandomWithVariance(6, 2)
  inst.components.sleeper:SetSleepTest(ShouldSleep)
  inst.components.sleeper:SetWakeTest(ShouldWakeUp)

  -- 容器：4 格储物，内部物品无普通堆叠上限
  inst:AddComponent("container")
  inst.components.container:WidgetSetup("piece_box")
  inst.components.container.onopenfn = OnOpen
  inst.components.container.onclosefn = OnClose
  inst.components.container.canbeopened = true
  inst.components.container:EnableInfiniteStackSize(true) -- 只读属性，须用 setter（同步 replica + 现有物品 SetIgnoreMaxSize）
  inst:ListenForEvent("itemget", OnItemGet)
  inst.UnbindOwner = UnbindOwner

  -- 主人 userid 存档：跨会话"放下棋盒→找回主人"兜底（随主人组件 GetSaveRecord 一并记录）
  inst.OnSave = function(_, data)
    if inst._owner_userid ~= nil then
      data.owner_userid = inst._owner_userid
    end
  end
  inst.OnLoad = function(_, data)
    if data ~= nil and data.owner_userid ~= nil then
      inst._owner_userid = data.owner_userid
    end
  end

  inst.OnRemoveEntity = RemoveHatFx

  inst:SetStateGraph("SGpiece_box")
  inst:SetBrain(brain)

  return inst
end

local function hatfxfn()
  local inst = CreateEntity()

  inst.entity:AddTransform()
  inst.entity:AddAnimState()
  inst.entity:AddFollower()
  inst.entity:AddNetwork()

  inst.Transform:SetSixFaced()
  inst.AnimState:SetBuild("piece_box_build")
  inst.AnimState:SetBank("kitcoon")
  inst.AnimState:PlayAnimation("idle_loop", true)

  inst:AddTag("FX")
  inst:AddTag("NOCLICK")

  inst.entity:SetPristine()

  if not TheWorld.ismastersim then
    return inst
  end

  inst.persists = false

  return inst
end

return Prefab("piece_box", fn, assets, prefabs),
  Prefab("piece_box_hat_fx", hatfxfn, assets)
