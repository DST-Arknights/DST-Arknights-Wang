-- 对不支持的语言兜底到英文（DST 原版 ChooseTranslationTable 只回退到 tbl[1]，
-- 但我们用字典键值而非数字索引，非 en/zh 语言会返回 nil 导致崩溃）
local function T(tbl)
    return ChooseTranslationTable(tbl) or tbl["en"]
end

name = T({
    en = "Wang",
    zh = "望"
})
version = "1.1.3"

-- 版本更新说明（由发布脚本自动维护，请勿手动编辑）
local UPDATE_EN = [[
v1.1.3 (2026-10-26)
- Fixed Yingjie fatal protection so ignore-reduction HP loss from mods like Prism now triggers it, preventing low-health Wang from being instantly killed; lethal HP loss consumes Black Piece except for Kill/ForceKill, while M3 Cocoon Armor's early low-HP lock protection still applies.
---
v1.1.2 (2026-10-12)
- Added carrying stamina for Wang: at full stamina, walking can carry for 60 seconds, and stamina recovers gradually after dropping the load; when depleted, the load is dropped automatically and Wang is forced to rest for 10 seconds.
- While riding a Beefalo, carrying does not consume stamina and stamina can recover; remaining stamina and rest time are saved with the character.
- Updated Wang's Chinese and English character selection bio, carrying lines, and Steam copy.
]]

local UPDATE_ZH = [[
v1.1.3 (2026-10-26)
- 修复 Yingjie 致命保护：Prism 等模组的无视减伤扣血现在也会触发保护，低血量 Wang 不再被直接击杀；致死扣血会消耗 Black Piece，仅放过 Kill/ForceKill，并保留 M3 Cocoon Armor 锁血下限的提前保护。
---
v1.1.2 (2026-10-12)
- 为 Wang 新增搬运体力：步行满体力可搬运 60 秒，放下后逐渐恢复；体力耗尽时会自动放下并强制休息 10 秒。
- 骑 Beefalo 时搬运不消耗体力且可恢复；剩余体力和休息时间会随角色存档保存。
- 更新了 Wang 的中英文选角简介、搬运台词和 Steam 文案。
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
    {["DST-Arknights-Nexus"] = false},
}
