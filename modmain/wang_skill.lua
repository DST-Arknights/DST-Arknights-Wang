table.insert(Assets, Asset("ATLAS", "images/wang_skill.xml"))
-- 望的技能配置
-- 被动：铸子 / 料敌机先（另行实现）
-- 主动：取势（精英0）/ 连星（精英1）/ 天下劫（精英2）
-- 武器：拈子剑（另行实现）
local ARK_CONSTANTS = require("ark_constants")

local skillConfig = {
  {
    id = 'wang_skill1', -- 取势
    name = STRINGS.UI.ARK_SKILL.NAMES.WANG[1],
    lockedDesc = STRINGS.UI.ARK_SKILL.LOCKED_DESC.WANG[1],
    atlas = "images/wang_skill.xml",
    image = "skill_icon_wang_1.tex",
    recipe_atlas = "images/wang_skill.xml",
    -- recipe_image = "wang_skill1_recipe.tex",
    recipe_image = "skill_icon_wang_1.tex",
    hotkey = KEY_Z,
    energyRecoveryMode = ARK_CONSTANTS.ENERGY_RECOVERY_MODE.AUTO, -- 自动回复
    activationMode = ARK_CONSTANTS.ACTIVATION_MODE.MANUAL,        -- 手动触发
    levels = { {
      desc = STRINGS.UI.ARK_SKILL.LEVEL_DESC.WANG[1][1],
      activationEnergy = 5,       -- 消耗 SP（设定：5→3→1）
      maxActivationStacks = 5,    -- 可储存次数（设定：5→7→10）
      params = {},
    }, {
      desc = STRINGS.UI.ARK_SKILL.LEVEL_DESC.WANG[1][2],
      activationEnergy = 3,
      maxActivationStacks = 7,
      params = {},
    }, {
      desc = STRINGS.UI.ARK_SKILL.LEVEL_DESC.WANG[1][3],
      activationEnergy = 1,
      maxActivationStacks = 10,
      params = {},
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
