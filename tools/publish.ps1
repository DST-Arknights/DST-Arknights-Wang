# 项目发布入口；公共流程和配置契约由 DST-ArknightsItemPackage 统一实现。
#
# 用法:
#   pwsh ./tools/publish.ps1 -Bump patch
#   pwsh ./tools/publish.ps1 major -New
#   pwsh ./tools/publish.ps1 -DistOnly

$ErrorActionPreference = 'Stop'

$projectConfig = @{
    LanguagesDir = 'languages'
    WorkshopDeps = @{
        'DST-ArknightsItemPackage' = 'workshop-3677284770'
    }
}

$sharedEntry = Join-Path $PSScriptRoot '..\..\DST-ArknightsItemPackage\tools\publish.ps1'
if (-not (Test-Path -LiteralPath $sharedEntry)) {
    Write-Error "未找到物品包统一发布入口（相对路径）: $sharedEntry"
    exit 1
}
$sharedEntry = (Resolve-Path -LiteralPath $sharedEntry).Path

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
& $sharedEntry -ProjectRoot $projectRoot -ProjectConfig $projectConfig @args
