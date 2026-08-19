-- recipe_mastery 配方掌握组件（服务端）
-- 状态枚举 RECIPE_MASTERY_STATE、可掌握判定 IsLearnableRecipe 均定义于 modmain
-- 职责：制作完成监听 → 有几率掌握 → MasterRecipe（解锁 + 标记 + 事件）
-- 望专属逻辑（升级自动掌握 / 掌握经验）在 wang.lua

local function on_enable_teaching(self, enabled)
  self.inst.replica.recipe_mastery:SetTeachingEnabled(enabled)
end

local function SendMasterRecipeNotify(self, name)
  local inst = self.inst
  if inst.userid then
    SendRPCToClient(CLIENT_RPC.LearnBuilderRecipe, inst.userid, name)
  end
  if inst.player_classified then
    inst.player_classified.learnrecipeevent:push()
  end
end

-- 学习接口：掌握 = 触发系统解锁（unlockrecipe 事件推动掌握状态 + 掌握事件）
local function MasterRecipe(self, name)
  if not self:IsMastered(name) then
    local inst = self.inst
    if inst.components.builder then
      inst.components.builder:UnlockRecipe(name)
    end
    self:SetState(name, RECIPE_MASTERY_STATE.MASTERED)
    inst:PushEvent("recipe_mastered", { recipe = name })
  end
end

local function OnLearnRecipe(inst, data)
  local name = data and data.recipe
  if name == nil then
    return
  end
  local recipe = GetValidRecipe(name)
  if recipe == nil or not IsLearnableRecipe(recipe) then
    return
  end
  local self = inst.components.recipe_mastery
  if not self:IsMastered(name) then
    MasterRecipe(self, name)
  end
end


local RecipeMastery = Class(function(self, inst)
  self.inst = inst
  self.states = {}                 -- [配方名] = RECIPE_MASTERY_STATE 数字，与副本一致
  self.sanity_buff_enabled = false -- 精神增益开启状态不存档，由用户组件手动启用
  self.enable_teaching = false          -- 可传授开关
  -- （不传 source，默认以 inst 为 source，实体移除时自动清理）
  inst:ListenForEvent("learnrecipe", OnLearnRecipe)
end, nil, {
  enable_teaching = on_enable_teaching,
})

-- 可传授开关（教学者身份；同步到副本网络变量，客户端采集器可读）
function RecipeMastery:EnableTeaching(enabled)
  self.enable_teaching = enabled
end

-- 精英阶级
function RecipeMastery:GetElite()
  return self.inst.components.ark_elite and self.inst.components.ark_elite.elite or 1
end

-- 配方难度档（1~7：普通一/魔法一/普通二/魔法二/远古/暗影月亮/其他）
function RecipeMastery:GetMasteryTier(recipe)
  local level = recipe.level
  if level.SCIENCE == 1 then return 1 end
  if level.MAGIC == 2 then return 2 end
  if level.SCIENCE == 2 then return 3 end
  if level.MAGIC == 3 then return 4 end
  if level.ANCIENT > 0 then return 5 end
  if level.SHADOW > 0 or level.CELESTIAL > 0 then return 6 end
  return 7
end

-- 佩戴建筑护符？
function RecipeMastery:IsWearingAmulet()
  for _, item in pairs(self.inst.components.inventory.equipslots) do
    if item ~= nil and item.prefab == "greenamulet" then return true end
  end
  return false
end

-- 本地：掌握掷骰（几率按以前：难度档 × 精英化 + 护符加成）
local function RollMastery(inst, recipe)
  local mastery = inst.components.recipe_mastery
  local chance = TUNING.WANG.MASTER_CHANCE[mastery:GetElite()][mastery:GetMasteryTier(recipe)]
  if mastery:IsWearingAmulet() then
    chance = chance + TUNING.WANG.AMULET_MASTERY_BONUS
  end
  return math.random() < math.min(1, chance)
end

-- 状态写入统一走这里：修改组件本地状态表 + 同步副本
function RecipeMastery:SetState(recname, state)
  state = state or RECIPE_MASTERY_STATE.UNMASTERED
  self.states[recname] = state
  self.inst.replica.recipe_mastery:SetState(recname, state)
  -- 精神增益开启时，状态变更即重算数量并应用
  if self.sanity_buff_enabled then
    self:UpdateSanityBuff()
  end
end

function RecipeMastery:GetState(recname)
  return self.states[recname] or RECIPE_MASTERY_STATE.UNMASTERED
end

-- 是否已掌握（数字状态判定）
function RecipeMastery:IsMastered(name)
  return self.states[name] == RECIPE_MASTERY_STATE.MASTERED
end

local function OnBuildItem(inst, data)
  local recipe = data and data.recipe
  if recipe == nil or not IsLearnableRecipe(recipe) then
    return
  end
  local self = inst.components.recipe_mastery
  if self:IsMastered(recipe.name) then
    return
  end
  if RollMastery(inst, recipe) then
    self:MasterRecipe(recipe.name)
  else
    -- 弱几率失败：设置为掌握中
    self:SetState(recipe.name, RECIPE_MASTERY_STATE.MASTERING)
  end
end

function RecipeMastery:MasterRecipe(name)
  if not self:IsMastered(name) then
    local recipe = GetValidRecipe(name)
    if recipe ~= nil and IsLearnableRecipe(recipe) then
      MasterRecipe(self, name)
      SendMasterRecipeNotify(self, name)
    end
  end
end

-- 统计某状态的配方数量
function RecipeMastery:CountState(status)
  local count = 0
  for _, state in pairs(self.states) do
    if state == status then
      count = count + 1
    end
  end
  return count
end

-- 精神增益：每掌握中配方扣减 SANITY_DRAIN_PER_UNMASTERED，每已掌握配方恢复 SANITY_RECOVERY_PER_MASTERED
local function SanityRateFn(inst, dt)
  local comp = inst.components.recipe_mastery
  if not comp.sanity_buff_enabled then
    return 0
  end
  return comp._sanity_mastering * TUNING.WANG.SANITY_DRAIN_PER_UNMASTERED
      + comp._sanity_mastered * TUNING.WANG.SANITY_RECOVERY_PER_MASTERED
end

-- 接口：启用精神增益（由用户组件手动启用；开启状态不存档）
function RecipeMastery:EnableSanityBuff()
  self.sanity_buff_enabled = true
  self.inst.components.sanity.custom_rate_fn = SanityRateFn
  self:UpdateSanityBuff()
end

-- 重算掌握中/已掌握数量（状态变更或读档后调用）
function RecipeMastery:UpdateSanityBuff()
  self._sanity_mastering = self:CountState(RECIPE_MASTERY_STATE.MASTERING)
  self._sanity_mastered = self:CountState(RECIPE_MASTERY_STATE.MASTERED)
end

-- 接口：开启自动掌握（监听制作完成，有几率解锁；不拦截制作逻辑）
function RecipeMastery:EnableAutoMastery()
  self.inst:ListenForEvent("builditem", OnBuildItem)
end

function RecipeMastery:DisableAutoMastery()
  self.inst:RemoveEventCallback("builditem", OnBuildItem)
end

function RecipeMastery:OnSave()
  return { states = self.states }
end

function RecipeMastery:OnLoad(data)
  if data ~= nil then
    self.states = data.states or {}
  end
  -- 直接恢复本地表 + 副本，结束后统一按精神增益状态重算（不走 SetState，避免逐条触发更新）
  for name, state in pairs(self.states) do
    self.inst.replica.recipe_mastery:SetState(name, state)
  end
  if self.sanity_buff_enabled then
    self:UpdateSanityBuff()
  end
end

function RecipeMastery:OnRemoveFromEntity()
  self:DisableAutoMastery()
  self.inst:RemoveEventCallback("learnrecipe", OnLearnRecipe)
end

return RecipeMastery
