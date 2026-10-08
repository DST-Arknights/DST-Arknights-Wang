# 项目发布入口；公共流程和配置契约由 DST-Arknights-Nexus 统一实现。
#
# 用法:
#   pwsh ./tools/publish.ps1 -Bump patch
#   pwsh ./tools/publish.ps1 major -New
#   pwsh ./tools/publish.ps1 -DistOnly

$ErrorActionPreference = 'Stop'

$projectConfig = @{
    GitFiles = @(
        'modinfo.lua'
        'CHANGELOG.md'
        'docs/workshop_description_zh.md'
        'docs/workshop_description_en.md'
        'docs/workshop_description_zh-steam.txt'
        'docs/workshop_description_en-steam.txt'
    )
    LanguagesDir = 'languages'
    SteamDescriptionMarkdown = @(
        'docs/workshop_description_zh.md'
        'docs/workshop_description_en.md'
    )
    SteamDescriptionOutput = @(
        'docs/workshop_description_zh-steam.txt'
        'docs/workshop_description_en-steam.txt'
    )
    WorkshopDeps = @{
        'DST-Arknights-Nexus' = 'workshop-3677284770'
    }
}

$sharedEntry = Join-Path $PSScriptRoot '..\..\DST-Arknights-Nexus\tools\publish.ps1'
if (-not (Test-Path -LiteralPath $sharedEntry)) {
    Write-Error "未找到源枢统一发布入口（相对路径）: $sharedEntry"
    exit 1
}
$sharedEntry = (Resolve-Path -LiteralPath $sharedEntry).Path

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
& $sharedEntry -ProjectRoot $projectRoot -ProjectConfig $projectConfig @args
