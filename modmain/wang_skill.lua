table.insert(Assets, Asset("ATLAS", "images/wang_skill.xml"))
-- 望的技能配置
-- 被动：铸子 / 料敌机先（另行实现）
-- 主动：取势（精英0）/ 连星（精英1）/ 天下劫（精英2）
-- 武器：拈子剑（另行实现）
local ARK_CONSTANTS = require("ark_constants")

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
  for _, piece in ipairs(pieces) do
    if piece:IsValid() and piece.ActiveExplode ~= nil then
      piece:ActiveExplode(act.doer, multiplier)
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

  local x, y, z = pos:Get()
  ArkLogger:Debug(string.format("取势：选择点(%.1f,%.1f,%.1f) 主动引爆 %d 枚黑子，倍率 %.2f",
    x, y, z, #pieces, levelParams.damageMultiplier))

  return true
end

-- ════════════════════════════════════════════════════════
-- 连星（技能2）：选区填充 + 棋子互连
-- 链路：选择器确认 → OnActivate → ①网格填充(包里棋子，不重叠) → ②全选区转连接态 → ③互连
-- 连接复用原版 electricconnector + piece_link_field 光束（连接/读档重连内置）
-- ════════════════════════════════════════════════════════
local WANG_SKILL2_AOE_RANGE = 6     -- 选区半径（填充 / 连接范围，大于取势的 4）
local WANG_SKILL2_CAST_RANGE = 20   -- 施法距离（玩家可远程施法）

-- 连星区域选择器（同取势视觉：reticuleaoe 环 + 落点 ping）
RegisterTargetSelector("wang_skill2_area", AreaTargetSelector {
  range          = WANG_SKILL2_CAST_RANGE,
  deployradius   = 0,
  reticuleprefab = "reticuleaoe_6",
  pingprefab     = "reticuleaoeping_6",
})

-- ① 选区网格填充：从包里消耗棋子，按 spacing 部署到选区空闲格点（近→远）
-- 避开技能开启前已部署的棋子（不重叠）；跳过不可通行地面；包里棋子用尽即停
local function DeployPiecesInArea(doer, cx, cz)
  local spacing = TUNING.WANG.PIECE_DEPLOY_SPACING or 1
  local range = WANG_SKILL2_AOE_RANGE
  local inv = doer.components.inventory
  if inv == nil then
    return
  end

  -- 已有部署棋子（技能开启前就存在的，避免重叠部署）
  local existing = TheSim:FindEntities(cx, 0, cz, range, { "wang_piece_deployed" }, nil)
  local taken = {}
  for _, p in ipairs(existing) do
    if p:IsValid() then
      local px, _, pz = p.Transform:GetWorldPosition()
      table.insert(taken, { px, pz })
    end
  end

  -- 网格候选（从圆心向周围扩展，按距离近→远排序）
  local candidates = {}
  local steps = math.ceil(range / spacing)
  for dx = -steps, steps do
    for dz = -steps, steps do
      local gx = cx + dx * spacing
      local gz = cz + dz * spacing
      local distsq = (gx - cx) * (gx - cx) + (gz - cz) * (gz - cz)
      if distsq <= range * range then
        local free = true
        for _, t in ipairs(taken) do
          if (t[1] - gx) * (t[1] - gx) + (t[2] - gz) * (t[2] - gz) < spacing * spacing then
            free = false
            break
          end
        end
        if free and TheWorld.Map:IsPassableAtPoint(gx, 0, gz) then
          table.insert(candidates, { gx, gz, distsq })
        end
      end
    end
  end
  table.sort(candidates, function(a, b) return a[3] < b[3] end)

  -- 部署：每消耗一枚包里棋子 → 生成一个新棋子到该格点
  for _, c in ipairs(candidates) do
    if not inv:Has("piece", 1) then
      break -- 包里棋子用尽
    end
    inv:ConsumeByName("piece", 1)
    local piece = SpawnPrefab("piece")
    if piece ~= nil then
      piece:DeployPiece(Vector3(c[1], 0, c[2]))
    end
  end
end

-- ③ 互连：每棋子连到最近的非满候选，最多 max_links 条
-- 复用 electricconnector:ConnectTo —— 双向注册自动去重（fields 表）；满 max_links 打 fully_electrically_linked
local function LinkPiecesInArea(pieces)
  local maxLinks = TUNING.WANG.PIECE_MAX_LINKS or 4
  for i = 1, #pieces do
    local p = pieces[i]
    if p:IsValid() and p.components.electricconnector ~= nil then
      local pc = p.components.electricconnector
      local px, _, pz = p.Transform:GetWorldPosition()

      -- 候选：未连接过的 / 对方未满连接数的
      local candidates = {}
      for j = 1, #pieces do
        if j ~= i then
          local q = pieces[j]
          if q:IsValid() then
            local qc = q.components.electricconnector
            if qc ~= nil and pc.fields[q] == nil and GetTableSize(qc.fields) < maxLinks then
              local qx, _, qz = q.Transform:GetWorldPosition()
              table.insert(candidates, { q, (qx - px) * (qx - px) + (qz - pz) * (qz - pz) })
            end
          end
        end
      end
      table.sort(candidates, function(a, b) return a[2] < b[2] end)

      -- 就近连接；连接前再查一次对方是否已被其他棋子占满
      for _, c in ipairs(candidates) do
        if GetTableSize(pc.fields) >= maxLinks then break end
        local qc = c[1].components.electricconnector
        if GetTableSize(qc.fields) < maxLinks then
          pc:ConnectTo(c[1])
        end
      end
    end
  end
end

-- 技能2激活测试（连星）：选区有已部署棋子（可直接连接）或包里还有棋子（可填充）才合法
-- 返回 false → 不消耗技能充能
local function OnWangSkill2ActivateTest(skill, params)
  if params == nil or params.targetPos == nil then
    return false
  end
  local x, y, z = params.targetPos:Get()
  local hasAreaPieces = #TheSim:FindEntities(x, y, z, WANG_SKILL2_AOE_RANGE, { "wang_piece_deployed" }, nil) > 0
  local hasInvPieces = skill.inst.components.inventory ~= nil
    and skill.inst.components.inventory:Has("piece", 1)
  return hasAreaPieces or hasInvPieces
end

-- 技能2激活（连星）：① 网格填充 → ② 全选区已部署棋子转连接态 → ③ 互连
local function OnWangSkill2Activate(skill, data)
  local inst = skill.inst
  if data == nil or data.targetPos == nil then
    return false
  end
  local x, y, z = data.targetPos:Get()

  -- ① 用包里棋子填充选区（到满，避开已有棋子）
  DeployPiecesInArea(inst, x, z)

  -- ② 全选区已部署棋子（含新填的）→ 连接态（非激活态，不自动引爆，移除碰撞体积）
  local pieces = TheSim:FindEntities(x, y, z, WANG_SKILL2_AOE_RANGE, { "wang_piece_deployed" }, nil)
  for _, p in ipairs(pieces) do
    if p:IsValid() and p.EnterLinkState ~= nil then
      p:EnterLinkState()
    end
  end

  -- ③ 互相连接（每棋子最多连 max_links 个最近棋子）
  LinkPiecesInArea(pieces)

  ArkLogger:Debug(string.format("连星：选区(%.1f,%.1f) 连接 %d 枚黑子", x, z, #pieces))

  return true
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
    levels = { {
      activationEnergy = 181,     -- 消耗 SP（设定：181，开启后持续 1 SP/秒）
      maxActivationStacks = 1,
      params = {},
    } },
  },
}

for _, skill in ipairs(skillConfig) do
  RegisterArkSkill(skill)
end
