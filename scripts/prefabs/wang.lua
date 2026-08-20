local MakePlayerCharacter = require "prefabs/player_common"

local assets = {
  Asset("ANIM", "anim/wang.zip"),
  Asset('ATLAS', 'bigportraits/wang.xml'),
  Asset('ATLAS', 'images/saveslot_portraits/wang.xml'),
  Asset('ATLAS', 'images/selectscreen_portraits/wang.xml'),
  Asset('ATLAS', 'images/selectscreen_portraits/wang_silho.xml'),
  Asset('ATLAS', 'images/avatars/avatar_wang.xml'),
  Asset('ATLAS', 'images/avatars/avatar_ghost_wang.xml'),
  Asset('ATLAS', 'images/avatars/self_inspect_wang.xml'),
  Asset("ATLAS", "images/names_wang.xml"),
  Asset("ATLAS", "images/names_gold_wang.xml"),
}

local prefabs = {}

local start_inv = {}

-- ════════════════════════════════════════════════════════
-- 技能：出生时安装
-- ════════════════════════════════════════════════════════
local DEFAULT_SKILL_IDS = { "wang_skill1", "wang_skill2", "wang_skill3" }

local function InstallDefaultSkills(inst)
  for _, skill_id in ipairs(DEFAULT_SKILL_IDS) do
    if inst.components.ark_skill:GetSkill(skill_id) == nil then
      inst.components.ark_skill:AddSkill(skill_id)
    end
  end
end

local function OnNewSpawn(inst)
  InstallDefaultSkills(inst)
  -- 天赋：铸子（被动，出生即有）
  if inst.components.ark_talent:GetTalent("wang_talent_zhuzi") == nil then
    inst.components.ark_talent:AddTalent("wang_talent_zhuzi")
  end
end

-- ════════════════════════════════════════════════════════
-- 特性：工作效率 0.8（所有工作动作）
-- ════════════════════════════════════════════════════════
local function WangWorkMultiplierFn(inst, action, target, tool, numworks, recoil)
  return numworks * TUNING.WANG.WORK_EFFICIENCY
end

-- ════════════════════════════════════════════════════════
-- 特性：无法独自搬运（平时禁重物，骑牛可搬）
-- ════════════════════════════════════════════════════════
local function OnMounted(inst)
  inst.components.inventory.noheavylifting = false
end

local function OnDismounted(inst)
  inst.components.inventory.noheavylifting = true
  -- 下牛时若仍扛着重物则放下（不能独自搬运）
  if inst.components.inventory:IsHeavyLifting() then
    local item = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
    if item ~= nil then
      inst.components.inventory:DropItem(item, true, true)
    end
  end
end

-- ════════════════════════════════════════════════════════
-- 经验来源
-- ════════════════════════════════════════════════════════
-- 使用技能（解锁/掌握经验由 recipe_mastered 事件发放）
local function OnSkillActivated(inst, data)
  inst.components.ark_elite:AddExp(TUNING.WANG.EXP_PER_SKILL_USE)
end

-- ════════════════════════════════════════════════════════
-- 特性：阅读书籍（理智消耗随已读次数降低）
-- ════════════════════════════════════════════════════════
local function GetReadSanityMultiplier(inst, book)
  local reads = inst.wang_book_reads[book.prefab] or 0
  local mult = TUNING.WANG.READ_SANITY_MULT_FIRST - reads * TUNING.WANG.READ_SANITY_MULT_STEP
  return math.max(TUNING.WANG.READ_SANITY_MULT_MIN, mult)
end

-- 挂 reader.Read：读前按该书设倍率，读完恢复原倍率（备份旧值，兼容其他模组）
-- 不做 pcall 兜底：异常直接上抛，让问题暴露
local function HookWangRead(next, self, book, ...)
  local inst = self.inst
  local old_mult = self:GetSanityPenaltyMultiplier()
  if book ~= nil then
    self:SetSanityPenaltyMultiplier(GetReadSanityMultiplier(inst, book))
  end
  local success, reason = next(self, book, ...)
  self:SetSanityPenaltyMultiplier(old_mult)
  if success and book ~= nil then
    inst.wang_book_reads[book.prefab] = (inst.wang_book_reads[book.prefab] or 0) + 1
  end
  return success, reason
end

-- ════════════════════════════════════════════════════════
-- 配方掌握（望专属：升级自动掌握 / 掌握经验）
-- ════════════════════════════════════════════════════════
-- 按难度档权重随机选档（护符完全覆盖精英化分布）
local function WangRollRandomTier(inst)
  local mastery = inst.components.recipe_mastery
  local weights
  if mastery:IsWearingAmulet() then
    weights = TUNING.WANG.AUTO_MASTER_AMULET_WEIGHTS
  else
    weights = TUNING.WANG.AUTO_MASTER_WEIGHTS[mastery:GetElite()]
  end
  local total = 0
  for _, w in ipairs(weights) do
    total = total + w
  end
  if total <= 0 then
    return nil
  end
  local roll = math.random() * total
  local acc = 0
  for tier, w in ipairs(weights) do
    acc = acc + w
    if roll <= acc then
      return tier
    end
  end
  return nil
end

-- 抽一个未掌握配方名：优先"掌握中"纯随机，其次按难度权重从未掌握里抽
local function WangPickRandomUnmastered(inst)
  local replica = inst.replica.recipe_mastery
  local mastering = replica:GetRecipeListByState(RECIPE_MASTERY_STATE.MASTERING)
  if #mastering > 0 then
    return mastering[math.random(#mastering)]
  end
  local tier = WangRollRandomTier(inst)
  if tier ~= nil then
    local candidates = replica:GetRecipeListByState(RECIPE_MASTERY_STATE.UNMASTERED)
    local tiered = {}
    for _, name in ipairs(candidates) do
      local recipe = GetValidRecipe(name)
      if recipe ~= nil and inst.components.recipe_mastery:GetMasteryTier(recipe) == tier then
        table.insert(tiered, name)
      end
    end
    if #tiered > 0 then
      return tiered[math.random(#tiered)]
    end
  end
  return nil
end

-- 显示物品名而非代码（与原版制作菜单一致：STRINGS.NAMES 键为大写）
local function GetRecipeDisplayName(recipe, recname)
  if recipe == nil then
    return recname
  end
  local nameKey = recipe.nameoverride or recipe.name
  return STRINGS.NAMES[string.upper(nameKey)]
    or (recipe.product ~= nil and STRINGS.NAMES[string.upper(recipe.product)])
    or nameKey
end

-- 升级自动掌握（含满级伪升级）：每次升级掌握一个，说"学到了 xxx"
local function OnWangEliteLevelUp(inst, data)
  local mastery = inst.components.recipe_mastery
  local count = (data ~= nil and data.count) or 1
  for _ = 1, count do
    local name = WangPickRandomUnmastered(inst)
    if name == nil then
      break
    end
    mastery:MasterRecipe(name)
    inst.components.talker:Say(string.format(STRINGS.CHARACTERS.WANG.ANNOUNCE.WANG_LEARNED,
      GetRecipeDisplayName(GetValidRecipe(name), name)))
  end
end

-- 掌握 → 精英经验
local function OnWangRecipeMastered(inst, data)
  if data ~= nil and data.recipe ~= nil then
    inst.components.ark_elite:AddExp(TUNING.WANG.EXP_PER_RECIPE_UNLOCK)
  end
end

-- ════════════════════════════════════════════════════════
-- 存档（配方掌握状态由 recipe_mastery 组件自身存档）
-- ════════════════════════════════════════════════════════
local function OnSave(inst, data)
  data.wang_book_reads = inst.wang_book_reads
end

local function OnLoad(inst, data)
  if data and data.wang_book_reads then
    inst.wang_book_reads = data.wang_book_reads
  end
end

-- ════════════════════════════════════════════════════════
-- 客户端与服务端都会执行：tags / 表现相关
-- ════════════════════════════════════════════════════════
local function common_post_init(inst)
  inst:AddTag("wang")
  inst:AddTag("reader")        -- 可以阅读书籍
  inst:AddTag("ark_character") -- 物品包框架识别
  inst:AddTag("heavybody")     -- 免疫击飞（原版机制：SGwilson knockback 处理器判定，被击飞时原地落地）
end

-- ════════════════════════════════════════════════════════
-- 仅服务端执行：组件 / 属性 / 玩法
-- ════════════════════════════════════════════════════════
local function master_post_init(inst)
  -- 基础属性（生命上限会随成长逐渐降低，最低为 1）
  inst.components.health:SetMaxHealth(TUNING.WANG_HEALTH)
  inst.components.hunger:SetMax(TUNING.WANG_HUNGER)
  inst.components.sanity:SetMax(TUNING.WANG_SANITY)

  -- 阅读书籍（reader 组件 + common 里的 reader tag）
  inst:AddComponent("reader")
  inst.wang_book_reads = {}
  ArkHookFunction(inst.components.reader, "Read", HookWangRead)

  -- 六星干员，精英化（精英0/1/2，等级上限 50/80/90 由框架按六星配置）
  inst:AddComponent("ark_elite")
  inst.components.ark_elite:SetRarity(6)
  -- 生命上限随成长降低：基础 181，成长满后为 1（框架按累计等级平滑施加负奖励）
  inst.components.ark_elite:SetMaxHealthBonus(TUNING.WANG.MAX_HEALTH_BONUS)
  -- 关闭击杀经验，改为自定义来源（解锁配方 / 使用技能）
  inst.components.ark_elite:SetKillExpEnabled(false)

  -- 技能（绑定精英化解锁）
  inst:AddComponent("ark_skill")
  inst.components.ark_skill:DeclareBuiltin("wang_skill1", { -- 取势：精英0 解锁
    requiredElite = 1,
    eliteLevelMap = { [1] = 1, [2] = 2, [3] = 3 },
  })
  inst.components.ark_skill:DeclareBuiltin("wang_skill2", { -- 连星：精英1 解锁
    requiredElite = 2,
    eliteLevelMap = { [2] = 1, [3] = 2 },
  })
  inst.components.ark_skill:DeclareBuiltin("wang_skill3", { -- 天下劫：精英2 解锁
    requiredElite = 3,
    eliteLevelMap = { [3] = 1 },
  })
  -- 出生时安装技能（DeclareBuiltin 只注册配置，AddSkill 才真正安装）
  inst.OnNewSpawn = OnNewSpawn

  -- 天赋：铸子（出生解锁，等级随精英化 20/15/10 秒生成黑子）
  -- 组件可能已被物品包 AddPlayerPostInit 挂载，避免重复添加
  if inst.components.ark_talent == nil then
    inst:AddComponent("ark_talent")
  end
  inst.components.ark_talent:DeclareBuiltin("wang_talent_zhuzi", {
    requiredElite = 1,                       -- 精英0 解锁（出生即有）
    eliteLevelMap = { [1] = 1, [2] = 2, [3] = 3 }, -- 精英0→1级，精英1→2级，精英2→3级
  })

  -- 配方掌握（望安装并启用：自动掌握 / 精神增益 / 可传授）
  inst:AddComponent("recipe_mastery")
  inst.components.recipe_mastery:EnableAutoMastery()
  inst.components.recipe_mastery:EnableSanityBuff()
  inst.components.recipe_mastery:EnableTeaching(true)

  -- 事件监听（经验 / 升级自动掌握 / 掌握经验）
  inst:ListenForEvent("ark_skill_activate", OnSkillActivated)
  inst:ListenForEvent("ark_elite_levelup", OnWangEliteLevelUp)
  inst:ListenForEvent("recipe_mastered", OnWangRecipeMastered)

  -- 存档（配方掌握状态由组件自身存档）
  inst.OnSave = OnSave
  inst.OnLoad = OnLoad

  -- 基础属性修正
  inst.components.locomotor:SetExternalSpeedMultiplier(inst, "wang_speed", TUNING.WANG.SPEED_MULTIPLIER) -- 移动速度 0.8
  inst.components.combat.externaldamagemultipliers:SetModifier(inst, TUNING.WANG.DAMAGE_MULTIPLIER, "wang_damage") -- 武器攻击倍率 0.8
  inst.components.workmultiplier:SetSpecialMultiplierFn(WangWorkMultiplierFn) -- 工作效率 0.8
  inst.components.hunger.burnratemodifiers:SetModifier(inst, TUNING.WANG.HUNGER_DRAIN_RATE, "wang_hunger_rate") -- 饥饿下降较慢
  inst.components.eater.hungerabsorption = TUNING.WANG.EAT_EFFECT_MULTIPLIER -- 进食效果 0.5

  -- 特性：免疫猴子诅咒
  inst.components.cursable.IsCursable = function(self, item)
    return false
  end

  -- 特性：无法独自搬运（平时禁止重物，骑牛时放开）
  inst.components.inventory.noheavylifting = true
  inst:ListenForEvent("mounted", OnMounted)
  inst:ListenForEvent("dismounted", OnDismounted)
end

return MakePlayerCharacter("wang", prefabs, assets, common_post_init, master_post_init, start_inv)
