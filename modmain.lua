-- ════════════════════════════════════════════════════════
-- 入口：全局访问 + 前置依赖检查
-- ════════════════════════════════════════════════════════
GLOBAL.setmetatable(env, {
  __index = function(t, k)
    return GLOBAL.rawget(GLOBAL, k)
  end
})
assert(ARK_ITEM_PACKAGE_LOADED, "请安装前置模组: ark_item_package\n please install the required mod: ark_item_package\n[https://steamcommunity.com/sharedfiles/filedetails/?id=3677284770]")

-- ════════════════════════════════════════════════════════
-- 语言（台词直接写入 PO，随语言翻译）
-- ════════════════════════════════════════════════════════
RegisterPOFile(GetModConfigData("language"), {
  zh = "languages/wang_chinese_s.po",
  en = "languages/wang_english.po",
})

-- ════════════════════════════════════════════════════════
-- 角色注册
-- ════════════════════════════════════════════════════════
PrefabFiles = {'wang', 'wang_none', 'piece'}

Assets = {
}

AddMinimapAtlas('images/map_icons/wang.xml')
AddModCharacter("wang", "MALE")

ArkLogger:DeclareLogger('INFO', 'wang')

-- ════════════════════════════════════════════════════════
-- 常量配置
-- ════════════════════════════════════════════════════════
TUNING.WANG = {}

-- 基础属性（望的生命上限会随成长逐渐降低，最低为 1）
TUNING.WANG_HEALTH = 181
TUNING.WANG_HUNGER = 150
TUNING.WANG_SANITY = 361

-- 基础属性修正
TUNING.WANG.SPEED_MULTIPLIER = 0.8     -- 移动速度
TUNING.WANG.DAMAGE_MULTIPLIER = 0.8    -- 武器攻击倍率
TUNING.WANG.WORK_EFFICIENCY = 0.8      -- 工作效率
TUNING.WANG.HUNGER_DRAIN_RATE = 0.8    -- 饥饿下降速率（较慢）
TUNING.WANG.EAT_EFFECT_MULTIPLIER = 0.5 -- 进食饥饿恢复（0.5倍）

-- 黑子投掷（装备后右键，水球模式抛物线）
TUNING.WANG.PIECE_THROW_DAMAGE = 5    -- 落地对附近生物伤害
TUNING.WANG.PIECE_THROW_AOE = 1       -- 落地伤害范围
TUNING.WANG.PIECE_THROW_SPEED = 15    -- 水平速度
TUNING.WANG.PIECE_THROW_GRAVITY = -35 -- 重力（抛物线）

-- 经验来源（已关闭框架默认击杀经验）
TUNING.WANG.EXP_PER_RECIPE_UNLOCK = 10 -- 解锁配方
TUNING.WANG.EXP_PER_SKILL_USE = 10     -- 使用技能

-- 读书理智消耗控制（倍率：首次阅读新书翻倍 → 随已读次数降至 0.5 倍）
TUNING.WANG.READ_SANITY_MULT_FIRST = 2   -- 首次阅读理智消耗倍率
TUNING.WANG.READ_SANITY_MULT_MIN = 0.5   -- 最低降至正常值 0.5 倍
TUNING.WANG.READ_SANITY_MULT_STEP = 0.1  -- 每次阅读后降低 0.1

-- 配方掌握（recipe_mastery 组件）
-- 普通制造掌握成功率 [精英阶级][难度档]：普通一/魔法一/普通二/魔法二/远古/暗影月亮/其他mod
TUNING.WANG.MASTER_CHANCE = {
  { 0.75, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25 }, -- 无精英化
  { 1.00, 0.75, 0.50, 0.25, 0.25, 0.25, 0.25 }, -- 精一
  { 1.00, 1.00, 0.75, 0.50, 0.25, 0.25, 0.25 }, -- 精二
}
TUNING.WANG.AMULET_MASTERY_BONUS = 0.5             -- 建筑护符：掌握成功率加算 50%（各阶级一致）
TUNING.WANG.SANITY_DRAIN_PER_UNMASTERED = -0.2      -- 每个未掌握配方每秒掉理智（占位）
TUNING.WANG.SANITY_RECOVERY_PER_MASTERED = 0.05     -- 每个已掌握配方每秒回理智（占位）
-- 升级自动掌握：按难度档权重分配（科一/魔一/科二/魔二/远古/暗影月亮/其他）
TUNING.WANG.AUTO_MASTER_WEIGHTS = {
  { 75, 25, 0, 0, 0, 0, 0 },   -- 无精英化
  { 45, 33, 20, 2, 0, 0, 0 },  -- 精一
  { 9, 15, 30, 30, 16, 0, 0 }, -- 精二
}
TUNING.WANG.AUTO_MASTER_AMULET_WEIGHTS = { 0, 0, 0, 25, 25, 25, 25 } -- 佩戴建筑护符时完全覆盖精英化分布

-- ════════════════════════════════════════════════════════
-- 配方掌握共享接口（组件与外部共用）
-- ════════════════════════════════════════════════════════
-- 状态枚举
GLOBAL.RECIPE_MASTERY_STATE = {
  UNMASTERED = 0,
  MASTERING = 1,
  MASTERED = 2,
}

-- 可掌握的有效配方判定
function GLOBAL.IsLearnableRecipe(recipe)
  if recipe == nil then return false end
  if recipe.builder_tag ~= nil and recipe.builder_tag ~= "wang" then return false end
  if recipe.manufactured or recipe.nounlock then return false end
  local level = recipe.level
  if level.ANCIENT > 0 or level.CELESTIAL > 0 or level.CARTOGRAPHY > 0 or level.SCULPTING > 0 then return false end
  return true
end

-- ════════════════════════════════════════════════════════
-- 子模块
-- ════════════════════════════════════════════════════════
modimport("modmain/wang_elite")
modimport("modmain/wang_skill")

-- ════════════════════════════════════════════════════════
-- recipe_mastery 组件注册（可复制，全玩家挂载；传授目标也需组件）
-- ════════════════════════════════════════════════════════
AddReplicableComponent("recipe_mastery")
AddPlayerPostInit(function(inst)
  if TheWorld.ismastersim and not inst.components.recipe_mastery then
    inst:AddComponent("recipe_mastery")
  end
end)
modimport("modmain/recipe_mastery")

-- ════════════════════════════════════════════════════════
-- 初始物品（待实现：兽形棋盒）
-- ════════════════════════════════════════════════════════
-- local StartItems = {"wang_chess_box"}
-- TUNING.GAMEMODE_STARTING_ITEMS.DEFAULT.WANG = StartItems
