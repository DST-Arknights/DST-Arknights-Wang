-- recipe_mastery 副本（客户端）
-- 每个"可掌握的有效配方"一个 net_tinybyte（3-bit [0..7]）状态，挂在玩家实体上（全客户端可见）
-- 状态约定（RECIPE_MASTERY_STATE，定义于 modmain）：
--   0 = 未掌握   1 = 掌握中   2 = 已掌握   3~7 = 保留

local RecipeMasteryReplica = Class(function(self, inst)
  self.inst = inst
  -- 只为可掌握的有效配方建状态变量，节约网络变量（IsLearnableRecipe 为 modmain 全局）
  self.state = {}
  for k, v in pairs(AllRecipes) do
    if IsRecipeValid(k) and IsLearnableRecipe(v) then
      self.state[k] = net_tinybyte(inst.GUID, "recipe_mastery.recipes[" .. k .. "]", "recipe_mastery_recipesdirty")
    end
  end
  -- 各状态配方列表缓存（采集器高频访问，避免每次遍历所有状态变量）
  self._state_lists = nil
  inst:ListenForEvent("recipe_mastery_recipesdirty", function()
    self._state_lists = nil
  end)
  -- 可传授开关（网络变量，客户端采集器可读）
  self.teaching_enabled = net_bool(inst.GUID, "recipe_mastery.teaching_enabled", "recipe_mastery_teaching_dirty")
end)

-- 可传授开关读取（客户端采集器用）
function RecipeMasteryReplica:IsTeachingEnabled()
  return self.teaching_enabled ~= nil and self.teaching_enabled:value()
end

-- 可传授开关写入（服务端组件调用）
function RecipeMasteryReplica:SetTeachingEnabled(enabled)
  self.teaching_enabled:set(enabled == true)
end

-- 同步查询某配方状态
function RecipeMasteryReplica:GetState(recname)
  local v = self.state[recname]
  return v ~= nil and v:value() or RECIPE_MASTERY_STATE.UNMASTERED
end

-- 服务端组件写入状态
function RecipeMasteryReplica:SetState(recname, state)
  local v = self.state[recname]
  if v ~= nil then
    v:set(state or RECIPE_MASTERY_STATE.UNMASTERED)
  end
end

-- 获取某状态的配方列表（缓存，状态变化时重建）
function RecipeMasteryReplica:GetRecipeListByState(status)
  if self._state_lists == nil then
    self._state_lists = {}
    for name, v in pairs(self.state) do
      local s = v:value()
      local list = self._state_lists[s]
      if list == nil then
        list = {}
        self._state_lists[s] = list
      end
      table.insert(list, name)
    end
  end
  return self._state_lists[status] or {}
end

return RecipeMasteryReplica
