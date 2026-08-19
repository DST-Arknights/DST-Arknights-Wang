# DST-Arknights-Wang (望)

饥荒联机版的明日方舟系列角色模组：**望**，沉默的弈者。

> 以黑子为棋，以性命为盘。望不依靠强壮的身体解决问题，而是先落下一子，慢慢建立自己的棋局。

## 依赖

- [DST-ArknightsItemPackage（明日方舟 物品包）](https://steamcommunity.com/sharedfiles/filedetails/?id=3677284770) — 必需前置，提供精英化 / 技能 / 材料 / Buff 等共享框架。

## 目录结构

```
dst-arknights-wang/
├── modinfo.lua              # 模组信息与配置项
├── modmain.lua              # 模组入口：依赖检查、语言、角色注册、框架钩子
├── modmain/
│   ├── wang_elite.lua       # 精英化配置（精英材料、成长数值）
│   └── wang_skill.lua       # 技能配置
├── languages/               # PO 语言文件（台词直接写入 PO，随语言翻译）
├── scripts/
│   ├── components/          # 自定义组件
│   ├── prefabs/
│   │   └── wang.lua         # 角色 prefab
│   ├── stategraphs/         # 角色状态图
│   └── widgets/             # 自定义 UI
├── bigportraits/            # 角色选择大图
├── images/                  # 导出的贴图 (xml/tex)
├── imageSource/             # 贴图源文件 (png)
├── anim/                    # 导出的动画 (zip)
├── animSource/              # 动画源文件
├── sound/                   # 导出的音频
├── soundSource/             # 音频源文件
├── fx/                      # 特效贴图
├── tools/
│   ├── publish.ps1          # 发布脚本（薄封装）
│   └── publish-config.ps1   # 发布配置（依赖 workshop id）
└── docs/
```

## 开发

- **发布**：在项目根目录执行 `pwsh ./tools/publish.ps1 -Bump patch`
- **游戏源码参考**：`C:\Saved Games\Steam\steamapps\common\Don't Starve Together\data\databundles\scripts`
- **通用编码规范**：见 `DST-Arknights-AICoding` plugin 仓库的 skills
