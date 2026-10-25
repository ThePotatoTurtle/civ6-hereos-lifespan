[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetModsPath,
    [switch]$DevOnly
)

$ErrorActionPreference = 'Stop'
if (-not $DevOnly) {
    throw 'This build contains the development spike kit only. Specify -DevOnly.'
}

$runningGame = Get-Process -Name 'CivilizationVI', 'CivilizationVI_DX12' -ErrorAction SilentlyContinue
if ($runningGame) {
    throw 'Civilization VI is running. Quit to the desktop before installing.'
}

$workspacePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourcePath = Join-Path $workspacePath 'HLS_Dev'
$targetRoot = [IO.Path]::GetFullPath($TargetModsPath)
if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
    throw "The explicit Mods target must already exist: $targetRoot"
}
$destinationPath = [IO.Path]::GetFullPath((Join-Path $targetRoot 'HLS_Dev'))
if (-not $destinationPath.StartsWith($targetRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The installation destination must be inside the explicit Mods target.'
}
if ($destinationPath.Equals($sourcePath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The installation destination must differ from the source folder.'
}

$modInfoPath = Join-Path $sourcePath 'HLS_Dev.modinfo'
[xml]$modInfo = Get-Content -LiteralPath $modInfoPath -Raw
$payload = @('HLS_Dev.modinfo') + @($modInfo.SelectNodes('/Mod/Files/File') | ForEach-Object { $_.InnerText })
if (Test-Path -LiteralPath $destinationPath) {
    $existingModInfo = Join-Path $destinationPath 'HLS_Dev.modinfo'
    if (-not (Test-Path -LiteralPath $existingModInfo -PathType Leaf)) {
        throw 'Existing HLS_Dev directory has no matching manifest; it will not be overwritten.'
    }
    [xml]$existing = Get-Content -LiteralPath $existingModInfo -Raw
    if ($existing.Mod.id -ne $modInfo.Mod.id) {
        throw 'Existing HLS_Dev manifest belongs to a different mod ID.'
    }
    foreach ($existingFile in Get-ChildItem -LiteralPath $destinationPath -File -Recurse) {
        $relativePath = $existingFile.FullName.Substring($destinationPath.Length + 1).Replace('\', '/')
        if ($payload.Replace('\', '/') -notcontains $relativePath) {
            throw "Unexpected installed file $relativePath. Resolve it manually before updating."
        }
    }
}

foreach ($relativePath in $payload) {
    $sourceFile = [IO.Path]::GetFullPath((Join-Path $sourcePath $relativePath))
    $targetFile = [IO.Path]::GetFullPath((Join-Path $destinationPath $relativePath))
    if (-not $sourceFile.StartsWith($sourcePath + '\', [StringComparison]::OrdinalIgnoreCase) -or
        -not $targetFile.StartsWith($destinationPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Manifest path escapes the mod folder: $relativePath"
    }
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
        throw "Manifest source is missing: $sourceFile"
    }
}

foreach ($relativePath in $payload) {
    $sourceFile = Join-Path $sourcePath $relativePath
    $targetFile = Join-Path $destinationPath $relativePath
    $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($targetFile)) -Force
    Copy-Item -LiteralPath $sourceFile -Destination $targetFile -Force
    if ((Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash) {
        throw "Installed bytes differ: $relativePath"
    }
}
Write-Output "Installed verified development kit at $destinationPath"
