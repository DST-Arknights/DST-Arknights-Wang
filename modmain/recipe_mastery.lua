-- 配方交流动作（recipe_mastery 组件）
-- 传授：望作为教师，把自己掌握而目标未掌握的随机配方传给目标。
-- 请教：望作为学生，从目标掌握而自己未掌握的配方中随机学习一个。
-- 两者都走右键场景动作，并共用同一套 10 秒坐姿流程：发起者锁定，目标方可主动打断；交流双方持续损失理智。

local INITIATOR_STATE = "wang_recipe_exchange"
local PARTNER_STATE = "wang_recipe_exchange_partner"
local TEACH_SIT_ANIMS = {
  { "emote_pre_sit2", "emote_loop_sit2" },
  { "emote_pre_sit4", "emote_loop_sit4" },
}

local function PlayTeachSit(inst)
  local anims = TEACH_SIT_ANIMS[math.random(#TEACH_SIT_ANIMS)]
  inst.AnimState:PlayAnimation(anims[1])
  inst.AnimState:PushAnimation(anims[2], true)
end

-- 返回 teacher 已掌握、student 尚未掌握的配方列表。
local function GetTeachDiff(teacher, student)
  local teacher_mastery = teacher ~= nil and teacher.replica.recipe_mastery or nil
  local student_mastery = student ~= nil and student.replica.recipe_mastery or nil
  if teacher_mastery == nil or student_mastery == nil then
    return {}
  end

  local candidates = {}
  local list = teacher_mastery:GetRecipeListByState(RECIPE_MASTERY_STATE.MASTERED)
  for _, name in ipairs(list) do
    if student_mastery:GetState(name) ~= RECIPE_MASTERY_STATE.MASTERED then
      table.insert(candidates, name)
    end
  end
  return candidates
end

local function CanPair(a, b)
  return a ~= nil
      and b ~= nil
      and a ~= b
      and a:IsValid()
      and b:IsValid()
      and not a:HasTag("playerghost")
      and not b:HasTag("playerghost")
      and a.components.recipe_mastery ~= nil
      and b.components.recipe_mastery ~= nil
end

local function CanTeach(teacher, student)
  return CanPair(teacher, student)
      and teacher.components.recipe_mastery:IsTeachingEnabled()
end

local function CanAsk(student, teacher)
  -- 请教是望的专属主动交互；资格沿用传授的精二 / 无持续负理智状态开关。
  return CanPair(student, teacher)
      and student.prefab == "wang"
      and student.components.recipe_mastery:IsTeachingEnabled()
end

-- 决定望对目标右键时唯一显示的交流动作：
-- 1. 双方掌握集合一致：无动作；
-- 2. 望是目标的真子集：请教；
-- 3. 其余只要望有目标不会的配方：传授（双方各有独有配方时也优先传授）。
local function GetExchangeMode(wang, target)
  local wang_mastery = wang ~= nil and wang.replica.recipe_mastery or nil
  local target_mastery = target ~= nil and target.replica.recipe_mastery or nil
  if wang_mastery == nil or target_mastery == nil then
    return nil
  end

  local wang_has_extra = false
  for _, name in ipairs(wang_mastery:GetRecipeListByState(RECIPE_MASTERY_STATE.MASTERED)) do
    if target_mastery:GetState(name) ~= RECIPE_MASTERY_STATE.MASTERED then
      wang_has_extra = true
      break
    end
  end

  local target_has_extra = false
  for _, name in ipairs(target_mastery:GetRecipeListByState(RECIPE_MASTERY_STATE.MASTERED)) do
    if wang_mastery:GetState(name) ~= RECIPE_MASTERY_STATE.MASTERED then
      target_has_extra = true
      break
    end
  end

  if not wang_has_extra and not target_has_extra then
    return nil
  end
  return wang_has_extra and "teach" or "ask"
end

local function TeachRandomRecipe(teacher, student)
  local candidates = GetTeachDiff(teacher, student)
  if #candidates == 0 then
    return false
  end
  student.components.recipe_mastery:MasterRecipe(candidates[math.random(#candidates)])
  return true
end

local SANITY_DRAIN_KEY = "wang_recipe_exchange"

local function StartExchangeSanityDrain(inst)
  local sanity = inst.components.sanity
  if sanity ~= nil then
    sanity.externalmodifiers:SetModifier(
        inst,
        -TUNING.WANG.TEACH_SANITY_TOTAL / TUNING.WANG.TEACH_DURATION,
        SANITY_DRAIN_KEY)
  end
end

local function StopExchangeSanityDrain(inst)
  local sanity = inst.components.sanity
  if sanity ~= nil then
    sanity.externalmodifiers:RemoveModifier(inst, SANITY_DRAIN_KEY)
  end
end

local TEACH_RECIPE = AddAction("TEACH_RECIPE", STRINGS.ACTIONS.TEACH_RECIPE, function(act)
  local teacher, student = act.doer, act.target
  if not CanTeach(teacher, student) or GetExchangeMode(teacher, student) ~= "teach" then
    return false
  end
  if #GetTeachDiff(teacher, student) == 0 then
    return false, "TEACH_NONE"
  end
  return true
end)
TEACH_RECIPE.priority = 5
TEACH_RECIPE.distance = 3

local ASK_RECIPE = AddAction("ASK_RECIPE", STRINGS.ACTIONS.ASK_RECIPE, function(act)
  local student, teacher = act.doer, act.target
  if not CanAsk(student, teacher) or GetExchangeMode(student, teacher) ~= "ask" then
    return false
  end
  if #GetTeachDiff(teacher, student) == 0 then
    return false, "ASK_NONE"
  end
  return true
end)
ASK_RECIPE.priority = 5
ASK_RECIPE.distance = 3

-- 传授 / 请教都只占右键动作槽，并由双方已掌握集合关系决定唯一动作。
AddComponentAction("SCENE", "recipe_mastery", function(inst, doer, actions, right)
  if not right or doer == nil or inst == doer
      or doer.prefab ~= "wang"
      or doer:HasTag("playerghost") or inst:HasTag("playerghost") then
    return
  end

  local doer_mastery = doer.replica.recipe_mastery
  local target_mastery = inst.replica.recipe_mastery
  if doer_mastery == nil or target_mastery == nil or not doer_mastery:IsTeachingEnabled() then
    return
  end

  local mode = GetExchangeMode(doer, inst)
  if mode == "teach" then
    table.insert(actions, ACTIONS.TEACH_RECIPE)
  elseif mode == "ask" then
    table.insert(actions, ACTIONS.ASK_RECIPE)
  end
end)

-- 被发起方：不带 busy，保持原版 Wilson 的 locomote / action 中断能力。
-- 是否承担“学生”身份由 data.is_student 决定，因此传授与请教可以共用这一状态。
local partnerState = State {
  name = PARTNER_STATE,
  tags = { "idle" },

  onenter = function(inst, data)
    inst.components.locomotor:Stop()
    inst:ClearBufferedAction()
    PlayTeachSit(inst)

    if TheWorld.ismastersim then
      inst.sg.statemem.initiator = data ~= nil and data.initiator or nil
      inst.sg.statemem.recipe_is_student = data ~= nil and data.is_student == true
      StartExchangeSanityDrain(inst)
    end

    -- 发起方在 10 秒整负责结算；这里多留 1 秒只作异常兜底，避免双方 timeout 同帧竞争。
    inst.sg:SetTimeout(TUNING.WANG.TEACH_DURATION + 1)
  end,

  ontimeout = function(inst)
    inst.sg:GoToState("idle")
  end,

  onexit = function(inst)
    if not TheWorld.ismastersim then
      return
    end

    StopExchangeSanityDrain(inst)

    if not inst.sg.statemem.recipe_exit_silent then
      local initiator = inst.sg.statemem.initiator
      if initiator ~= nil and initiator:IsValid() then
        initiator:PushEvent("wang_recipe_interrupted", { target = inst })
      end
    end
  end,
}

-- 发起方：busy + nointerrupt，不能靠移动/动作/受击主动或被动打断普通流程。
-- TEACH_RECIPE 时发起方是教师；ASK_RECIPE 时发起方是学生。
local initiatorState = State {
  name = INITIATOR_STATE,
  tags = { "doing", "busy", "nointerrupt" },
  server_states = { INITIATOR_STATE },

  onenter = function(inst)
    local action = inst:GetBufferedAction()
    local target = action ~= nil and action.target or nil
    local is_ask = action ~= nil and action.action == ACTIONS.ASK_RECIPE
    inst.sg.statemem.target = target
    inst.sg.statemem.is_ask = is_ask
    inst.sg.statemem.recipe_is_student = is_ask

    inst.components.locomotor:Stop()
    PlayTeachSit(inst)
    if target ~= nil and target:IsValid() then
      inst:ForceFacePoint(target.Transform:GetWorldPosition())
    end

    if not TheWorld.ismastersim then
      -- 清掉同名状态的旧缓存，避免连续交互时误把上一次服务端状态当成已确认。
      if inst.player_classified ~= nil then
        inst.player_classified.currentstate:set_local(0)
      end
      if action ~= nil then
        inst:PerformPreviewBufferedAction()
      end
      inst.sg:SetTimeout(TUNING.WANG.TEACH_DURATION + 1)
      return
    end

    if action == nil or not inst:PerformBufferedAction()
        or target == nil or not target:IsValid() or target.sg == nil then
      inst.sg:GoToState("idle")
      return
    end

    StartExchangeSanityDrain(inst)
    if is_ask then
      -- 请教时目标是教师；用通用教学台词，不要求其它角色额外提供专属文本。
      if target.components.talker ~= nil then
        target.components.talker:Say(STRINGS.CHARACTERS.GENERIC.ANNOUNCE.TEACH_RECIPE)
      end
    elseif inst.components.talker ~= nil then
      inst.components.talker:Say(STRINGS.CHARACTERS.WANG.ANNOUNCE.TEACH_RECIPE)
    end

    target:ForceFacePoint(inst.Transform:GetWorldPosition())
    target.sg:GoToState(PARTNER_STATE, {
      initiator = inst,
      is_student = not is_ask,
    })
    inst.sg:SetTimeout(TUNING.WANG.TEACH_DURATION)
  end,

  onupdate = function(inst)
    if TheWorld.ismastersim then
      return
    end

    if inst.sg:ServerStateMatches() then
      inst.sg.statemem.server_confirmed = true
    elseif inst.sg.statemem.server_confirmed
        or (inst.sg:GetTimeInState() >= 1 and inst:GetBufferedAction() == nil) then
      -- 服务端已经结束/拒绝本次交互，立即解除客户端 busy；首次确认留 1 秒网络余量。
      inst.sg:GoToState("idle", true)
    end
  end,

  events = {
    EventHandler("wang_recipe_interrupted", function(inst, data)
      if TheWorld.ismastersim and data ~= nil and data.target == inst.sg.statemem.target then
        inst.sg.statemem.interrupted = true
        if inst.components.talker ~= nil then
          inst.components.talker:Say(STRINGS.CHARACTERS.WANG.ANNOUNCE.TEACH_RECIPE_INTERRUPTED)
        end
        inst.sg:GoToState("idle")
      end
    end),
  },

  ontimeout = function(inst)
    if not TheWorld.ismastersim then
      inst.sg:GoToState("idle")
      return
    end

    local target = inst.sg.statemem.target
    local is_ask = inst.sg.statemem.is_ask == true
    if target == nil or not target:IsValid() or target.sg == nil
        or target.sg.currentstate.name ~= PARTNER_STATE
        or target.sg.statemem.initiator ~= inst
        or target.sg.statemem.recipe_is_student ~= (not is_ask) then
      inst.sg.statemem.interrupted = true
      inst.sg:GoToState("idle")
      return
    end

    local teacher = is_ask and target or inst
    local student = is_ask and inst or target
    TeachRandomRecipe(teacher, student)

    target.sg.statemem.recipe_exit_silent = true
    target.sg:GoToState("idle")
    inst.sg.statemem.completed = true
    inst.sg:GoToState("idle")
  end,

  onexit = function(inst)
    if not TheWorld.ismastersim then
      return
    end

    StopExchangeSanityDrain(inst)
    if inst.sg.statemem.completed then
      return
    end

    local target = inst.sg.statemem.target
    if target ~= nil and target:IsValid() and target.sg ~= nil
        and target.sg.currentstate.name == PARTNER_STATE
        and target.sg.statemem.initiator == inst then
      target.sg.statemem.recipe_exit_silent = true
      target.sg:GoToState("idle")
    end
  end,
}

AddStategraphState("wilson", initiatorState)
AddStategraphState("wilson_client", initiatorState)
AddStategraphState("wilson", partnerState)
AddStategraphState("wilson_client", partnerState)
AddStategraphActionHandler("wilson", ActionHandler(ACTIONS.TEACH_RECIPE, INITIATOR_STATE))
AddStategraphActionHandler("wilson_client", ActionHandler(ACTIONS.TEACH_RECIPE, INITIATOR_STATE))
AddStategraphActionHandler("wilson", ActionHandler(ACTIONS.ASK_RECIPE, INITIATOR_STATE))
AddStategraphActionHandler("wilson_client", ActionHandler(ACTIONS.ASK_RECIPE, INITIATOR_STATE))
