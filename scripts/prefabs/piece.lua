require "prefabutil"

-- 棋子网格占用表（scripts/wang_piecegrid.lua）：整图分区，每格至多 1 枚
local Grid = require "wang_piecegrid"
local Audio = require "wang_audio"
local Skill3MapMarkers = require "wang_skill3_mapmarkers"

-- ════════════════════════════════════════════════════════
-- 望的棋子（黑子）
-- 物品态（可堆叠 / 可装备投掷）→ 投掷落地转部署态
--   物品态   — 可入背包(堆叠 120) / 装备手上右键投掷(TOSS，水球模式)
--   部署态   — 地面建筑(structure)，可被锤子 / boss 摧毁；自动检测附近敌人并被动引爆
--              无实体碰撞（可走穿，间距由网格管）；进入连星态后停止陷阱检测
-- 投掷落地：生成 chester_transform_fx + wanda_attack_pocketwatch_old_fx
--           遮盖黑子出现，直接播放未激活动画(WeiJiHuo)
-- 网格约束：落点所在格已被占/被占位 → 不投掷（服务端拦截）；飞行漂移落入已占格 → 落地为可拾取物品
-- 占位：投掷起飞即打目标格占位（ReserveCell），超时自动解锁，避免连续投掷堆叠
-- 引爆：主动(1技能) / 被动(被摧毁 / 部署态接近探测命中) 三种触发，参考火药爆炸 / 蜜蜂地雷
-- 动画来源: animSource/piece/piece.scml
--   idle     — 物品态（普通物品丢地上的表现）
--   XuanZuan — 投掷飞行旋转
--   ChuXian  — 出现（拈子剑单次落子与二技能批量部署都播）
--   WeiJiHuo — 部署态待机
--   JiHuo    — 预留动画（当前无独立激活态）
-- ════════════════════════════════════════════════════════

-- 物理效果数值（一般不改动，直接放预制体；可调整数值放 modmain）
local THROW_SPEED = 15    -- 投掷水平速度
local THROW_GRAVITY = -35 -- 投掷重力（抛物线）
local THROW_AOE = 1       -- 落地伤害范围

-- 爆炸数值（modmain 可调）
local EXPLODE_RANGE = TUNING.WANG.PIECE_EXPLODE_RANGE or 4 -- 爆炸半径

-- 部署态陷阱数值
-- 引爆半径 = 伤害半径 = EXPLODE_RANGE（单一数据源，二者自动同步）
-- 注意：后续某状态（如天下劫）下该值可能翻倍，检测与伤害共用，改这一处即可
local PROX_CHECK_INTERVAL = 1 -- 部署态检测周期（秒）

-- 陷阱目标筛选（参考蜜蜂地雷 mine 组件）
-- 触发：怪物 / 动物 / 敌对角色；"player" 加入禁止表 → 玩家（含望自己）不会触发陷阱
local PROX_ONEOF_TAGS = { "monster", "character", "animal" }
local PROX_MUST_TAGS = { "_combat" }
local PROX_NO_TAGS = { "notraptrigger", "flying", "ghost", "playerghost", "spawnprotection", "player" }

RegisterInventoryItemAtlas("images/inventoryimages/piece.xml", "piece.tex")

local assets = {
  Asset("ANIM", "anim/piece.zip"),
  Asset("ANIM", "anim/swap_piece.zip"),
  Asset("ATLAS", "images/inventoryimages/piece.xml"),
  Asset("ATLAS", "images/map_icons/piece.xml"),
}

local prefabs = {
  "wang_skill3_map_marker",
}

-- ────────────────────────────────────────────────────────
-- 爆炸相关（参考游戏源码 explosive 组件 + 凯尔希二技能子弹）
-- ────────────────────────────────────────────────────────

local function SpawnFxAt(prefab, x, y, z)
  local fx = SpawnPrefab(prefab)
  if fx ~= nil then
    fx.Transform:SetPosition(x, y, z)
  end
end

-- 爆炸命中敌人时，敌人身上播放的两个特效
local function SpawnHitEnemyFx(ent)
  local x, y, z = ent.Transform:GetWorldPosition()
  SpawnFxAt("wanda_attack_shadowweapon_old_fx", x, y, z)
  SpawnFxAt("fx_dock_pop", x, y, z)
end

-- 主动爆炸额外摧毁周围建造物（参考凯尔希二技能子弹命中：collapse_small + workable:Destroy）
-- 不含已部署棋子，避免连锁引爆
local DESTROY_TAGS = { "CHOP_workable", "MINE_workable", "HAMMER_workable", "DIG_workable" }
local function DestroySurroundingBuildings(inst, source, range)
  local x, y, z = inst.Transform:GetWorldPosition()
  local ents = TheSim:FindEntities(x, y, z, range, nil,
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
local function AoEExplode(inst, source, damage, range, active, suggest)
  if active then
    DestroySurroundingBuildings(inst, source, range)
  end

  local x, y, z = inst.Transform:GetWorldPosition()
  local ents = TheSim:FindEntities(x, y, z, range, nil, { "INLIMBO", "notarget" })
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
    SpawnFxAt("chester_transform_fx", x, y, z)
  end
  SpawnFxAt("wanda_attack_pocketwatch_old_fx", x, y, z)
end

-- ────────────────────────────────────────────────────────
-- 部署态被动引爆：周期检测引爆半径内目标，命中即直接爆炸（陷阱）
-- 参考蜜蜂地雷 mine 组件（DoPeriodicTask + FindEntity）
-- 触发：怪物/动物/敌对角色（玩家不触发）；爆炸本身对所有可攻击目标造成伤害，不摧毁建造物
-- ────────────────────────────────────────────────────────
local function PassiveDetonateCheck(inst)
  local target = FindEntity(inst, EXPLODE_RANGE * inst._explodeRangeMultiplier, function(dude)
    return not (dude.components.health ~= nil and dude.components.health:IsDead())
      and dude.components.combat ~= nil and dude.components.combat:CanBeAttacked(inst)
  end, PROX_MUST_TAGS, PROX_NO_TAGS, PROX_ONEOF_TAGS)
  if target ~= nil then
    inst:PassiveExplode(nil, 1) -- 被动引爆：范围伤害、不摧毁建造物、不记击杀
  end
end

local function StartProximityTrap(inst)
  if inst._proxTask == nil then
    -- 首次检测延后一整个周期：连星会在 0.5 秒内完成外围落子并转连接态，可在第一次扫描前关闭任务。
    inst._proxTask = inst:DoPeriodicTask(PROX_CHECK_INTERVAL, PassiveDetonateCheck, PROX_CHECK_INTERVAL)
  end
end

local function StopProximityTrap(inst)
  if inst._proxTask ~= nil then
    inst._proxTask:Cancel()
    inst._proxTask = nil
  end
end

-- 读档恢复时随机待机帧，避免一批存档棋子完全同步
local function RandomizeAnimFrame(inst)
  local numFrames = inst.AnimState:GetCurrentAnimationNumFrames()
  if numFrames > 0 then
    inst.AnimState:SetFrame(math.random(numFrames) - 1)
  end
end

local function DisableEntityCollisions(inst)
  if inst.Physics ~= nil then
    inst.Physics:SetCollisionMask(COLLISION.GROUND)
    inst.Physics:Stop()
  end
end

-- 脚底动画纯客户端生成：非网络实体，不参与存档，也不在专服创建。
-- 只在棋子真正进入部署态后触发；棋子预占位时虽然实体已生成，但不会提前创建 FX。
local function CreateGroundFx(parent)
  local fx = CreateEntity()

  fx.entity:AddTransform()
  fx.entity:AddAnimState()

  fx:AddTag("FX")
  fx:AddTag("NOCLICK")
  fx.persists = false

  fx.AnimState:SetBank("piece")
  fx.AnimState:SetBuild("piece")
  fx.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
  fx.AnimState:SetLayer(LAYER_BACKGROUND)
  fx.AnimState:SetSortOrder(3)
  fx.AnimState:PlayAnimation("JiHuo_DiMian-0", false)
  fx.AnimState:SetFrame(5)
  fx.AnimState:PushAnimation("JiHuo_DiMian-1", true)

  parent:AddChild(fx)
  fx.Transform:SetPosition(0, 0, 0)
  return fx
end

local function TryCreateGroundFx(inst)
  inst._groundFxTask = nil
  if not inst._showGroundFx:value()
      or (inst._groundFx ~= nil and inst._groundFx:IsValid()) then
    return
  end
  if not inst.entity:IsVisible() then
    inst._groundFxTask = inst:DoTaskInTime(0, TryCreateGroundFx)
    return
  end
  inst._groundFx = CreateGroundFx(inst)
end

local function OnGroundFxDirty(inst)
  if inst._showGroundFx:value()
      and inst._groundFxTask == nil
      and not (inst._groundFx ~= nil and inst._groundFx:IsValid()) then
    inst._groundFxTask = inst:DoTaskInTime(0, TryCreateGroundFx)
  end
end

local function EnableGroundFx(inst)
  if not inst._showGroundFx:value() then
    inst._showGroundFx:set(true)
  end
end

-- ────────────────────────────────────────────────────────
-- 部署态：投掷落地 / 技能放置后转地面建筑
-- 无实体碰撞（棋子出生即不参与实体碰撞，部署时无需再移除碰撞体）
-- 网格注册统一走这里：投掷/拈子剑/连星/读档恢复 → 自动重建占用表
-- ────────────────────────────────────────────────────────
local function SetDeployedState(inst, deploydata)
  if inst._isdeployed then
    return
  end
  deploydata = deploydata or {}

  inst._isdeployed = true
  inst:AddTag("structure")
  inst:AddTag("wang_piece_deployed") -- 已部署标记：供 1 技能引爆检索
  DisableEntityCollisions(inst)
  inst.components.inventoryitem.canbepickedup = false
  inst.components.workable:SetWorkable(true)
  if not deploydata.silent then
    Audio.PlayPiecePlace(inst)
  end
  if deploydata.playappear then
    inst.AnimState:PlayAnimation("ChuXian", false)
    inst.AnimState:PushAnimation("WeiJiHuo", true)
  else
    inst.AnimState:PlayAnimation("WeiJiHuo", true)
    if deploydata.randomize then
      RandomizeAnimFrame(inst)
    end
  end
  EnableGroundFx(inst)

  -- 注册网格占用（异常路径兜底：正常部署前调用方已查 IsCellTaken）
  if TheWorld.ismastersim then
    local x, _, z = inst.Transform:GetWorldPosition()
    if not Grid:TryOccupy(x, z, inst) then
      ArkLogger:Debug("棋子部署但所在格已被占用（异常路径）")
    end
    Skill3MapMarkers:Register(inst)
  end

  -- 普通部署态即为陷阱态；连星会在 EnterLinkState 中关闭检测。
  StartProximityTrap(inst)
end

-- ────────────────────────────────────────────────────────
-- 投掷落地（complexprojectile onhit）：
-- 落点附近伤害 + 清投掷占位 + 按落点格占用 → 特效遮盖 + 转部署态（不播出现动画）
-- 落点格被占（漂移边界）→ 不部署，落地为可拾取物品（不浪费）
-- ────────────────────────────────────────────────────────
local function OnTossHit(inst, attacker)
  local x, y, z = inst.Transform:GetWorldPosition()
  Audio.PlaySfx(inst, "piece_projectile_hit", 0.55)

  local ents = TheSim:FindEntities(x, y, z, THROW_AOE, nil, { "INLIMBO", "playerghost" })
  for _, ent in ipairs(ents) do
    if ent ~= nil and ent:IsValid() and ent.components.combat ~= nil
        and attacker ~= nil and attacker:IsValid() then
      ent.components.combat:GetAttacked(attacker, TUNING.WANG.PIECE_THROW_DAMAGE)
    end
  end

  -- 网格：清起飞时打的占位 → 落点（吸附可选）查占用 → 被占则不部署
  if TheWorld.ismastersim then
    Grid:Detach(inst)
    local sx, sz = Grid:SnapPos(x, z) -- 吸附 ON → 格中心
    if sx ~= x or sz ~= z then
      inst.Transform:SetPosition(sx, y, sz)
      x, z = sx, sz
    end
    if Grid:IsCellTaken(x, z) then
      -- 落点格被占：恢复物品态待机动画（投掷飞行中播的是 XuanZuan 旋转）
      inst.AnimState:PlayAnimation("idle", true)
      return -- 保持物品态，可直接拾取回收
    end
  end

  -- 特效遮盖黑子生成过程（同主动爆炸特效）
  SpawnExplodeFx(inst, true)

  SetDeployedState(inst)
end

-- ────────────────────────────────────────────────────────
-- 装备手上显示
-- ────────────────────────────────────────────────────────
local function OnEquip(inst, owner)
  owner.AnimState:OverrideSymbol("swap_object", "swap_piece", "swap_object")
  owner.AnimState:Show("ARM_carry")
  owner.AnimState:Hide("ARM_normal")
end

local function OnUnequip(inst, owner)
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

local function ReticuleTargetFn()
  return TheInput:GetWorldPosition()
end

local function CanTossInWorld(_, _, pos)
  return not Grid:IsCellTakenForAction(pos.x, pos.z)
end

local function OnTossLaunch(inst, _, targetPos)
  inst.AnimState:PlayAnimation("XuanZuan", true)
  Audio.PlaySfx(inst, "piece_projectile_start", 0.5)
  Grid:ReserveCell(inst, targetPos.x, targetPos.z)
end

local function OnRemove(inst)
  StopProximityTrap(inst)
  Skill3MapMarkers:Unregister(inst)
  Grid:Detach(inst)
end

local function OnSave(inst, data)
  if inst._isdeployed then
    data.isdeployed = true
  end
  if inst._islinked then
    data.islinked = true
  end
  if inst._damageMultiplier ~= 1 then
    data.damageMultiplier = inst._damageMultiplier
  end
  if inst._explodeRangeMultiplier ~= 1 then
    data.explodeRangeMultiplier = inst._explodeRangeMultiplier
  end
end

local function OnLoad(inst, data)
  if data == nil then
    return
  end

  inst._damageMultiplier = data.damageMultiplier or 1
  inst._explodeRangeMultiplier = data.explodeRangeMultiplier or 1

  if data.isdeployed then
    SetDeployedState(inst, { silent = true, randomize = true })
  end
  if data.islinked then
    inst:EnterLinkState()
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
  DisableEntityCollisions(inst)

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
  inst.components.reticule.targetfn = ReticuleTargetFn

  -- 投掷落点网格门禁：目标格已被占（含占位）→ 不显示 TOSS（UI 层）
  -- 服务端权威拦截在 modmain/wang_piecegrid.lua（包 ACTIONS.TOSS.fn）
  inst.CanTossInWorld = CanTossInWorld

  -- 部署是一次性状态，用父棋子的 1 bit net_bool 通知各客户端创建本地脚底 FX。
  -- FX 自身完全不联网；专服只同步这个已有实体上的状态位。
  inst._showGroundFx = net_bool(inst.GUID, "piece._showGroundFx", "piece_groundfxdirty")
  if not TheNet:IsDedicated() then
    inst:ListenForEvent("piece_groundfxdirty", OnGroundFxDirty)
  end

  inst.entity:SetPristine()

  if not TheWorld.ismastersim then
    return inst
  end

  inst._isdeployed = false
  inst._islinked = false -- 连接态（连星）标志
  inst._proxTask = nil   -- 仅普通部署态运行；连星/物品等其它状态均关闭

  -- 移除时释放网格占用（爆炸/锤毁/投掷异常等一律兜底）
  inst:ListenForEvent("onremove", OnRemove)

  inst:AddComponent("inspectable")

  inst:AddComponent("inventoryitem")

  -- 可堆叠（系统最大堆叠数）
  inst:AddComponent("stackable")
  inst.components.stackable.maxsize = TUNING.STACK_SIZE_PELLET

  -- 装备手上（equipstack：从堆叠分出单个装备，投掷即消耗一个）
  inst:AddComponent("equippable")
  inst.components.equippable.equipslot = EQUIPSLOTS.HANDS
  inst.components.equippable.equipstack = true
  inst.components.equippable:SetOnEquip(OnEquip)
  inst.components.equippable:SetOnUnequip(OnUnequip)

  -- 投掷：item 本身作为抛物线投掷物（waterballoon 模式）
  -- 投掷 = 消耗：TOSS 把装备的单个黑子丢出，落地转部署态，堆叠中其余保留
  inst:AddComponent("complexprojectile")
  inst.components.complexprojectile:SetHorizontalSpeed(THROW_SPEED)
  inst.components.complexprojectile:SetGravity(THROW_GRAVITY)
  inst.components.complexprojectile:SetLaunchOffset(Vector3(0.25, 1, 0))
  inst.components.complexprojectile:SetTargetOffset(Vector3(0, 1.5, 0)) -- 终点Y轴抬高，匹配部署飘浮动画
  inst.components.complexprojectile:SetOnHit(OnTossHit)
  -- 投掷飞行中播放旋转动画，并给目标格打占位（避免连续投掷堆叠）
  inst.components.complexprojectile:SetOnLaunch(OnTossLaunch)

  -- 部署态可被锤子 / boss 摧毁
  inst:AddComponent("workable")
  inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
  inst.components.workable:SetWorkLeft(1)
  inst.components.workable:SetOnFinishCallback(OnHammered)
  inst.components.workable:SetWorkable(false)

  -- 连接态（连星）：复用原版 electricconnector，连接/断开/读档重连全内置
  -- max_links=4（每棋子最多连 4 个）；field_prefab 为连接光束（仅视觉，电击后续接入）
  -- 组件惰性：只有 EnterLinkState 后 ConnectTo 才真正建连，平时无副作用
  inst:AddComponent("electricconnector")
  inst.components.electricconnector.max_links = TUNING.WANG.PIECE_MAX_LINKS or 4
  inst.components.electricconnector.field_prefab = "piece_link_field"
  -- 组件构造会打 electric_connector 标签，导致原版麻刺节点(Fence)自动搜索时找到棋子，
  -- 而棋子无状态机(sg) → CanLinkTo 里 IsLinking() 崩溃。移除标签：棋子只按技能直连，不参与自动搜索
  inst:RemoveTag("electric_connector")
  -- 取消该组件的菜单动作注册：连接(连星)完全由技能 ConnectTo 管理，不向玩家暴露原版
  -- 手动操作（左键"打开连接"=STARTELECTRICLINK / 右键"断开连接"=ENDELECTRICLINK）
  inst:UnregisterComponentActions("electricconnector")

  -- 部署/连接状态存档；普通部署态读档后自动恢复陷阱，连星态随后关闭；electricconnector 自行重连
  inst.OnSave = OnSave
  inst.OnLoad = OnLoad

  -- ────────────────────────────────────────────────────────
  -- 引爆方法（挂在棋子实例上，仅部署态有效）
  -- ────────────────────────────────────────────────────────

  -- 棋子基础伤害（内置，便于不同品质/类型扩展）
  inst._baseDamage = TUNING.WANG.PIECE_BASE_DAMAGE
  inst._damageMultiplier = 1
  inst._explodeRangeMultiplier = 1

  -- 主动引爆（1技能取势调用）：范围伤害 + 摧毁周围建造物 + 双特效
  -- multiplier: 技能倍率（如 0.9 / 1.1 / 1.3），实际伤害 = 基础伤害 × 倍率
  inst.ActiveExplode = function(_, source, multiplier, sfx_volume)
    if not inst._isdeployed then return end
    local damage = inst._baseDamage * inst._damageMultiplier * (multiplier or 1)
    local range = EXPLODE_RANGE * inst._explodeRangeMultiplier
    AoEExplode(inst, source, damage, range, true)
    SpawnExplodeFx(inst, true)
    Audio.PlaySfx(inst, "skill1_active_explode", sfx_volume or 0.6)
    inst:Remove()
  end

  -- 被动引爆（被锤子 / boss 摧毁时触发）：范围伤害，仅单特效，不摧毁建造物
  -- multiplier: 倍率，默认 1（被动引爆无技能加成）
  inst.PassiveExplode = function(_, source, multiplier)
    if not inst._isdeployed then return end
    local damage = inst._baseDamage * inst._damageMultiplier * (multiplier or 1)
    local range = EXPLODE_RANGE * inst._explodeRangeMultiplier
    AoEExplode(inst, inst, damage, range, false, source)
    SpawnExplodeFx(inst, false)
    Audio.PlaySfx(inst, "piece_passive_explode", 0.65)
    inst:Remove()
  end

  -- 连接态（连星）：关闭普通部署态的接近陷阱，只保留连接行为。
  -- 连接本身由 electricconnector 管理（ConnectTo 建连 / 读档 LoadPostPass 重连）
  -- 可重复调用（幂等）：已是连接态则直接返回
  inst.EnterLinkState = function(_)
    if not inst._isdeployed or inst._islinked then
      return
    end
    inst._islinked = true
    StopProximityTrap(inst)
  end

  -- 落子部署（拈子剑 / 连星复用）：调用方先设置 Transform，再进入部署态
  -- deploydata.playappear=true 时先播 ChuXian，再转 WeiJiHuo
  -- 仅主世界可调用
  inst.DeployPiece = function(_, deploydata)
    if inst._isdeployed then return end
    deploydata = deploydata or {}
    inst._damageMultiplier = deploydata.damageMultiplier or 1
    inst._explodeRangeMultiplier = deploydata.explodeRangeMultiplier or 1
    SetDeployedState(inst, deploydata)
  end

  return inst
end

return Prefab("piece", fn, assets, prefabs)
