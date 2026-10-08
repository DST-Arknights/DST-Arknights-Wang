# Wang（望）子项目工作指引

## 共享规范与依赖

- DST 通用 Lua、组件、状态图、动画、贴图、发布和验证流程统一遵循 DST-Arknights-AICoding 的 skills；本文件只记录 Wang 专属约定。
- 需要查看共享依赖源码时，依赖项目使用项目名 DST-Arknights-Nexus（源枢）；源枢的位置从记忆中查找，记忆不明确时先询问用户，不要写入或假设本机路径。

## 项目专属约定

- 入口是 modmain.lua；角色、精英化、技能和棋子玩法主要分布在 modmain/、scripts/prefabs/、scripts/components/ 与 scripts/stategraphs/。
- 整理玩法介绍或工坊说明时，以当前代码实现为准；temp/望设定.txt 是历史设计稿，必须核对已经发生的玩法改动后再引用。
- 工坊文案位于 docs/workshop_description_zh.md、docs/workshop_description_en.md 及对应的 *-steam.txt 文件；发布入口是 tools/publish.ps1。编辑文案或发布配置时保留其他未相关改动。
- imageSource/、animSource/、soundSource/ 是源资源，images/、anim/、sound/ 是导出资源；bigportraits/ 存放角色选择大图。资源变更需保持源文件与导出文件的对应关系。
