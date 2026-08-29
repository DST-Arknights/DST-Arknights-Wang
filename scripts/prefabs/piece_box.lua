-- ════════════════════════════════════════════════════════
-- 兽形棋盒（跟随容器，宠物式存在）
-- 动画：复用 catcoon（bank=catcoon / build=catcoon_build），后续切换棋盒专属 build
-- 跟随：参考切斯特（brain 跟随 follower.leader），leader = 放下它的建造者/持有者
-- 拾取：inventoryitem canbepickedup(alive)，左键拾取进物品栏（右键打开由容器接管）
-- 容器：4 格储物，infinitestacksize = 无普通堆叠上限（容器组件 SetIgnoreMaxSize）
-- 宠物式存在（随主人上下线消失/重现，存档由主人管理）：
--   全程 persists=false → inv/世界档均不存（inv:OnSave 跳过 persists=false，
--                         读档不会重复触发进包事件），存档唯一来源是主人
--                         wang_chess_box_owner 组件（捕获 GetSaveRecord 含容器）
--   进出背包事件（SetOnPutInInventoryFn/SetOnDroppedFn）驱动主人组件 TrackBox 记录模式
-- 交互（原版动作解析天然支持）：左键 PICKUP(优先级1) / 右键 RUMMAGE(打开,-1)
--       有 container 且无 equippable → 右键不提供 PICKUP（componentactions 477 行）
-- 穿戴（头戴保暖/防水）、回san光环、偷吃等后续实现
-- ════════════════════════════════════════════════════════

local brain = require "brains/piece_boxbrain"

local assets = {
  Asset("ANIM", "anim/catcoon_basic.zip"),
  Asset("ANIM", "anim/catcoon_actions.zip"),
  Asset("ANIM", "anim/catcoon_build.zip"),
}

-- ────────────────────────────────────────────────────────
-- 容器开关 → SG 播打开/关闭动画
-- ────────────────────────────────────────────────────────
local function OnOpen(inst)
  if inst.sg ~= nil then
    inst.sg:GoToState("open")
  end
end

local function OnClose(inst)
  if inst.sg ~= nil then
    inst.sg:GoToState("close")
  end
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
-- brain 由 inventoryitem HibernateLivingItem 自动休眠；存档由主人组件管（全程 persists=false）
-- ────────────────────────────────────────────────────────
local function OnPutInInventory(inst, owner)
  inst.components.inventoryitem.canbepickedup = false
  if inst.components.container ~= nil then
    inst.components.container:Close()
  end

  -- 清旧主人（棋盒之前跟随者）的组件登记
  local oldleader = inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
  if oldleader ~= nil and oldleader:IsValid() and oldleader.components.wang_chess_box_owner ~= nil then
    oldleader.components.wang_chess_box_owner:ClearBox()
  end

  -- 记录新主人并登记为背包态：_pendingleader 瞬态，_owner_userid 持久（跨会话兜底）
  local grand = (owner ~= nil and owner.components.inventoryitem ~= nil) and owner.components.inventoryitem:GetGrandOwner() or owner
  if grand ~= nil and grand:HasTag("player") then
    inst._pendingleader = grand
    inst._owner_userid = grand.userid
    grand.components.wang_chess_box_owner:TrackBox(inst, "inventory")
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
    inst.components.follower:SetLeader(leader)
    inst._owner_userid = leader:HasTag("player") and leader.userid or nil
    if leader.components.wang_chess_box_owner ~= nil then
      leader.components.wang_chess_box_owner:TrackBox(inst, "following")
    end
  end
  if inst.sg ~= nil then
    inst.sg:GoToState("idle")
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
  inst.entity:AddNetwork()

  MakeCharacterPhysics(inst, 1, 0.5)
  inst.Physics:SetCollisionGroup(COLLISION.CHARACTERS)
  inst.Physics:SetCollisionMask(
    COLLISION.WORLD,
    COLLISION.OBSTACLES,
    COLLISION.CHARACTERS
  )

  inst:AddTag("companion")     -- 跟随者
  inst:AddTag("scarytoprey")
  inst:AddTag("notraptrigger")
  inst:AddTag("noauradamage")
  inst:AddTag("NOBLOCK")

  inst.DynamicShadow:SetSize(1.5, 1)
  inst.Transform:SetFourFaced()

  inst.AnimState:SetBank("catcoon")
  inst.AnimState:SetBuild("catcoon_build")
  inst.AnimState:PlayAnimation("idle_loop", true)

  inst.entity:SetPristine()

  if not TheWorld.ismastersim then
    return inst
  end

  -- 存档由主人 wang_chess_box_owner 组件全权管理（inv/世界档均不存，避免双重存档/读档重复触发）
  inst.persists = false

  inst:AddComponent("inspectable")
  inst.components.inspectable.descriptionfn = function()
    return STRINGS.CHARACTERS.WANG.WANG_CHESS_BOX_DESC
  end
  inst.components.inspectable:RecordViews()

  -- 可拾取进物品栏（活物拾取）
  inst:AddComponent("inventoryitem")
  inst.components.inventoryitem.canbepickedup = true
  inst.components.inventoryitem.canbepickedupalive = true
  inst.components.inventoryitem.nobounce = true
  -- 物品图标占位：暂用黑子图标（等棋盒图标资源补齐后替换）
  inst.components.inventoryitem.atlasname = "images/inventoryimages/piece.xml"
  inst.components.inventoryitem.imagename = "piece.tex"
  inst.components.inventoryitem:SetOnPutInInventoryFn(OnPutInInventory)
  inst.components.inventoryitem:SetOnDroppedFn(OnDropped)

  -- 跟随移动
  inst:AddComponent("locomotor")
  inst.components.locomotor.walkspeed = 3
  inst.components.locomotor.runspeed = 7
  inst.components.locomotor:SetAllowPlatformHopping(true)

  inst:AddComponent("follower")

  -- 容器：4 格储物，内部物品无普通堆叠上限
  inst:AddComponent("container")
  inst.components.container:WidgetSetup("piece_box")
  inst.components.container.onopenfn = OnOpen
  inst.components.container.onclosefn = OnClose
  inst.components.container.canbeopened = true
  inst.components.container:EnableInfiniteStackSize(true) -- 只读属性，须用 setter（同步 replica + 现有物品 SetIgnoreMaxSize）

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

  inst:SetStateGraph("SGpiece_box")
  inst:SetBrain(brain)

  return inst
end

return Prefab("piece_box", fn, assets)
