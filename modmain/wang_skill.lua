table.insert(Assets, Asset("ATLAS", "images/wang_skill.xml"))
-- 望的技能配置
-- 被动：铸子 / 料敌机先（另行实现）
-- 主动：取势（精英0）/ 连星（精英1）/ 天下劫（精英2）
-- 武器：拈子剑（另行实现）
local ARK_CONSTANTS = require("ark_constants")
local Grid = require("wang_piecegrid")
local PieceResource = require("wang_piece_resource")
local GetEliteBonusDamage = require("wang_piece_damage")
local Skill3MapMarkers = require("wang_skill3_mapmarkers")
local Audio = require("wang_audio")

-- 天下劫空中态只屏蔽 locomote，不把 playercontroller 整体禁用：
-- 这样方向移动不会进入 walk/run（避免隐身时脚步声），但右键落子等动作仍可正常执行。
local function ApplySkill3MovementLock(inst)
  if inst.sg == nil then
    return
  end

  local active = inst._wang_skill3_active ~= nil and inst._wang_skill3_active:value()
  if active then
    -- 同一 state 内可能被 dirty / 主动调用多次；只在尚未归属时判断并补 tag，保持幂等。
    if not inst._wang_skill3_added_overridelocomote and not inst.sg:HasStateTag("overridelocomote") then
      inst.sg:AddStateTag("overridelocomote")
      inst._wang_skill3_added_overridelocomote = true
    end
    if inst.components.locomotor ~= nil then
      inst.components.locomotor:Stop()
    end
  elseif inst._wang_skill3_added_overridelocomote then
    inst.sg:RemoveStateTag("overridelocomote")
    inst._wang_skill3_added_overridelocomote = nil
  end
end

local function OnSkill3NewState(inst)
  -- GoToState 会先重建整套 state tags，因此上一状态的“由三技能添加”记录在这里失效。
  inst._wang_skill3_added_overridelocomote = nil
  ApplySkill3MovementLock(inst)
end

-- 三技能 active 是跨主客机同步的长期状态；客户端也据此补隐藏，避免读档/重连时仅服务端 Hide 但本地仍短暂现形。
local function ApplySkill3HiddenVisual(inst)
  if inst._wang_skill3_active ~= nil and inst._wang_skill3_active:value() then
    inst:Hide()
    if inst.DynamicShadow ~= nil then
      inst.DynamicShadow:Enable(false)
    end
  end
end

local function UpdateSkill3Camera(inst)
  -- 相机是本地视觉：专服不处理，房主玩家与远程客户端都需要响应 net_bool。
  if TheNet:IsDedicated() or inst ~= ThePlayer or TheCamera == nil then
    return
  end
  if inst._wang_skill3_active:value() then
    if inst._wang_skill3_camera_state == nil then
      local minpitch, maxpitch = TheCamera:GetPitchRange()
      inst._wang_skill3_camera_state = {
        distance = TheCamera:GetDistance(),
        minpitch = minpitch,
        maxpitch = maxpitch,
        dollyzoom = TheCamera.dollyzoom,
      }
    end
    TheCamera:SetDistance(40)
    TheCamera:SetPitchRange(20, 70)
    TheCamera.dollyzoom = true
    if inst.HUD ~= nil and inst.HUD.clouds ~= nil then
      inst.HUD.clouds:Hide()
      inst.HUD.clouds_on = false
    end
  elseif inst._wang_skill3_camera_state ~= nil then
    local state = inst._wang_skill3_camera_state
    TheCamera:SetDistance(state.distance)
    TheCamera:SetPitchRange(state.minpitch, state.maxpitch)
    TheCamera.dollyzoom = state.dollyzoom
    TheCamera:Snap()
    if inst.HUD ~= nil then
      inst.HUD:UpdateClouds(TheCamera)
    end
    inst._wang_skill3_camera_state = nil
  end
end

AddPlayerPostInit(function(inst)
  inst._wang_skill3_active = net_bool(inst.GUID, "wang_skill3_active", "wang_skill3_active_dirty")
  inst:ListenForEvent("wang_skill3_active_dirty", function()
    ApplySkill3HiddenVisual(inst)
    UpdateSkill3Camera(inst)
    ApplySkill3MovementLock(inst)
  end)
  -- StateGraph 每次 GoToState 都会清空动态 state tag；监听原版 newstate 重新补移动拦截。
  inst:ListenForEvent("newstate", OnSkill3NewState)
end)

-- ════════════════════════════════════════════════════════
-- 引爆棋子 Action + sg（基于原版 throw_deploy，去掉 useitem_dir_pre 和 symbol 替换）
-- 链路：技能激活 → PushBufferedAction → sg:wang_detonate_piece 播投掷动画
--       → Frame 7 PerformBufferedAction → fn 引爆 → animover 回 idle
-- 动画来源 player_actions_deploytoss.zip（player_common 已加载）
-- ════════════════════════════════════════════════════════

-- 引爆 action：fn 从 act.options 读取引爆数据（pieces/multiplier），伤害来源 act.doer
AddAction("DETONATE_PIECE", "DETONATE_PIECE", function(act)
  local pieces = act.options ~= nil and act.options.pieces
  if pieces == nil then
    return true
  end
  local multiplier = act.options.multiplier
  local volume = math.min(0.9, 0.45 + 0.08 * math.min(#pieces, 6))
  for _, piece in ipairs(pieces) do
    if piece:IsValid() and piece.ActiveExplode ~= nil then
      piece:ActiveExplode(act.doer, multiplier, volume)
    end
  end
  return true
end)
ACTIONS.DETONATE_PIECE.distance = 0

-- 共享状态（wilson / wilson_client 同一份，同框架 USE_ARK_CURRENCY 模式）：
-- 服务端 Frame 7 执行引爆；客户端仅播动画（PerformPreviewBufferedAction 无操作）
-- 参考 throw_deploy：用 timeline FrameEvent 控制结束，不用 animover（多动画序列时 animover 会在第一个动画结束就触发）
local wangDetonateState = State {
  name = "wang_detonate_piece",
  tags = { "doing", "busy" },
  server_states = { "wang_detonate_piece" },
  onenter = function(inst, data)
    local action = inst:GetBufferedAction()
    if action ~= nil and not TheWorld.ismastersim then
      inst:PerformPreviewBufferedAction()
    end
    inst.components.locomotor:Stop()
    inst.AnimState:PlayAnimation("deploytoss_pre")
    inst.AnimState:PushAnimation("deploytoss", false)
    if action ~= nil and action.pos ~= nil then
      inst:ForceFacePoint(action:GetActionPoint():Get())
    end
  end,
  timeline = {
    FrameEvent(7, function(inst)
      if not TheWorld.ismastersim then
        return
      end
      inst:PerformBufferedAction()
    end),
    -- deploytoss_pre (8帧) + deploytoss 动画结束时退出状态
    FrameEvent(22, function(inst) inst.sg:GoToState("idle") end),
  },
}
AddStategraphState("wilson", wangDetonateState)
AddStategraphState("wilson_client", wangDetonateState)
AddStategraphActionHandler("wilson", ActionHandler(ACTIONS.DETONATE_PIECE, "wang_detonate_piece"))
AddStategraphActionHandler("wilson_client", ActionHandler(ACTIONS.DETONATE_PIECE, "wang_detonate_piece"))

-- 取势（技能1）
local WANG_SKILL1_AOE_RANGE = 4     -- 引爆范围（选择点周围）
local WANG_SKILL1_CAST_RANGE = 20   -- 施法距离（玩家可远程施法，无需走到跟前）

-- 取势范围选择器（老方案）：范围内必须有已部署黑子才显示合法（validfn）
RegisterTargetSelector("wang_piece_aoe", AreaTargetSelector {
  range          = WANG_SKILL1_CAST_RANGE, -- 施法距离（aoetargeting.range → CASTAOE distance）
  deployradius   = 0,
  reticuleprefab = "reticuleaoe",
  pingprefab     = "reticuleaoeping",
  validfn = function(selectorInst, reticule, pos)
    local x, y, z = pos:Get()
    return #TheSim:FindEntities(x, y, z, WANG_SKILL1_AOE_RANGE, { "wang_piece_deployed" }, nil) > 0
  end,
})

-- 技能描述函数：level desc 为空时 skill_desc 回退到 config 层
-- 技能1：业务倍率来自 params；储存次数属于技能框架 level config。
local function WangSkill1LevelDesc(skill)
  local params = skill:GetLevelParams()
  local levelConfig = skill:GetLevelConfig()
  return string.format(
    STRINGS.UI.ARK_SKILL.LEVEL_DESC.WANG[1],
    params.damageMultiplier,
    levelConfig.maxActivationStacks
  )
end

-- 技能2：玩法本身无额外业务 params，仅动态展示当前等级最大储存次数。
local function WangSkill2LevelDesc(skill)
  local levelConfig = skill:GetLevelConfig()
  return string.format(STRINGS.UI.ARK_SKILL.LEVEL_DESC.WANG[2], levelConfig.maxActivationStacks)
end

-- 技能3：弹药数 / 储存次数属于 level config，棋子伤害与爆炸范围倍率属于业务 params。
local function WangSkill3LevelDesc(skill)
  local params = skill:GetLevelParams()
  local levelConfig = skill:GetLevelConfig()
  return string.format(
    STRINGS.UI.ARK_SKILL.LEVEL_DESC.WANG[3],
    levelConfig.bulletCount,
    params.damageMultiplier,
    params.explodeRangeMultiplier,
    levelConfig.maxActivationStacks
  )
end

-- 技能1激活测试（取势）：确认选择后（框架传入 targetPos）检查引爆范围内是否有已部署黑子，
-- 通过则缓存 targets（非 data，不参与存档）；无引爆目标返回 false → 不消耗技能充能
local function OnWangSkill1ActivateTest(skill, params)
  local x, y, z = params.targetPos:Get()
  local pieces = TheSim:FindEntities(x, y, z, WANG_SKILL1_AOE_RANGE, { "wang_piece_deployed" }, nil)
  if #pieces == 0 then
    return false, 'WANG_SKILL1_NO_PIECES'
  end
  -- 缓存引爆目标到 skill 对象（不存 state，state 会处理存档，此缓存无需存档）
  skill._wang_skill1_targets = pieces
  return true
end

-- 技能1激活（取势）：Push BufferedAction → sg 播引爆动画 → fn 引爆（不直接触发）
local function OnWangSkill1Activate(skill, data)
  local inst = skill.inst
  if data == nil or data.targetPos == nil then
    return false, 'WANG_SKILL1_NO_PIECES'
  end
  local pos = data.targetPos

  local pieces = skill._wang_skill1_targets
  skill._wang_skill1_targets = nil
  -- 兜底：若 test 未缓存（异常路径），按 data.targetPos 重新检索
  if pieces == nil then
    local x, y, z = pos:Get()
    pieces = TheSim:FindEntities(x, y, z, WANG_SKILL1_AOE_RANGE, { "wang_piece_deployed" }, nil)
  end
  if #pieces == 0 then
    return false, 'WANG_SKILL1_NO_PIECES'
  end

  -- 传递技能倍率（棋子内部计算 基础伤害 × 倍率）
  local levelParams = skill:GetLevelParams()

  -- Push BufferedAction → action handler → sg:wang_detonate_piece 播动画 → Frame 7 引爆
  local buff = BufferedAction(inst, nil, ACTIONS.DETONATE_PIECE, nil, pos, nil, 0, true)
  buff.options.pieces = pieces
  buff.options.multiplier = levelParams.damageMultiplier
  inst:PushBufferedAction(buff)
  Audio.TrySayVoice(inst, "WANG_SKILL1_CAST")

  local x, y, z = pos:Get()
  ArkLogger:Debug(string.format("取势：选择点(%.1f,%.1f,%.1f) 主动引爆 %d 枚黑子，倍率 %.2f",
    x, y, z, #pieces, levelParams.damageMultiplier))

  return true
end

-- ════════════════════════════════════════════════════════
-- 连星（技能2）：方格四角顺时针落子并首尾成环
-- 链路：选择器确认 → 检查方格四角 → 复用已有棋子 / 补足缺子 → 0.5 秒内顺时针落下 → 按环序直连
-- 连接复用原版 electricconnector + piece_link_field 光束（连接/读档重连内置）
-- ════════════════════════════════════════════════════════
local WANG_SKILL2_HALF_SIZE = 6     -- grid_1 放大 3 倍后：中心到四角目标格在 X/Z 轴上的偏移
local WANG_SKILL2_CAST_RANGE = 20   -- 施法距离（玩家可远程施法）
local WANG_SKILL2_DROP_WINDOW = 0.5 -- 缺失棋子在此时间内按顺时针顺序全部落下
local WANG_SKILL2_CORNER_OFFSETS = {
  { -1,  1 }, -- 西北
  {  1,  1 }, -- 东北
  {  1, -1 }, -- 东南
  { -1, -1 }, -- 西南
}
local WANG_SKILL2_RING_COUNT = #WANG_SKILL2_CORNER_OFFSETS

-- 连星区域选择器：物品包 grid_1 方格指示器放大 3 倍，落点按棋子单元格中心离散吸附。
local function SnapLianxingTargetToCell(_, pos)
  if pos == nil then
    return nil
  end
  local gx, gz = Grid:WorldToCell(pos.x, pos.z)
  local x, z = Grid:CellCenter(gx, gz)
  return Vector3(x, 0, z)
end

RegisterTargetSelector("wang_skill2_area", AreaTargetSelector {
  range          = WANG_SKILL2_CAST_RANGE,
  deployradius   = 0,
  reticuleprefab = "ark_reticule_grid_1",
  pingprefab     = "reticuleaoeping_6",
  reticulescale  = 3,
  targetposfn    = SnapLianxingTargetToCell,
  ease           = false, -- 固定格点不要在相邻单元格之间平滑滑动
})

-- 天下劫地图选择：已部署棋子由 wang_skill3_mapmarkers 按固定世界网格聚合。
-- 客户端从全局地图代理库找最近聚合点；服务端直接从聚合管理器校验，避免依赖 CLASSIFIED 地图代理的 FindEntities。
local WANG_SKILL3_MAP_TARGET_RANGE = 5
local function FindWangSkill3MapMarker(_, pos)
  local x, _, z = pos:Get()
  if TheWorld.ismastersim then
    return Skill3MapMarkers:FindNearestMarker(x, z, WANG_SKILL3_MAP_TARGET_RANGE)
  end

  if GlobalMapIconsDB == nil or GlobalMapIconsDB.prefabs["wang_skill3_map_marker"] == nil then
    return nil
  end
  local closest, closestdsq
  local maxdsq = WANG_SKILL3_MAP_TARGET_RANGE * WANG_SKILL3_MAP_TARGET_RANGE
  for marker in pairs(GlobalMapIconsDB.prefabs["wang_skill3_map_marker"]) do
    if marker:IsValid() and marker:HasTag("wang_skill3_map_marker") then
      local mx, _, mz = marker.Transform:GetWorldPosition()
      local dx, dz = mx - x, mz - z
      local dsq = dx * dx + dz * dz
      if dsq <= maxdsq and (closestdsq == nil or dsq < closestdsq) then
        closest, closestdsq = marker, dsq
      end
    end
  end
  return closest
end

RegisterTargetSelector("wang_skill3_map", MapTargetSelector {
  actionstring = STRINGS.UI.ARK_SKILL.NAMES.WANG[3],
  targetfn = FindWangSkill3MapMarker,
  targetrange = WANG_SKILL3_MAP_TARGET_RANGE,
  mapiconprefab = "wang_skill3_map_marker",
  mapicontag = "wang_skill3_map_marker",
  -- 地图打开后给候选聚合点添加原版风格的焦点装饰。
  mapfocus = {
    bank = "courier_minimap_indicator",
    build = "courier_minimap_indicator",
    scale = 0.3
  },
})

-- 四个固定槽位位于 3 倍方格的四角：西北 → 东北 → 东南 → 西南，顺时针排列。
-- 每个槽位可复用目标格周围 3×3 九格内最近的已有棋子，避免围栏过于拥挤；同一棋子只复用一次。
-- 没有可复用棋子时才在对应角落目标格落新子。
local function FindReusableLianxingPiece(gx, gz, x, z, usedPieces)
  local closest, closestDistSq
  for dx = -1, 1 do
    for dz = -1, 1 do
      local piece = Grid:GetPiece(gx + dx, gz + dz)
      if piece ~= nil and not usedPieces[piece] then
        local px, _, pz = piece.Transform:GetWorldPosition()
        local distSq = (px - x) * (px - x) + (pz - z) * (pz - z)
        if closestDistSq == nil or distSq < closestDistSq then
          closest = piece
          closestDistSq = distSq
        end
      end
    end
  end
  return closest
end

local function BuildLianxingRing(cx, cz)
  local slots = {}
  local missing = 0
  local usedPieces = {}
  for index, offset in ipairs(WANG_SKILL2_CORNER_OFFSETS) do
    local x = cx + offset[1] * WANG_SKILL2_HALF_SIZE
    local z = cz + offset[2] * WANG_SKILL2_HALF_SIZE
    -- 施法中心本身已吸附格中心；±6 恰为 3 个棋子网格，四角天然仍落在格中心。
    local gx, gz = Grid:WorldToCell(x, z)
    x, z = Grid:CellCenter(gx, gz)

    local piece = FindReusableLianxingPiece(gx, gz, x, z, usedPieces)
    if piece ~= nil then
      usedPieces[piece] = true
      table.insert(slots, { index = index, x = x, z = z, piece = piece })
    elseif Grid:IsOccupied(gx, gz) or not TheWorld.Map:IsPassableAtPoint(x, 0, z) then
      return nil, 0, 'WANG_SKILL2_NO_LINK'
    else
      table.insert(slots, { index = index, x = x, z = z })
      missing = missing + 1
    end
  end
  return slots, missing
end

local function CanAcceptLink(piece)
  if piece == nil or not piece:IsValid() or piece.components.electricconnector == nil then
    return false
  end
  local connector = piece.components.electricconnector
  return GetTableSize(connector.fields) < (connector.max_links or TUNING.WANG.PIECE_MAX_LINKS or 4)
end

local function LinkLianxingRing(slots)
  local linked = 0
  for _, slot in ipairs(slots) do
    local piece = slot.piece
    if piece ~= nil and piece:IsValid() and piece.EnterLinkState ~= nil then
      piece:EnterLinkState()
    end
  end

  for index, slot in ipairs(slots) do
    local piece = slot.piece
    local nextPiece = slots[index % #slots + 1].piece
    if piece ~= nil and nextPiece ~= nil and piece:IsValid() and nextPiece:IsValid()
        and piece.components.electricconnector ~= nil and nextPiece.components.electricconnector ~= nil then
      local connector = piece.components.electricconnector
      if connector.fields[nextPiece] ~= nil then
        linked = linked + 1
      elseif CanAcceptLink(piece) and CanAcceptLink(nextPiece) then
        connector:ConnectTo(nextPiece)
        if connector.fields[nextPiece] ~= nil then
          linked = linked + 1
        end
      end
    end
  end
  return linked
end

local function FinishLianxing(slots, cx, cz, doer)
  local linked = LinkLianxingRing(slots)
  -- 暂停成环瞬时 SFX，用于确认聒噪声是否来自 skill2_area_explode；持续 linked_lp 保留。
  ArkLogger:Debug(string.format("连星：方格四角(%.1f,%.1f) 成环 %d/%d 条", cx, cz, linked, WANG_SKILL2_RING_COUNT))
end

-- 先为全部缺失槽位生成隐藏棋子并声明占格，再一次性消耗棋子，保证不会出现资源不足时的部分落子。
local function ScheduleLianxingRing(doer, cx, cz)
  local slots, missing, reason = BuildLianxingRing(cx, cz)
  if slots == nil then
    return false, reason
  end
  if missing > 0 and not PieceResource.Has(doer, missing) then
    return false, 'WANG_SKILL2_NOT_ENOUGH_PIECES'
  end

  local pending = {}
  for _, slot in ipairs(slots) do
    if slot.piece == nil then
      local piece = SpawnPrefab("piece")
      piece._baseDamage = TUNING.WANG.PIECE_BASE_DAMAGE
      piece._eliteBonusDamage = GetEliteBonusDamage(doer)
      piece._deployer = doer
      piece._deployerUserid = doer.userid
      piece.Transform:SetPosition(slot.x, 0, slot.z)
      if not piece:ReserveDeployCell() then
        piece:Remove()
        for _, pendingSlot in ipairs(pending) do
          if pendingSlot.piece:IsValid() then
            pendingSlot.piece:Remove()
          end
        end
        return false, 'WANG_SKILL2_NO_LINK'
      end
      slot.piece = piece
      table.insert(pending, slot)
    end
  end

  if #pending > 0 and not PieceResource.TryConsume(doer, #pending) then
    for _, pendingSlot in ipairs(pending) do
      if pendingSlot.piece:IsValid() then
        pendingSlot.piece:Remove()
      end
    end
    return false, 'WANG_SKILL2_NOT_ENOUGH_PIECES'
  end

  if #pending == 0 then
    FinishLianxing(slots, cx, cz, doer)
    return true
  end

  local remaining = #pending
  local interval = WANG_SKILL2_DROP_WINDOW / (WANG_SKILL2_RING_COUNT - 1)
  for _, slot in ipairs(pending) do
    TheWorld:DoTaskInTime((slot.index - 1) * interval, function()
      if slot.piece:IsValid() then
        if not slot.piece:DeployPiece({ playappear = true }) then
          slot.piece = nil -- 留作可拾取棋子，不参与本次连星。
        end
      end
      remaining = remaining - 1
      if remaining == 0 then
        FinishLianxing(slots, cx, cz, doer)
      end
    end)
  end
  return true
end

-- ════════════════════════════════════════════════════════
-- 连星 Action + sg（同取势：走施法动画后排程落子+连接）
-- 链路：技能激活 → PushBufferedAction → sg:wang_lianxing_piece 播投掷动画
--       → Frame 7 PerformBufferedAction → 0.5 秒内顺时针补齐方格四角 → 首尾成环
-- 动画来源 player_actions_deploytoss.zip（player_common 已加载）
-- ════════════════════════════════════════════════════════

-- 连星 action：fn 从 act.options 读取选区中心，按固定外围槽位落子并成环（仅服务端执行）
AddAction("LIANXING_PIECE", "LIANXING_PIECE", function(act)
  local opts = act.options
  if opts == nil or opts.x == nil or opts.z == nil or act.doer == nil then
    return true
  end
  local ok, reason = ScheduleLianxingRing(act.doer, opts.x, opts.z)
  if not ok then
    Audio.PlaySfx(act.doer, "skill_cancel", 0.6)
    if reason ~= nil and SayAndVoice ~= nil then
      SayAndVoice(act.doer, reason)
    end
  end
  return true
end)
ACTIONS.LIANXING_PIECE.distance = 0

-- 共享状态（wilson / wilson_client 同一份，同框架 USE_ARK_CURRENCY 模式）：
-- 服务端 Frame 7 排程顺时针落子；客户端仅播动画（PerformPreviewBufferedAction 无操作）
-- 与取势共用同一套投掷动画与时间轴（deploytoss_pre + deploytoss，Frame 22 回 idle）
local wangLianxingState = State {
  name = "wang_lianxing_piece",
  tags = { "doing", "busy" },
  server_states = { "wang_lianxing_piece" },
  onenter = function(inst, data)
    local action = inst:GetBufferedAction()
    if action ~= nil and not TheWorld.ismastersim then
      inst:PerformPreviewBufferedAction()
    end
    inst.components.locomotor:Stop()
    inst.AnimState:PlayAnimation("deploytoss_pre")
    inst.AnimState:PushAnimation("deploytoss", false)
    if action ~= nil and action.pos ~= nil then
      inst:ForceFacePoint(action:GetActionPoint():Get())
    end
  end,
  timeline = {
    FrameEvent(7, function(inst)
      if not TheWorld.ismastersim then
        return
      end
      inst:PerformBufferedAction()
    end),
    -- deploytoss_pre (8帧) + deploytoss 动画结束时退出状态
    FrameEvent(22, function(inst) inst.sg:GoToState("idle") end),
  },
}
AddStategraphState("wilson", wangLianxingState)
AddStategraphState("wilson_client", wangLianxingState)
AddStategraphActionHandler("wilson", ActionHandler(ACTIONS.LIANXING_PIECE, "wang_lianxing_piece"))
AddStategraphActionHandler("wilson_client", ActionHandler(ACTIONS.LIANXING_PIECE, "wang_lianxing_piece"))

-- 技能2激活测试（连星）：方格四角固定 4 个槽位，每槽可复用周围九格内已有棋子，只要求库存能补齐缺口。
local function OnWangSkill2ActivateTest(skill, params)
  if params == nil or params.targetPos == nil then
    return false, 'WANG_SKILL2_NO_LINK'
  end
  local x, _, z = params.targetPos:Get()
  local slots, missing, reason = BuildLianxingRing(x, z)
  if slots == nil then
    Audio.PlaySfx(skill.inst, "skill_cancel", 0.6)
    return false, reason or 'WANG_SKILL2_NO_LINK'
  end
  if missing > 0 and not PieceResource.Has(skill.inst, missing) then
    Audio.PlaySfx(skill.inst, "skill_cancel", 0.6)
    return false, 'WANG_SKILL2_NOT_ENOUGH_PIECES'
  end
  return true
end

-- 技能2激活（连星）：Push BufferedAction → sg 播连星动画 → Frame 7 fn 顺时针补齐方格四角并成环
local function OnWangSkill2Activate(skill, data)
  local inst = skill.inst
  if data == nil or data.targetPos == nil then
    return false, 'WANG_SKILL2_NO_LINK'
  end
  local pos = data.targetPos

  -- Push BufferedAction → action handler → sg:wang_lianxing_piece 播动画 → Frame 7 执行
  local buff = BufferedAction(inst, nil, ACTIONS.LIANXING_PIECE, nil, pos, nil, 0, true)
  buff.options.x = pos.x
  buff.options.z = pos.z
  inst:PushBufferedAction(buff)
  Audio.TrySayVoice(inst, "WANG_SKILL2_CAST")
  Audio.PlaySfx(inst, "skill2_select", 0.7)

  ArkLogger:Debug(string.format("连星：施法点(%.1f,%.1f) 进入方格四角施法动画", pos.x, pos.z))

  return true
end

-- 天下劫飞天：参考 Mon3tr 三技能 superjump 的升空 / 返回时序。
-- 升空到目标后保持隐藏，玩家本体即为空中的下棋位置；技能结束再回跳到起点。
local WANG_SKILL3_SPEED_KEY = "wang_skill3_lock"
local WANG_SKILL3_SUPERJUMP_COLOR_R = 75 / 255
local WANG_SKILL3_SUPERJUMP_COLOR_G = 110 / 255
local WANG_SKILL3_SUPERJUMP_COLOR_B = 85 / 255

local function ToggleSkill3PhysicsOff(inst)
  -- 起飞动画阶段只临时去掉碰撞；真正进入隐身驻留后交给 ark_flyer 接管完整飞行物理。
  RemovePhysicsColliders(inst)
end

local function ToggleSkill3PhysicsOn(inst)
  if not inst:HasTag("playerghost") and inst.Physics ~= nil then
    ChangeToCharacterPhysics(inst)
  end
end

local function StopSkill3InvincibilityGuard(inst)
  if inst._wang_skill3_invincible_task ~= nil then
    inst._wang_skill3_invincible_task:Cancel()
    inst._wang_skill3_invincible_task = nil
  end
end

local function StartSkill3InvincibilityGuard(inst)
  if inst.components.health ~= nil then
    inst.components.health:SetInvincible(true)
  end
  if inst._wang_skill3_invincible_task == nil then
    inst._wang_skill3_invincible_task = inst:DoPeriodicTask(FRAMES, function(player)
      if player._wang_skill3_airborne and player.components.health ~= nil then
        player.components.health:SetInvincible(true)
      end
    end)
  end
end

local function RestoreSkill3Player(inst, was_invincible)
  inst._wang_skill3_airborne = nil
  if inst._wang_skill3_added_notarget then
    inst:RemoveTag("notarget")
    inst._wang_skill3_added_notarget = nil
  end
  StopSkill3InvincibilityGuard(inst)
  if inst.components.talker ~= nil then
    inst.components.talker:StopIgnoringAll("wang_skill3")
  end

  local flyer = inst.components.ark_flyer
  if inst._wang_skill3_owns_flight then
    inst._wang_skill3_owns_flight = nil
    if flyer ~= nil and flyer:IsFlying() then
      flyer:Land()
    else
      ToggleSkill3PhysicsOn(inst)
    end
  elseif flyer == nil or not flyer:IsFlying() then
    -- 技能若在真正进入 ark_flyer 前被打断，需要把起飞动画阶段去掉的碰撞补回来。
    ToggleSkill3PhysicsOn(inst)
  end

  inst:Show()
  inst.DynamicShadow:Enable(true)
  if inst.components.health ~= nil then
    inst.components.health:SetInvincible(was_invincible == true)
  end
  if inst.components.locomotor ~= nil then
    inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, WANG_SKILL3_SPEED_KEY)
  end
  if inst._wang_skill3_active ~= nil then
    inst._wang_skill3_active:set(false)
  end
  -- 主机/专服本地也立即释放动态移动锁；远程客户端则由 dirty 事件执行同样清理。
  ApplySkill3MovementLock(inst)
end

-- 起手：完全沿用 Mon3tr 的 superjump_pre → superjump_lag 节奏。
AddStategraphState("wilson", State {
  name = "wang_skill3_takeoff_pre",
  tags = { "aoe", "doing", "busy", "nointerrupt", "nomorph", "pausepredict", "wang_skill3" },

  onenter = function(inst, data)
    if data == nil or data.targetpos == nil then
      inst.sg:GoToState("idle", true)
      return
    end
    inst.sg.statemem.data = data
    inst.components.locomotor:Stop()
    inst.components.locomotor:SetExternalSpeedMultiplier(inst, WANG_SKILL3_SPEED_KEY, 0)
    inst.AnimState:PlayAnimation("superjump_pre")
    inst.AnimState:PushAnimation("superjump_lag")
    if inst.components.playercontroller ~= nil then
      inst.components.playercontroller:RemotePausePrediction()
    end
  end,

  events = {
    EventHandler("animover", function(inst)
      if inst.AnimState:AnimDone() and inst.AnimState:IsCurrentAnimation("superjump_lag") then
        inst.sg.statemem.continue_takeoff = true
        inst.sg:GoToState("wang_skill3_takeoff", inst.sg.statemem.data)
      end
    end),
  },

  onexit = function(inst)
    if not inst.sg.statemem.continue_takeoff then
      local data = inst.sg.statemem.data
      RestoreSkill3Player(inst, data ~= nil and data.was_invincible)
    end
  end,
})

local function EnterSkill3Airborne(inst, targetpos, own_flight)
  inst._wang_skill3_airborne = true
  -- notarget 会被原版战斗和爆炸查找排除，且不会随下棋时切换 SG 状态丢失。
  if not inst:HasTag("notarget") then
    inst:AddTag("notarget")
    inst._wang_skill3_added_notarget = true
  end
  inst.components.locomotor:SetExternalSpeedMultiplier(inst, WANG_SKILL3_SPEED_KEY, 0)
  inst.components.locomotor:Stop()

  -- 隐身驻留直接进入物品包 ark_flyer 的正式飞行状态：海面、碰撞、drownable、客户端预测统一复用现成实现。
  local flyer = inst.components.ark_flyer
  inst._wang_skill3_owns_flight = own_flight == true
  if flyer ~= nil then
    if own_flight and not flyer:IsFlying() then
      flyer:TakeOff()
    end
  else
    -- 理论上前置包会给所有玩家安装 ark_flyer；保留兼容兜底。
    ToggleSkill3PhysicsOff(inst)
  end

  inst.DynamicShadow:Enable(false)
  -- 隐身驻留期间持续锁定无敌，避免其它状态/组件意外清掉 invincible 后在空中异常死亡。
  StartSkill3InvincibilityGuard(inst)
  if inst.components.talker ~= nil then
    inst.components.talker:ShutUp()
    inst.components.talker:IgnoreAll("wang_skill3")
  end
  inst:Hide()
  inst.Physics:Teleport(targetpos.x, 0, targetpos.z)
  inst._wang_skill3_active:set(true)
  ApplySkill3MovementLock(inst)
end

local function CompleteSkill3Takeoff(inst)
  if inst.sg.statemem.completed then
    return
  end
  local data = inst.sg.statemem.data
  if data == nil or data.targetpos == nil then
    inst.sg:GoToState("idle", true)
    return
  end

  inst.sg.statemem.completed = true
  EnterSkill3Airborne(inst, data.targetpos, data.own_flight)
  Audio.PlaySfx(inst, "skill3_land", 0.7)
  inst.sg:GoToState("idle", true)
end

-- 升空：参考 Mon3tr 的渐隐阶段；区别是到目标后不落地，而是保持隐藏进行空中下棋。
AddStategraphState("wilson", State {
  name = "wang_skill3_takeoff",
  tags = { "aoe", "doing", "busy", "nointerrupt", "pausepredict", "nomorph", "wang_skill3" },

  onenter = function(inst, data)
    if data == nil or data.targetpos == nil then
      inst.sg:GoToState("idle", true)
      return
    end
    inst.sg.statemem.data = data
    inst.components.locomotor:Stop()
    ToggleSkill3PhysicsOff(inst)
    inst.AnimState:PlayAnimation("superjump")
    inst.AnimState:SetMultColour(.8, .8, .8, 1)
    inst.components.colouradder:PushColour("wang_skill3", .1, .1, .1, 0)
    local pos = inst:GetPosition()
    if pos.x ~= data.targetpos.x or pos.z ~= data.targetpos.z then
      inst:ForceFacePoint(data.targetpos:Get())
    end
    inst.SoundEmitter:PlaySound("dontstarve/movement/bodyfall_dirt", nil, .4)
    inst.SoundEmitter:PlaySound("dontstarve/common/deathpoof")
    inst.sg:SetTimeout(0.5)
  end,

  onupdate = function(inst)
    if inst.sg.statemem.dalpha ~= nil and inst.sg.statemem.alpha > 0 then
      inst.sg.statemem.dalpha = math.max(.1, inst.sg.statemem.dalpha - .1)
      inst.sg.statemem.alpha = math.max(0, inst.sg.statemem.alpha - inst.sg.statemem.dalpha)
      inst.AnimState:SetMultColour(0, 0, 0, inst.sg.statemem.alpha)
    end
  end,

  timeline = {
    TimeEvent(FRAMES, function(inst)
      inst.DynamicShadow:Enable(false)
      inst.sg:AddStateTag("noattack")
      inst.components.health:SetInvincible(true)
      inst.AnimState:SetMultColour(.5, .5, .5, 1)
      inst.components.colouradder:PushColour("wang_skill3",
        WANG_SKILL3_SUPERJUMP_COLOR_R, WANG_SKILL3_SUPERJUMP_COLOR_G, WANG_SKILL3_SUPERJUMP_COLOR_B, 0)
    end),
    TimeEvent(2 * FRAMES, function(inst)
      inst.AnimState:SetMultColour(0, 0, 0, 1)
      inst.components.colouradder:PushColour("wang_skill3",
        WANG_SKILL3_SUPERJUMP_COLOR_R * .9, WANG_SKILL3_SUPERJUMP_COLOR_G * .9,
        WANG_SKILL3_SUPERJUMP_COLOR_B * .9, 0)
    end),
    TimeEvent(3 * FRAMES, function(inst)
      inst.sg.statemem.alpha = 1
      inst.sg.statemem.dalpha = .5
    end),
  },

  events = {
    EventHandler("animover", function(inst)
      if inst.AnimState:AnimDone() then
        CompleteSkill3Takeoff(inst)
      end
    end),
  },

  ontimeout = CompleteSkill3Takeoff,

  onexit = function(inst)
    inst.components.colouradder:PopColour("wang_skill3")
    inst.AnimState:SetMultColour(1, 1, 1, 1)
    if not inst.sg.statemem.completed then
      local data = inst.sg.statemem.data
      RestoreSkill3Player(inst, data ~= nil and data.was_invincible)
    end
  end,
})

local function BeginSkill3ReturnLanding(inst)
  if inst.sg.statemem.landing then
    return
  end
  inst.sg.statemem.landing = true
  local data = inst.sg.statemem.data
  RestoreSkill3Player(inst, data ~= nil and data.was_invincible)
  inst.sg:RemoveStateTag("noattack")
  inst.AnimState:PlayAnimation("superjump_land")
  inst.SoundEmitter:PlaySound("dontstarve/movement/bodyfall_dirt", nil, .35)
  inst.sg.statemem.footstep_task = inst:DoTaskInTime(0x13 * FRAMES, function(player)
    if player.sg ~= nil and player.sg.currentstate ~= nil
        and player.sg.currentstate.name == "wang_skill3_return_jump_pst"
        and player.sg.statemem.landing then
      PlayFootstep(player)
    end
  end)
end

-- 技能结束返程：先在隐身状态传回起点并退出 ark_flyer；飞行真正收束后再显示落地动画。
-- 这样 ark_flyer 的 ark_land 事件不会在可见状态下覆盖 superjump_land。
AddStategraphState("wilson", State {
  name = "wang_skill3_return_jump_pst",
  tags = { "aoe", "doing", "busy", "noattack", "pausepredict", "nomorph", "wang_skill3" },

  onenter = function(inst, data)
    if data == nil or data.targetpos == nil then
      RestoreSkill3Player(inst, data ~= nil and data.was_invincible)
      inst.sg:GoToState("idle", true)
      return
    end
    inst.sg.statemem.data = data
    inst:Hide()
    inst.Physics:Teleport(data.targetpos.x, 0, data.targetpos.z)

    local flyer = inst.components.ark_flyer
    if inst._wang_skill3_owns_flight and flyer ~= nil and flyer:IsFlying() then
      -- Land 会立即恢复地面物理/落水判定，再用约半秒把飞行高度收回 0；此时人物仍隐藏。
      inst._wang_skill3_owns_flight = nil
      flyer:Land()
      inst.sg.statemem.waiting_for_flyer = true
      inst.sg:SetTimeout(2)
    else
      BeginSkill3ReturnLanding(inst)
    end
  end,

  onupdate = function(inst)
    if inst.sg.statemem.waiting_for_flyer then
      local flyer = inst.components.ark_flyer
      if flyer == nil or not flyer:IsFlying() then
        inst.sg.statemem.waiting_for_flyer = nil
        BeginSkill3ReturnLanding(inst)
      end
    end
  end,

  ontimeout = function(inst)
    -- 极端情况下飞行组件未正常结束也不要永久卡在隐藏状态。
    inst.sg.statemem.waiting_for_flyer = nil
    BeginSkill3ReturnLanding(inst)
  end,

  events = {
    EventHandler("animover", function(inst)
      if inst.sg.statemem.landing and inst.AnimState:AnimDone()
          and inst.AnimState:IsCurrentAnimation("superjump_land") then
        inst.sg:GoToState("idle")
      end
    end),
  },

  onexit = function(inst)
    if inst.sg.statemem.footstep_task ~= nil then
      inst.sg.statemem.footstep_task:Cancel()
      inst.sg.statemem.footstep_task = nil
    end
    local data = inst.sg.statemem.data
    RestoreSkill3Player(inst, data ~= nil and data.was_invincible)
  end,
})

-- 跟随落子由每 0.25 秒一枚改为每 0.20 秒一枚：频率 ×1.25。
local WANG_SKILL3_AUTO_INTERVAL = 0.20
local WANG_SKILL3_DIRECTIONS = {
  { 0, 1 },
  { 1, 0 },
  { 0, -1 },
  { -1, 0 },
}

local function HasNianziSword(doer)
  local item = doer.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
  return item ~= nil and item.components.nianzi_sword ~= nil
end

local function ReturnSkill3Bullets(skill)
  local count = skill.data.bulletCount
  skill.data.bulletCount = 0
  for _ = 1, count do
    local item = SpawnPrefab("piece")
    if not PieceResource.Give(skill.inst, item) then
      item.Transform:SetPosition(skill.inst.Transform:GetWorldPosition())
    end
  end
  skill:SyncStatus()
end

local function OnWangSkill3ManualDeploy(inst, data)
  local skill = inst.components.ark_skill:GetSkill("wang_skill3")
  local levelParams = skill:GetLevelParams()
  local gx, gz = Grid:WorldToCell(data.x, data.z)
  local pending = {}
  local bulletLimit = math.min(#WANG_SKILL3_DIRECTIONS, skill.data.bulletCount)
  for index = 1, bulletLimit do
    local direction = WANG_SKILL3_DIRECTIONS[index]
    local cellX = gx + direction[1]
    local cellZ = gz + direction[2]
    local x, z = Grid:CellCenter(cellX, cellZ)
    if not Grid:IsOccupied(cellX, cellZ) and TheWorld.Map:IsPassableAtPoint(x, 0, z) then
      local piece = SpawnPrefab("piece")
      piece._baseDamage = TUNING.WANG.PIECE_BASE_DAMAGE
      piece._eliteBonusDamage = GetEliteBonusDamage(inst)
      piece._damageMultiplier = levelParams.damageMultiplier
      piece._explodeRangeMultiplier = levelParams.explodeRangeMultiplier
      piece._neighborMode = "square"
      piece._deployer = inst
      piece._deployerUserid = inst.userid
      piece.Transform:SetPosition(x, 0, z)
      if piece:ReserveDeployCell() then
        table.insert(pending, { piece = piece, x = x, z = z })
      else
        piece:Remove()
      end
    end
  end
  if #pending == 0 then
    if not PieceResource.HasAny(inst) then
      skill:Cancel(true)
    end
    return
  end
  skill:CutBullet(#pending)
  for index, entry in ipairs(pending) do
    entry.piece:DoTaskInTime((index - 1) * WANG_SKILL3_AUTO_INTERVAL, function()
      if entry.piece:IsValid() then
        entry.piece:DeployPiece({ playappear = true })
      end
    end)
  end
  if not PieceResource.HasAny(inst) then
    skill:Cancel(true)
  end
end

local function OnWangSkill3Install(skill)
  skill:ListenForEventWhileActivating("wang_skill3_manual_deploy", OnWangSkill3ManualDeploy)
end

local function CanStartWangSkill3(skill)
  local inst = skill.inst
  if inst.components.rider ~= nil and inst.components.rider:IsRiding() then
    return false, 'WANG_SKILL3_CANT_RIDE'
  end
  if not HasNianziSword(inst) then
    return false, 'WANG_SKILL3_NEED_SWORD'
  end
  return true
end

-- 地图选择器打开前先检查施法姿态，避免骑乘/未持剑时仍弹出地图。
local function OnWangSkill3ActivateSelectorTest(skill)
  return CanStartWangSkill3(skill)
end

local function OnWangSkill3ActivateTest(skill, params)
  -- 确认目标时再校验一次，防止选择期间装备或骑乘状态发生变化。
  local can, reason = CanStartWangSkill3(skill)
  if not can then
    return false, reason
  end
  -- 地图选择器已在主客两端把点击吸附到聚合代理中心；这里只需要聚合坐标，不依赖具体棋子实体。
  return params ~= nil and params.targetPos ~= nil
end

local function OnWangSkill3Activate(skill, data)
  local inst = skill.inst
  local targetpos = data ~= nil and data.targetPos or nil
  if targetpos == nil then
    return false
  end
  local ox, oy, oz = inst.Transform:GetWorldPosition()
  skill:SetState("origin", { x = ox, y = oy, z = oz })
  skill:SetState("target", { x = targetpos.x, y = targetpos.y, z = targetpos.z })
  skill:SetState("was_invincible", inst.components.health.invincible)
  local flyer = inst.components.ark_flyer
  skill:SetState("was_flying", flyer ~= nil and flyer:IsFlying() or false)
  for _ = 1, 10 do
    local item = SpawnPrefab("piece")
    if not PieceResource.Give(inst, item) then
      item:Remove()
    end
  end
  -- 三技能台词保留语音但不生成文字气泡；起飞前文字一旦广播，之后 ShutUp 无法可靠撤回远端 HUD。
  Audio.TrySayVoice(inst, "WANG_SKILL3_CAST", { text = false })
  Audio.PlaySfx(inst, "skill3_start", 0.7)
  return true
end

local function OnWangSkill3ActivateEffect(skill, data)
  local inst = skill.inst
  local target = skill:GetState("target")
  if target == nil then
    return
  end

  local targetpos = Vector3(target.x, target.y, target.z)
  if data ~= nil and data.source == "load" then
    -- 激活中的技能读档时直接恢复空中位置，不重复播放一次起飞。
    EnterSkill3Airborne(inst, targetpos, skill:GetState("was_flying") ~= true)
    -- 原版 playerspawner 会在加载后的约第 6 帧无条件 Show 玩家；延后一次重申隐藏即可覆盖，
    -- 不需要在整个空中阶段每帧重复处理可见性。
    inst:DoTaskInTime(10 * FRAMES, function(player)
      if player:IsValid() and player._wang_skill3_airborne
          and player._wang_skill3_active ~= nil and player._wang_skill3_active:value() then
        ApplySkill3HiddenVisual(player)
      end
    end)
    return
  end

  -- 不再生成望的假身；本体直接播放 Mon3tr 风格升空，抵达目标后隐藏在空中下棋。
  inst.sg:GoToState("wang_skill3_takeoff_pre", {
    targetpos = targetpos,
    was_invincible = skill:GetState("was_invincible") == true,
    own_flight = skill:GetState("was_flying") ~= true,
  })
end

local function OnWangSkill3Deactivate(skill)
  local inst = skill.inst
  local origin = skill:GetState("origin")
  local was_invincible = skill:GetState("was_invincible") == true

  ReturnSkill3Bullets(skill)
  Audio.PlaySfx(inst, "skill_cancel", 0.6)

  if inst._wang_skill3_airborne and origin ~= nil then
    -- 空中隐身态结束后直接回到起点进入落地段，不再播放返程升空动画。
    inst.sg:GoToState("wang_skill3_return_jump_pst", {
      targetpos = Vector3(origin.x, origin.y, origin.z),
      was_invincible = was_invincible,
    })
  else
    -- 若技能在升空完成前被强制结束，立即恢复，避免后续状态再次把人物藏起来。
    if inst.sg ~= nil and inst.sg:HasStateTag("wang_skill3") then
      inst.sg:GoToState("idle", true)
    end
    RestoreSkill3Player(inst, was_invincible)
  end

  skill:ClearState()
end

local skillConfig = {
  {
    id = 'wang_skill1', -- 取势
    name = STRINGS.UI.ARK_SKILL.NAMES.WANG[1],
    lockedDesc = STRINGS.UI.ARK_SKILL.LOCKED_DESC.WANG[1],
    -- 三级共用同一描述函数（level desc 为空时 skill_desc 回退到 config 层）
    desc = WangSkill1LevelDesc,
    atlas = "images/wang_skill.xml",
    image = "skill_icon_wang_1.tex",
    recipe_atlas = "images/wang_skill.xml",
    -- recipe_image = "wang_skill1_recipe.tex",
    recipe_image = "skill_icon_wang_1.tex",
    hotkey = KEY_Z,
    energyRecoveryMode = ARK_CONSTANTS.ENERGY_RECOVERY_MODE.AUTO, -- 自动回复
    activationMode = ARK_CONSTANTS.ACTIVATION_MODE.MANUAL,        -- 手动触发
    ActivateTest = OnWangSkill1ActivateTest,
    OnActivate = OnWangSkill1Activate,
    -- 预声明选择器（RegisterTargetSelector 声明于本文件顶部）
    targetSelector = "wang_piece_aoe",
    levels = { {
      activationEnergy = 15,       -- 消耗 SP（设定：15→13→11）
      maxActivationStacks = 3,    -- 可储存次数（设定：3→5→8）
      params = { damageMultiplier = 0.9 },
    }, {
      activationEnergy = 13,
      maxActivationStacks = 4,
      params = { damageMultiplier = 1.1 },
    }, {
      activationEnergy = 11,
      maxActivationStacks = 6,
      params = { damageMultiplier = 1.3 },
    } },
  },
  {
    id = 'wang_skill2', -- 连星
    name = STRINGS.UI.ARK_SKILL.NAMES.WANG[2],
    lockedDesc = STRINGS.UI.ARK_SKILL.LOCKED_DESC.WANG[2],
    desc = WangSkill2LevelDesc,
    atlas = "images/wang_skill.xml",
    image = "skill_icon_wang_2.tex",
    recipe_atlas = "images/wang_skill.xml",
    recipe_image = "skill_icon_wang_2.tex",
    hotkey = KEY_X,
    energyRecoveryMode = ARK_CONSTANTS.ENERGY_RECOVERY_MODE.AUTO,
    activationMode = ARK_CONSTANTS.ACTIVATION_MODE.MANUAL,
    targetSelector = "wang_skill2_area",
    ActivateTest = OnWangSkill2ActivateTest,
    OnActivate = OnWangSkill2Activate,
    levels = { {
      activationEnergy = 80,      -- 消耗 SP（设定：80→65）
      maxActivationStacks = 1,    -- 可储存次数（设定：1→2）
      params = {},
    }, {
      activationEnergy = 65,
      maxActivationStacks = 2,
      params = {},
    } },
  },
  {
    id = 'wang_skill3', -- 天下劫
    name = STRINGS.UI.ARK_SKILL.NAMES.WANG[3],
    lockedDesc = STRINGS.UI.ARK_SKILL.LOCKED_DESC.WANG[3],
    desc = WangSkill3LevelDesc,
    atlas = "images/wang_skill.xml",
    image = "skill_icon_wang_3.tex",
    recipe_atlas = "images/wang_skill.xml",
    recipe_image = "skill_icon_wang_3.tex",
    hotkey = KEY_C,
    energyRecoveryMode = ARK_CONSTANTS.ENERGY_RECOVERY_MODE.AUTO,
    activationMode = ARK_CONSTANTS.ACTIVATION_MODE.MANUAL,
    targetSelector = "wang_skill3_map",
    ActivateSelectorTest = OnWangSkill3ActivateSelectorTest,
    ActivateTest = OnWangSkill3ActivateTest,
    OnActivate = OnWangSkill3Activate,
    levels = { {
      activationEnergy = 181,     -- 消耗 SP（设定：181，开启后持续 1 SP/秒）
      maxActivationStacks = 1,
      params = {
        damageMultiplier = 2,
        explodeRangeMultiplier = 2,
      },
      bulletCount = 40,
    } },
    OnInstall = OnWangSkill3Install,
    OnActivateEffect = OnWangSkill3ActivateEffect,
    OnDeactivate = OnWangSkill3Deactivate,
  },
}

for _, skill in ipairs(skillConfig) do
  RegisterArkSkill(skill)
end
