table.insert(Assets, Asset("ATLAS", "images/wang_skill.xml"))
-- 望的技能配置
-- 被动：铸子 / 料敌机先（另行实现）
-- 主动：取势（精英0）/ 连星（精英1）/ 天下劫（精英2）
-- 武器：拈子剑（另行实现）
local ARK_CONSTANTS = require("ark_constants")
local Grid = require("wang_piecegrid")
local PieceResource = require("wang_piece_resource")
local Audio = require("wang_audio")

local function UpdateSkill3Camera(inst)
  if TheWorld.ismastersim or inst ~= ThePlayer or TheCamera == nil then
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
  inst:ListenForEvent("wang_skill3_active_dirty", UpdateSkill3Camera)
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
-- 技能1描述：三级共用模板（LEVEL_DESC.WANG[1] 带 %s 倍率占位）
local function WangSkill1LevelDesc(skill)
  local params = skill:GetLevelParams()
  return string.format(STRINGS.UI.ARK_SKILL.LEVEL_DESC.WANG[1], params.damageMultiplier)
end

-- 技能2描述：二级共用模板
local function WangSkill2LevelDesc(skill)
  return STRINGS.UI.ARK_SKILL.LEVEL_DESC.WANG[2]
end

-- 技能3描述：单级模板
local function WangSkill3LevelDesc(skill)
  return STRINGS.UI.ARK_SKILL.LEVEL_DESC.WANG[3]
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
-- 连星（技能2）：选区填充 + 棋子互连
-- 链路：选择器确认 → OnActivate → ①预留网格并在 0.5 秒内随机落子 → ②全选区转连接态 → ③邻格互连
-- 连接复用原版 electricconnector + piece_link_field 光束（连接/读档重连内置）
-- ③互连规则：选区内新旧棋子都参与，只连接正交相邻网格，不跨格连接
-- ════════════════════════════════════════════════════════
local WANG_SKILL2_AOE_RANGE = 6     -- 选区半径（填充 / 连接范围，大于取势的 4）
local WANG_SKILL2_CAST_RANGE = 20   -- 施法距离（玩家可远程施法）
local WANG_SKILL2_DROP_WINDOW = 0.5 -- 额外落子在此时间内随机出现，避免批量动画完全同步

-- 连星区域选择器（同取势视觉：reticuleaoe 环 + 落点 ping）
RegisterTargetSelector("wang_skill2_area", AreaTargetSelector {
  range          = WANG_SKILL2_CAST_RANGE,
  deployradius   = 0,
  reticuleprefab = "reticuleaoe_6",
  pingprefab     = "reticuleaoeping_6",
})

-- 天下劫地图选择：选择一个已部署棋子，而不是选择棋子附近的任意位置。
-- MapTargetSelector 在客户端命中全局地图代理，在服务端解析回真实 piece 实体。
RegisterTargetSelector("wang_skill3_map", MapTargetSelector {
  actionstring = STRINGS.UI.ARK_SKILL.NAMES.WANG[3],
  targetprefab = "piece",
  targettags = { "wang_piece_deployed" },
  targetrange = 5,
  mapiconprefab = "globalmapiconunderfog",
  mapicontag = "wang_piece_map_marker",
  -- 地图打开后给候选棋子添加原版风格的焦点装饰；全部字段均为可选配置。
  mapfocus = {
    bank = "courier_minimap_indicator",
    build = "courier_minimap_indicator",
    scale = 0.2
  },
})

-- ① 选区网格填充：从包里消耗棋子，按世界网格空闲格部署（近→远）
--    批量部署也播 ChuXian 出现动画（与拈子剑一致），随后转 WeiJiHuo 待机
-- 候选点 = 世界网格格中心 + 施法点偏移：吸附 OFF（默认）把施法点在其格内的偏移复制到各格，
--          保持"瞄准哪就偏哪"的手感；吸附 ON → 全部落在格中心
-- 跳过被占格（含投掷占位，与全局网格一致）与不可通行地面；包里棋子用尽即停
local function FindDeployCandidates(cx, cz)
  local grid = TUNING.WANG.PIECE_GRID_SIZE or 2
  local range = WANG_SKILL2_AOE_RANGE

  -- 施法点在其所在格内的偏移（吸附 OFF 时复制到每个填充格；ON 时 offset = 0）
  local offX, offZ = 0, 0
  if not TUNING.WANG.PIECE_GRID_SNAP then
    local ccx, ccz = Grid:CellCenterAt(cx, cz)
    offX, offZ = cx - ccx, cz - ccz
  end

  -- 枚举半径内世界网格格中心（+偏移）作为候选，按距离近→远排序
  local candidates = {}
  for gx = math.floor((cx - range) / grid), math.floor((cx + range) / grid) do
    for gz = math.floor((cz - range) / grid), math.floor((cz + range) / grid) do
      local px = (gx + 0.5) * grid + offX
      local pz = (gz + 0.5) * grid + offZ
      local distsq = (px - cx) * (px - cx) + (pz - cz) * (pz - cz)
      if distsq <= range * range
          and not Grid:IsCellTaken(px, pz)
          and TheWorld.Map:IsPassableAtPoint(px, 0, pz) then
        table.insert(candidates, { px, pz, distsq })
      end
    end
  end
  table.sort(candidates, function(a, b) return a[3] < b[3] end)
  return candidates
end

local function SchedulePiecesInArea(doer, cx, cz, oncomplete)
  local pending = {}
  for _, c in ipairs(FindDeployCandidates(cx, cz)) do
    local piece = SpawnPrefab("piece")
    piece.persists = false
    piece.Transform:SetPosition(c[1], 0, c[2])
    piece:Hide()
    if Grid:ReserveCell(piece, c[1], c[2]) then
      if PieceResource.TryConsume(doer, 1) then
        table.insert(pending, piece)
      else
        piece:Remove()
        break -- 包里棋子用尽
      end
    else
      piece:Remove()
    end
  end

  if #pending == 0 then
    if oncomplete ~= nil then
      oncomplete()
    end
    return 0
  end

  -- 不再依赖固定 0.5 秒后扫描：最后一个随机落子真正部署完成后才统一建连，
  -- 避免末批落子与 FinishLianxing 落在同一 tick 时漏进 FindEntities。
  local remaining = #pending
  for _, piece in ipairs(pending) do
    local scheduledPiece = piece
    TheWorld:DoTaskInTime(math.random() * WANG_SKILL2_DROP_WINDOW, function()
      if scheduledPiece:IsValid() then
        scheduledPiece.persists = true
        scheduledPiece:Show()
        scheduledPiece:DeployPiece({ playappear = true })
      end
      remaining = remaining - 1
      if remaining == 0 and oncomplete ~= nil then
        oncomplete()
      end
    end)
  end
  return #pending
end

local function CanAcceptLink(piece)
  if piece == nil or not piece:IsValid() or piece.components.electricconnector == nil then
    return false
  end
  local connector = piece.components.electricconnector
  return GetTableSize(connector.fields) < (connector.max_links or TUNING.WANG.PIECE_MAX_LINKS or 4)
end

local function AreGridNeighbors(ax, az, bx, bz)
  local agx, agz = Grid:CellCoord(ax, az)
  local bgx, bgz = Grid:CellCoord(bx, bz)
  local dx = math.abs(agx - bgx)
  local dz = math.abs(agz - bgz)
  return (dx == 1 and dz == 0) or (dx == 0 and dz == 1)
end

local function CanLinkPieces(p, q)
  if p == q or not CanAcceptLink(p) or not CanAcceptLink(q)
      or p.components.electricconnector.fields[q] ~= nil then
    return false
  end
  local px, _, pz = p.Transform:GetWorldPosition()
  local qx, _, qz = q.Transform:GetWorldPosition()
  return AreGridNeighbors(px, pz, qx, qz)
end

local function HasConnectablePair(pieces)
  for i = 1, #pieces - 1 do
    for j = i + 1, #pieces do
      if CanLinkPieces(pieces[i], pieces[j]) then
        return true
      end
    end
  end
  return false
end

-- ③ 互连：选区内新旧棋子都参与，只补齐正交相邻网格间的连线
-- 复用 electricconnector:ConnectTo —— 双向注册自动去重（fields 表）；满 max_links 打 fully_electrically_linked
local function LinkPiecesInArea(pieces)
  for i = 1, #pieces do
    local p = pieces[i]
    if CanAcceptLink(p) then
      local pc = p.components.electricconnector
      local px, _, pz = p.Transform:GetWorldPosition()

      local candidates = {}
      for j = 1, #pieces do
        local q = pieces[j]
        if CanLinkPieces(p, q) then
          local qx, _, qz = q.Transform:GetWorldPosition()
          table.insert(candidates, { q, (qx - px) * (qx - px) + (qz - pz) * (qz - pz) })
        end
      end
      table.sort(candidates, function(a, b) return a[2] < b[2] end)

      for _, candidate in ipairs(candidates) do
        if not CanAcceptLink(p) then
          break
        end
        if CanLinkPieces(p, candidate[1]) then
          pc:ConnectTo(candidate[1])
        end
      end
    end
  end
end

-- ════════════════════════════════════════════════════════
-- 连星 Action + sg（同取势：走施法动画后排程落子+连接）
-- 链路：技能激活 → PushBufferedAction → sg:wang_lianxing_piece 播投掷动画
--       → Frame 7 PerformBufferedAction → 0.5 秒内随机落子 → 统一连接
-- 动画来源 player_actions_deploytoss.zip（player_common 已加载）
-- ════════════════════════════════════════════════════════

local function FinishLianxing(x, z, doer)
  local pieces = TheSim:FindEntities(x, 0, z, WANG_SKILL2_AOE_RANGE, { "wang_piece_deployed" }, nil)
  for _, p in ipairs(pieces) do
    if p:IsValid() and p.EnterLinkState ~= nil then
      p:EnterLinkState()
    end
  end
  LinkPiecesInArea(pieces)
  if #pieces > 0 and doer ~= nil and doer:IsValid() then
    Audio.PlaySfx(doer, "skill2_area_explode", 0.6)
    Audio.PlaySfx(doer, "piece_place", 0.35)
  end
  ArkLogger:Debug(string.format("连星：选区(%.1f,%.1f) 连接 %d 枚黑子", x, z, #pieces))
end

-- 连星 action：fn 从 act.options 读取选区中心，排程随机落子；最后一枚完成部署后再统一连接（仅服务端执行）
AddAction("LIANXING_PIECE", "LIANXING_PIECE", function(act)
  local opts = act.options
  if opts == nil or opts.x == nil or opts.z == nil or act.doer == nil then
    return true
  end
  local x, z = opts.x, opts.z
  SchedulePiecesInArea(act.doer, x, z, function()
    FinishLianxing(x, z, act.doer)
  end)
  return true
end)
ACTIONS.LIANXING_PIECE.distance = 0

-- 共享状态（wilson / wilson_client 同一份，同框架 USE_ARK_CURRENCY 模式）：
-- 服务端 Frame 7 排程随机落子；客户端仅播动画（PerformPreviewBufferedAction 无操作）
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

local function CanCandidateLink(candidate, pieces, earlierCandidates)
  for _, piece in ipairs(pieces) do
    if CanAcceptLink(piece) then
      local px, _, pz = piece.Transform:GetWorldPosition()
      if AreGridNeighbors(candidate[1], candidate[2], px, pz) then
        return true
      end
    end
  end
  for _, earlier in ipairs(earlierCandidates) do
    if AreGridNeighbors(candidate[1], candidate[2], earlier[1], earlier[2]) then
      return true
    end
  end
  return false
end

-- 技能2激活测试（连星）：必须能让选区新增至少一条邻格连线。
-- 先检查旧子之间能否补链；需要落子时，按实际部署顺序和库存数量模拟新旧/新新连线。
local function OnWangSkill2ActivateTest(skill, params)
  if params == nil or params.targetPos == nil then
    return false, 'WANG_SKILL2_NO_LINK'
  end
  local x, y, z = params.targetPos:Get()
  local pieces = TheSim:FindEntities(x, y, z, WANG_SKILL2_AOE_RANGE, { "wang_piece_deployed" }, nil)
  if HasConnectablePair(pieces) then
    return true
  end

  local candidates = FindDeployCandidates(x, z)
  local earlierCandidates = {}
  for index, candidate in ipairs(candidates) do
    if not PieceResource.Has(skill.inst, index) then
      break
    end
    if CanCandidateLink(candidate, pieces, earlierCandidates) then
      return true
    end
    table.insert(earlierCandidates, candidate)
  end
  if TheWorld.ismastersim then
    Audio.PlaySfx(skill.inst, "skill_cancel", 0.6)
  end
  return false, 'WANG_SKILL2_NO_LINK'
end

-- 技能2激活（连星）：Push BufferedAction → sg 播连星动画 → Frame 7 fn 排程随机落子
-- 实际逻辑（落子/连接态/互连）由 action fn（LIANXING_PIECE）启动，并在最后一枚随机落子完成后统一收尾
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

  ArkLogger:Debug(string.format("连星：施法点(%.1f,%.1f) 进入施法动画", pos.x, pos.z))

  return true
end

local WANG_SKILL3_AUTO_INTERVAL = 0.25
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
  local gx, gz = Grid:CellCoord(data.x, data.z)
  local grid = TUNING.WANG.PIECE_GRID_SIZE or 2
  local pending = {}
  local bulletLimit = math.min(#WANG_SKILL3_DIRECTIONS, skill.data.bulletCount)
  for index = 1, bulletLimit do
    local direction = WANG_SKILL3_DIRECTIONS[index]
    local x = (gx + direction[1] + 0.5) * grid
    local z = (gz + direction[2] + 0.5) * grid
    if not Grid:IsCellTaken(x, z) and TheWorld.Map:IsPassableAtPoint(x, 0, z) then
      local piece = SpawnPrefab("piece")
      piece.persists = false
      piece.Transform:SetPosition(x, 0, z)
      piece:Hide()
      if Grid:ReserveCell(piece, x, z) then
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
    inst:DoTaskInTime((index - 1) * WANG_SKILL3_AUTO_INTERVAL, function()
      if entry.piece:IsValid() then
        local piece = entry.piece
        piece:Show()
        piece:DeployPiece({
          playappear = true,
          damageMultiplier = 2,
          explodeRangeMultiplier = 2,
        })
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

local function OnWangSkill3ActivateTest(skill, params)
  if not HasNianziSword(skill.inst) then
    return false, 'WANG_SKILL3_NEED_SWORD'
  end
  local target = params ~= nil and params.target or nil
  return target ~= nil and target:IsValid()
    and target.prefab == "piece" and target:HasTag("wang_piece_deployed")
end

local function OnWangSkill3Activate(skill, data)
  local inst = skill.inst
  local target = data.target
  local ox, oy, oz = inst.Transform:GetWorldPosition()
  local tx, ty, tz = target.Transform:GetWorldPosition()
  skill:SetState("origin", { x = ox, y = oy, z = oz })
  skill:SetState("target", { x = tx, y = ty, z = tz })
  skill:SetState("was_invincible", inst.components.health.invincible)
  for _ = 1, 10 do
    local item = SpawnPrefab("piece")
    if not PieceResource.Give(inst, item) then
      item:Remove()
    end
  end
  Audio.TrySayVoice(inst, "WANG_SKILL3_CAST")
  Audio.PlaySfx(inst, "skill3_start", 0.7)
  target:Remove()
end

local function OnWangSkill3ActivateEffect(skill)
  local inst = skill.inst
  local origin = skill:GetState("origin")
  local target = skill:GetState("target")
  if origin == nil or target == nil then
    return
  end
  local dummy = skill._wang_skill3_dummy
  if dummy == nil or not dummy:IsValid() then
    dummy = SpawnPrefab(inst.prefab)
    dummy.persists = false
    dummy.Transform:SetPosition(origin.x, origin.y, origin.z)
    skill._wang_skill3_dummy = dummy
  end
  inst:Hide()
  inst.components.health:SetInvincible(true)
  inst.components.locomotor:SetExternalSpeedMultiplier(inst, "wang_skill3_lock", 0)
  inst.components.locomotor:Stop()
  inst.Transform:SetPosition(target.x, target.y, target.z)
  inst._wang_skill3_active:set(true)
  Audio.PlaySfx(inst, "skill3_land", 0.7)
end

local function OnWangSkill3Deactivate(skill)
  local inst = skill.inst
  local origin = skill:GetState("origin")
  local dummy = skill._wang_skill3_dummy
  if dummy ~= nil then
    dummy:Remove()
  end
  skill._wang_skill3_dummy = nil
  if origin ~= nil then
    inst.Transform:SetPosition(origin.x, origin.y, origin.z)
  end
  inst:Show()
  inst.components.health:SetInvincible(skill:GetState("was_invincible") == true)
  inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "wang_skill3_lock")
  inst._wang_skill3_active:set(false)
  Audio.PlaySfx(inst, "skill_cancel", 0.6)
  ReturnSkill3Bullets(skill)
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
      activationEnergy = 5,       -- 消耗 SP（设定：5→3→1）
      maxActivationStacks = 5,    -- 可储存次数（设定：5→7→10）
      params = { damageMultiplier = 0.9 },
    }, {
      activationEnergy = 3,
      maxActivationStacks = 7,
      params = { damageMultiplier = 1.1 },
    }, {
      activationEnergy = 1,
      maxActivationStacks = 10,
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
      activationEnergy = 10,      -- 消耗 SP（设定：10~5）
      maxActivationStacks = 4,    -- 可储存次数（设定：4~6）
      params = {},
    }, {
      activationEnergy = 5,
      maxActivationStacks = 6,
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
    ActivateTest = OnWangSkill3ActivateTest,
    OnActivate = OnWangSkill3Activate,
    levels = { {
      -- activationEnergy = 181,     -- 消耗 SP（设定：181，开启后持续 1 SP/秒）
      activationEnergy = 10,
      maxActivationStacks = 1,
      params = {},
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
