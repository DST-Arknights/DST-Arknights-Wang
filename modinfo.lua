-- 对不支持的语言兜底到英文（DST 原版 ChooseTranslationTable 只回退到 tbl[1]，
-- 但我们用字典键值而非数字索引，非 en/zh 语言会返回 nil 导致崩溃）
local function T(tbl)
    return ChooseTranslationTable(tbl) or tbl["en"]
end

name = T({
    en = "Wang",
    zh = "望"
})
-- 版本更新说明（由发布脚本自动维护，请勿手动编辑）
local UPDATE_EN = [[
v0.1.0 (2026-08-17)
- 项目初始化
]]

local UPDATE_ZH = [[
v0.1.0 (2026-08-17)
- 项目初始化
]]

description = T({
    en = [[A DST character mod: Wang, the quiet chess player who builds his board one black stone at a time.

]] .. UPDATE_EN .. [[

Issues & Suggestions Feedback Channels:
Issues: https://github.com/DST-Arknights/DST-Arknights-Wang/issues
Email: tohsakakuro@outlook.com
QQ Group: 666511586
]],
    zh = [[饥荒联机版的明日方舟角色模组：望，沉默的弈者，以黑子为棋，以性命为盘。

]] .. UPDATE_ZH .. [[

需求与建议反馈渠道:
Issues: https://github.com/DST-Arknights/DST-Arknights-Wang/issues
Email: tohsakakuro@outlook.com
QQ群: 666511586

欢迎大家积极参与!]]
})
author = "让 望月心灵"
version = "0.1.0"
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
}}
mod_dependencies = {
    {["DST-ArknightsItemPackage"] = false},
}
