$ErrorActionPreference = 'Stop'
$workspacePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testPath = Join-Path $workspacePath ('tests/offline/hls_install_test_' + [Guid]::NewGuid().ToString('N'))
$installerPath = Join-Path $workspacePath 'tools/install.ps1'
$null = New-Item -ItemType Directory -Path $testPath
function Get-Process { [CmdletBinding()] param([string[]]$Name) return $null }
function Expect-Refusal([scriptblock]$Action, [string]$Expected) {
    $refused = $false
    try { & $Action }
    catch { if ($_.Exception.Message -notlike "*$Expected*") { throw }; $refused = $true }
    if (-not $refused) { throw "Expected refusal was absent: $Expected" }
}
try {
    Expect-Refusal { & $installerPath -TargetModsPath $testPath } 'Specify -DevOnly'
    Expect-Refusal { & $installerPath -DevOnly -TargetModsPath (Join-Path $testPath 'missing') } 'must already exist'
    function Get-Process { [CmdletBinding()] param([string[]]$Name) return [pscustomobject]@{ProcessName='CivilizationVI'} }
    Expect-Refusal { & $installerPath -DevOnly -TargetModsPath $testPath } 'Civilization VI is running'
    if (Test-Path -LiteralPath (Join-Path $testPath 'HLS_Dev')) { throw 'Refused installer created a payload.' }
    function Get-Process { [CmdletBinding()] param([string[]]$Name) return $null }
    & $installerPath -DevOnly -TargetModsPath $testPath
    & $installerPath -DevOnly -TargetModsPath $testPath
    [xml]$manifest = Get-Content -LiteralPath (Join-Path $workspacePath 'HLS_Dev/HLS_Dev.modinfo') -Raw
    foreach ($entry in $manifest.SelectNodes('/Mod/Files/File')) {
        $relative = $entry.InnerText
        $source = Join-Path (Join-Path $workspacePath 'HLS_Dev') $relative
        $installed = Join-Path (Join-Path $testPath 'HLS_Dev') $relative
        if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $installed).Hash) {
            throw "Nested payload copy/update differs: $relative"
        }
    }
    $unexpected = Join-Path $testPath 'HLS_Dev/unexpected.txt'
    Set-Content -LiteralPath $unexpected -Value 'preserve me'
    Expect-Refusal { & $installerPath -DevOnly -TargetModsPath $testPath } 'Unexpected installed file'
    if (-not (Test-Path -LiteralPath $unexpected)) { throw 'Refusal removed an unexpected file.' }
    Write-Output 'PASS: installer refusals, nested first install, identical update, and unexpected-file preservation'
}
finally {
    $resolvedTestPath = [IO.Path]::GetFullPath($testPath)
    $allowedParent = [IO.Path]::GetFullPath((Join-Path $workspacePath 'tests/offline'))
    if (-not $resolvedTestPath.StartsWith($allowedParent.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing cleanup outside the offline test directory.'
    }
    if (Test-Path -LiteralPath $resolvedTestPath) { Remove-Item -LiteralPath $resolvedTestPath -Recurse -Force }
}
