param([string]$PropBuilderSource = 'D:/tools/ytd-extractor/src/PropBuilder')
$ErrorActionPreference = 'Stop'
$resourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$projectPath = Join-Path $PSScriptRoot 'CapsulePropBuilder/CapsulePropBuilder.csproj'
$candidateRoot = Join-Path $resourceRoot 'artifacts/props-candidate'
& dotnet build $projectPath -c Release --nologo "-p:PropBuilderSource=$PropBuilderSource"
if ($LASTEXITCODE -ne 0) { throw 'Prop builder compilation failed; streamed assets were not changed.' }
& dotnet (Join-Path $PSScriptRoot 'CapsulePropBuilder/bin/Release/net8.0/CapsulePropBuilder.dll') $candidateRoot
if ($LASTEXITCODE -ne 0) { throw 'Binary validation failed; streamed assets were not changed.' }
$report = Get-Content -LiteralPath (Join-Path $candidateRoot 'validation.json') -Raw | ConvertFrom-Json
if ($report.status -ne 'structural_validation_passed') { throw 'Candidate has no passing structural validation.' }
$streamRoot = Join-Path $resourceRoot 'stream'
New-Item -ItemType Directory -Path $streamRoot -Force | Out-Null
$assetNames = @(
    'snipe_capsule_platform_v1.ydr', 'snipe_capsule_platform_v1.ytyp',
    'snipe_capsule_deck_v2.ydr', 'snipe_capsule_deck_v2.ytyp',
    'snipe_capsule_canopy_v2.ydr', 'snipe_capsule_canopy_v2.ytyp',
    'snipe_capsule_shell_v2.ydr', 'snipe_capsule_shell_v2.ytyp',
    'snipe_capsule_tablet_v1.ydr', 'snipe_capsule_tablet_v1.ytyp',
    'snipe_capsule_booth_v1.ydr', 'snipe_capsule_booth_v1.ytyp',
    'snipe_capsule_txd_v1.ytd'
)
foreach ($assetName in $assetNames) {
    $sourcePath = Join-Path $candidateRoot ('stream/' + $assetName)
    $targetPath = Join-Path $streamRoot $assetName
    Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    if ((Get-FileHash -LiteralPath $sourcePath).Hash -ne (Get-FileHash -LiteralPath $targetPath).Hash) {
        throw "Copied asset hash does not match: $assetName"
    }
}
Write-Output 'Installed 13 structurally validated binary assets. FiveM runtime smoke test: NOT RUN.'
