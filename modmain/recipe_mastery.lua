-- 配方教学动作（recipe_mastery 组件，通用——教学者不限于望）
-- 采集器：双方都有掌握组件 + 执行者可传授开关开即可显示
-- 流程：教师进入不可主动打断的坐姿，学生进入可自行打断的坐姿；持续 10 秒后随机传授一个配方。

local TEACHER_STATE = "wang_teach_recipe"
local STUDENT_STATE = "wang_learn_recipe"
local TEACH_SIT_ANIMS = {
  { "emote_pre_sit2", "emote_loop_sit2" },
  { "emote_pre_sit4", "emote_loop_sit4" },
}

local function PlayTeachSit(inst)
  local anims = TEACH_SIT_ANIMS[math.random(#TEACH_SIT_ANIMS)]
  inst.AnimState:PlayAnimation(anims[1])
  inst.AnimState:PushAnimation(anims[2], true)
end

-- diff 双方已掌握列表：返回可教的配方（服务端）
local function GetTeachDiff(teacher, target)
  local teacher_mastery = teacher ~= nil and teacher.replica.recipe_mastery or nil
  local target_mastery = target ~= nil and target.replica.recipe_mastery or nil
  if teacher_mastery == nil or target_mastery == nil then
    return {}
  end

  local candidates = {}
  local list = teacher_mastery:GetRecipeListByState(RECIPE_MASTERY_STATE.MASTERED)
  for _, name in ipairs(list) do
    if target_mastery:GetState(name) ~= RECIPE_MASTERY_STATE.MASTERED then
      table.insert(candidates, name)
    end
  end
  return candidates
end

local function CanTeach(teacher, target)
  return teacher ~= nil
      and target ~= nil
      and teacher ~= target
      and teacher:IsValid()
      and target:IsValid()
      and not teacher:HasTag("playerghost")
      and not target:HasTag("playerghost")
      and teacher.components.recipe_mastery ~= nil
      and target.components.recipe_mastery ~= nil
      and teacher.components.recipe_mastery:IsTeachingEnabled()
end

local function TeachRandomRecipe(teacher, target)
  if not CanTeach(teacher, target) then
    return false
  end
  local candidates = GetTeachDiff(teacher, target)
  if #candidates == 0 then
    return false
  end
  target.components.recipe_mastery:MasterRecipe(candidates[math.random(#candidates)])
  return true
end

local function DrainStudentSanity(inst, amount)
  if amount <= 0 or inst.components.sanity == nil then
    return
  end
  inst.components.sanity:DoDelta(-amount)
  inst.sg.statemem.teach_sanity_drained = (inst.sg.statemem.teach_sanity_drained or 0) + amount
end

local function FinishStudentSanityDrain(inst)
  local drained = inst.sg.statemem.teach_sanity_drained or 0
  local remain = TUNING.WANG.TEACH_SANITY_TOTAL - drained
  if remain > 0 then
    DrainStudentSanity(inst, remain)
  end
end

local TEACH_RECIPE = AddAction("TEACH_RECIPE", STRINGS.ACTIONS.TEACH_RECIPE, function(act)
  local teacher, target = act.doer, act.target
  if not CanTeach(teacher, target) then
    return false
  end
  if #GetTeachDiff(teacher, target) == 0 then
    return false, "TEACH_NONE"
  end
  return true
end)
TEACH_RECIPE.priority = 5
TEACH_RECIPE.distance = 3

-- 采集器（双方都要有掌握组件；可传授开关读取自副本网络变量）
AddComponentAction("SCENE", "recipe_mastery", function(inst, doer, actions, right)
  if doer == nil or inst == doer or doer:HasTag("playerghost") or inst:HasTag("playerghost") then
    return
  end
  local doer_mastery = doer.replica.recipe_mastery
  local target_mastery = inst.replica.recipe_mastery
  if doer_mastery == nil or target_mastery == nil then
    return
  end
  if not doer_mastery:IsTeachingEnabled() then
    return
  end
  table.insert(actions, ACTIONS.TEACH_RECIPE)
end)

-- 被传授方：不带 busy，保持原版 Wilson 的 locomote / action 中断能力。
local studentState = State {
  name = STUDENT_STATE,
  tags = { "idle" },

  onenter = function(inst, data)
    inst.components.locomotor:Stop()
    inst:ClearBufferedAction()
    PlayTeachSit(inst)

    if TheWorld.ismastersim then
      inst.sg.statemem.teacher = data ~= nil and data.teacher or nil
      inst.sg.statemem.teach_sanity_drained = 0
      local per_second = TUNING.WANG.TEACH_SANITY_TOTAL / TUNING.WANG.TEACH_DURATION
      inst.sg.statemem.teach_sanity_task = inst:DoPeriodicTask(1, function(player)
        if player.sg.currentstate.name == STUDENT_STATE then
          DrainStudentSanity(player, per_second)
        end
      end, 1)
    end

    -- 教师在 10 秒整负责结算；这里多留 1 秒只作异常兜底，避免双方 timeout 同帧竞争。
    inst.sg:SetTimeout(TUNING.WANG.TEACH_DURATION + 1)
  end,

  ontimeout = function(inst)
    inst.sg:GoToState("idle")
  end,

  onexit = function(inst)
    if not TheWorld.ismastersim then
      return
    end

    if inst.sg.statemem.teach_sanity_task ~= nil then
      inst.sg.statemem.teach_sanity_task:Cancel()
      inst.sg.statemem.teach_sanity_task = nil
    end

    if not inst.sg.statemem.teach_exit_silent then
      local teacher = inst.sg.statemem.teacher
      if teacher ~= nil and teacher:IsValid() then
        teacher:PushEvent("wang_teach_interrupted", { target = inst })
      end
    end
  end,
}

-- 邀请方：busy + nointerrupt，不能靠移动/动作/受击主动或被动打断普通流程。
local teacherState = State {
  name = TEACHER_STATE,
  tags = { "doing", "busy", "nointerrupt" },
  server_states = { TEACHER_STATE },

  onenter = function(inst)
    local action = inst:GetBufferedAction()
    local target = action ~= nil and action.target or nil
    inst.sg.statemem.target = target

    inst.components.locomotor:Stop()
    PlayTeachSit(inst)
    if target ~= nil and target:IsValid() then
      inst:ForceFacePoint(target.Transform:GetWorldPosition())
    end

    if not TheWorld.ismastersim then
      -- 清掉同名状态的旧缓存，避免连续传授时误把上一次服务端状态当成已确认。
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

    if inst.components.talker ~= nil then
      inst.components.talker:Say(STRINGS.CHARACTERS.WANG.ANNOUNCE.TEACH_RECIPE)
    end

    target:ForceFacePoint(inst.Transform:GetWorldPosition())
    target.sg:GoToState(STUDENT_STATE, { teacher = inst })
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
      -- 服务端已经结束/拒绝本次传授，立即解除客户端 busy；首次确认留 1 秒网络余量。
      inst.sg:GoToState("idle", true)
    end
  end,

  events = {
    EventHandler("wang_teach_interrupted", function(inst, data)
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
    if target == nil or not target:IsValid() or target.sg == nil
        or target.sg.currentstate.name ~= STUDENT_STATE
        or target.sg.statemem.teacher ~= inst then
      inst.sg.statemem.interrupted = true
      inst.sg:GoToState("idle")
      return
    end

    FinishStudentSanityDrain(target)
    TeachRandomRecipe(inst, target)

    target.sg.statemem.teach_exit_silent = true
    target.sg:GoToState("idle")
    inst.sg.statemem.completed = true
    inst.sg:GoToState("idle")
  end,

  onexit = function(inst)
    if not TheWorld.ismastersim or inst.sg.statemem.completed then
      return
    end

    local target = inst.sg.statemem.target
    if target ~= nil and target:IsValid() and target.sg ~= nil
        and target.sg.currentstate.name == STUDENT_STATE
        and target.sg.statemem.teacher == inst then
      target.sg.statemem.teach_exit_silent = true
      target.sg:GoToState("idle")
    end
  end,
}

AddStategraphState("wilson", teacherState)
AddStategraphState("wilson_client", teacherState)
AddStategraphState("wilson", studentState)
AddStategraphState("wilson_client", studentState)
AddStategraphActionHandler("wilson", ActionHandler(ACTIONS.TEACH_RECIPE, TEACHER_STATE))
AddStategraphActionHandler("wilson_client", ActionHandler(ACTIONS.TEACH_RECIPE, TEACHER_STATE))
