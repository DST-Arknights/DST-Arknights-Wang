-- 望的精英化配置
-- 分阶段成长：精英0 (1~50级) → 精英1 (1~80级) → 精英2 (1~90级)
-- 等级上限 {50, 80, 90} 由框架按六星配置给定，无需自定义
-- 生命上限随成长逐渐降低：基础 181（TUNING.WANG_HEALTH），成长满后为 1
-- 由框架 SetMaxHealthBonus 按累计等级比例平滑施加负奖励
TUNING.WANG.MAX_HEALTH_BONUS = 1 - TUNING.WANG_HEALTH

-- 各精英阶段额外配置（占位：铸子间隔 20/15/10、黑子成长、影响范围 0.5/1/1.5 等后续补充）
TUNING.WANG.ELITE = {
  {}, -- 精英0
  {}, -- 精英1
  {}, -- 精英2
}

-- 精英材料
-- 精英1：3W*龙门币 5*莎草纸 12*月岩 3*电子元件
-- 精英2：18W*龙门币 8*莎草纸 4*叶肉糕 6*蛞蝓龟黏液
local Elite1Ingredients = {
  Ingredient("ark_gold", 30000), -- 3W 龙门币
  Ingredient("papyrus", 5),      -- 5 莎草纸
  Ingredient("moonrocknugget", 12),    -- 12 月岩
  Ingredient("transistor", 3),   -- 3 电子元件
}

local Elite2Ingredients = {
  Ingredient("ark_gold", 180000), -- 18W 龙门币
  Ingredient("papyrus", 8),       -- 8 莎草纸
  Ingredient("leafloaf", 4),     -- 4 叶肉糕
  Ingredient("slurper_pelt", 6),  -- 6 蛞蝓龟黏液
}

-- 不开启全模组材料掉落时，龙门币替换为原版金块
-- if not TUNING.ARK_CONFIG.enable_all_materials_drop then
--   Elite1Ingredients = {
--     Ingredient("goldnugget", 30),
--     Ingredient("papyrus", 5),
--     Ingredient("moonrock", 12),
--     Ingredient("transistor", 3),
--   }
--   Elite2Ingredients = {
--     Ingredient("goldnugget", 180),
--     Ingredient("papyrus", 8),
--     Ingredient("leafymeat", 4),
--     Ingredient("slurper_pelt", 6),
--   }
-- end

AddEliteLevelUpRecipes("wang", {{
  ingredients = Elite1Ingredients,
  atlas = "images/ark_elite.xml",
  image = "elite1.tex",
}, {
  ingredients = Elite2Ingredients,
  atlas = "images/ark_elite.xml",
  image = "elite2.tex",
}})
