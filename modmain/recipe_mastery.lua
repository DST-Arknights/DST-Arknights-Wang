-- 配方教学动作（recipe_mastery 组件，通用——教学者不限于望）
-- 采集器：双方都有掌握组件 + 执行者可传授开关开即可显示
-- 动作：只检查 fail（无可授配方 → actionfail）；成功路径由后续 sg 流程接管

ACTIONS.TEACH_RECIPE = Action({ priority = 5, distance = 3, str = "TEACH_RECIPE" })

-- 采集器（双方都要有掌握组件；可传授开关读取自副本网络变量）
AddComponentAction("SCENE", "recipe_mastery", function(inst, doer, actions, right)
  if doer == nil or inst == doer then
    return
  end
  local doer_mastery = doer.replica.recipe_mastery
  local target_mastery = inst.replica.recipe_mastery
  -- 双方都需有掌握组件
  if doer_mastery == nil or target_mastery == nil then
    return
  end
  if not doer_mastery:IsTeachingEnabled() then
    return
  end
  table.insert(actions, ACTIONS.TEACH_RECIPE)
end)

-- diff 双方已掌握列表：返回可教的配方（服务端）
local function GetTeachDiff(teacher, target)
  local teacher_mastery = teacher.replica.recipe_mastery
  local target_mastery = target.replica.recipe_mastery
  local candidates = {}
  local list = teacher_mastery:GetRecipeListByState(RECIPE_MASTERY_STATE.MASTERED)
  for _, name in ipairs(list) do
    if target_mastery:GetState(name) ~= RECIPE_MASTERY_STATE.MASTERED then
      table.insert(candidates, name)
    end
  end
  return candidates
end

-- 动作执行（服务端）：只检查 fail；成功进 sg（后续实现）
ACTIONS.TEACH_RECIPE.fn = function(act)
  local teacher, target = act.doer, act.target
  local candidates = GetTeachDiff(teacher, target)
  if #candidates == 0 then
    return false, "TEACH_NONE" -- 没东西可教（actionfail 台词）
  end
  -- TODO: 进 sg（席地而坐 / 理智积累 / 对方可打断）后续实现，执行由 sg 流程接管
  return true
end
