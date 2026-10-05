-- 对不支持的语言兜底到英文（DST 原版 ChooseTranslationTable 只回退到 tbl[1]，
-- 但我们用字典键值而非数字索引，非 en/zh 语言会返回 nil 导致崩溃）
local function T(tbl)
    return ChooseTranslationTable(tbl) or tbl["en"]
end

name = T({
    en = "Wang",
    zh = "望"
})
version = "1.0.3"

-- 版本更新说明（由发布脚本自动维护，请勿手动编辑）
local UPDATE_EN = [[
v1.0.3 (2026-10-05)
- Fixed a health calculation error after unlocking Yingjie at Elite 1; taking damage, healing, and HUD health refresh now work correctly, including after unlocking, locking, removing, and loading saves.
---
v1.0.2 (2026-10-05)
- Adjusted the sources of skill-use XP and kill XP.
- Piece kills are now credited through the shared reward pipeline.
]]

local UPDATE_ZH = [[
v1.0.3 (2026-10-05)
- 修复精英化一解锁 Yingjie 后生命结算报错的问题；受伤、治疗和 HUD 生命值刷新恢复正常，解锁、锁定、移除及读档后也保持正常。
---
v1.0.2 (2026-10-05)
- 调整技能使用经验值和击杀经验的来源。
- Piece 击杀现在通过共享奖励流程结算。
]]

description = T({
    en = [[A DST character mod: Wang, the quiet chess player who builds his board one black stone at a time.

Current version: ]] .. version .. "\n" .. UPDATE_EN .. [[

Issues & Suggestions Feedback Channels:
Issues: https://github.com/DST-Arknights/DST-Arknights-Wang/issues
Email: tohsakakuro@outlook.com
QQ Group: 666511586
]],
    zh = [[饥荒联机版的明日方舟角色模组：望，沉默的弈者，以黑子为棋，以性命为盘。

当前版本: ]] .. version .. "\n" .. UPDATE_ZH .. [[

需求与建议反馈渠道:
Issues: https://github.com/DST-Arknights/DST-Arknights-Wang/issues
Email: tohsakakuro@outlook.com
QQ群: 666511586

欢迎大家积极参与!]]
})
author = "让 望月心灵"
forumthread = "https://steamcommunity.com/sharedfiles/filedetails/?id=3677284770"

api_version = 10

dont_starve_compatible = false
reign_of_giants_compatible = false

dst_compatible = true
all_clients_require_mod = true

icon_atlas = "modicon.xml"
icon = "modicon.tex"

server_filter_tags = {"character", "Wang", "arknights", "望", "明日方舟"}
configuration_options = { {
    name = "language",
    label = T({
        en = "Text Language",
        zh = "界面文本语言"
    }),
    hover = T({
        en = "Choose the language of the mod UI text (Auto follows game language)",
        zh = "选择模组界面文本的语言 (Auto 跟随游戏语言)"
    }),
    options = {{
        description = T({
            en = "Auto (follow game)",
            zh = "自动 (跟随游戏)"
        }),
        data = "auto"
    }, {
        description = T({
            en = "Simplified Chinese",
            zh = "简体中文"
        }),
        data = "zh"
    }, {
        description = T({
            en = "English",
            zh = "英文"
        }),
        data = "en"
    }},
    default = "auto"
}, {
    name = "voice_language",
    label = T({
        en = "Voice Language",
        zh = "配音语言"
    }),
    hover = T({
        en = "Choose Wang's voice language; Auto follows the game language",
        zh = "选择望的配音语言；自动跟随游戏语言"
    }),
    options = {{
        description = T({
            en = "Auto (follow game)",
            zh = "自动 (跟随游戏)"
        }),
        data = "auto"
    }, {
        description = T({
            en = "Mandarin Chinese",
            zh = "普通话"
        }),
        data = "zh"
    }, {
        description = T({
            en = "Japanese",
            zh = "日语"
        }),
        data = "jp"
    }, {
        description = T({
            en = "Hunan dialect",
            zh = "湖南话"
        }),
        data = "hunan"
    }},
    default = "auto"
}}
mod_dependencies = {
    {["DST-ArknightsItemPackage"] = false},
}
