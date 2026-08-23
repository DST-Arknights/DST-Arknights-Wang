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

-- 技能1描述：三级共用模板（LEVEL_DESC.WANG[1][1] 带 %s 倍率占位）
local function WangSkill1LevelDesc(skill)
  local params = skill:GetLevelParams()
  return string.format(STRINGS.UI.ARK_SKILL.LEVEL_DESC.WANG[1], params.damageMultiplier)
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
    atlas = "images/wang_skill.xml",
    image = "skill_icon_wang_2.tex",
    recipe_atlas = "images/wang_skill.xml",
    recipe_image = "skill_icon_wang_2.tex",
    hotkey = KEY_X,
    energyRecoveryMode = ARK_CONSTANTS.ENERGY_RECOVERY_MODE.AUTO,
    activationMode = ARK_CONSTANTS.ACTIVATION_MODE.MANUAL,
    levels = { {
      desc = STRINGS.UI.ARK_SKILL.LEVEL_DESC.WANG[2][1],
      activationEnergy = 10,      -- 消耗 SP（设定：10~5）
      maxActivationStacks = 4,    -- 可储存次数（设定：4~6）
      params = {},
    }, {
      desc = STRINGS.UI.ARK_SKILL.LEVEL_DESC.WANG[2][2],
      activationEnergy = 5,
      maxActivationStacks = 6,
      params = {},
    } },
  },
  {
    id = 'wang_skill3', -- 天下劫
    name = STRINGS.UI.ARK_SKILL.NAMES.WANG[3],
    lockedDesc = STRINGS.UI.ARK_SKILL.LOCKED_DESC.WANG[3],
    atlas = "images/wang_skill.xml",
    image = "skill_icon_wang_3.tex",
    recipe_atlas = "images/wang_skill.xml",
    recipe_image = "skill_icon_wang_3.tex",
    hotkey = KEY_C,
    energyRecoveryMode = ARK_CONSTANTS.ENERGY_RECOVERY_MODE.AUTO,
    activationMode = ARK_CONSTANTS.ACTIVATION_MODE.MANUAL,
    levels = { {
      desc = STRINGS.UI.ARK_SKILL.LEVEL_DESC.WANG[3][1],
      activationEnergy = 181,     -- 消耗 SP（设定：181，开启后持续 1 SP/秒）
      maxActivationStacks = 1,
      params = {},
    } },
  },
}

for _, skill in ipairs(skillConfig) do
  RegisterArkSkill(skill)
end
