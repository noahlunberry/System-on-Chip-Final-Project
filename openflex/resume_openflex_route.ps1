param(
    [string]$Csv = "bnn_fcc_resume.csv",
    [string]$Yaml = "bnn_fcc_timing.yml",
    [string]$BuildDir = "build_vivado",
    [ValidatePattern('^[A-Z]:$')][string]$DriveLetter = "Z:"
)

$ErrorActionPreference = "Stop"

function Resolve-OpenflexPath {
    param([string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return (Join-Path $scriptRoot $PathValue)
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildDirPath = Resolve-OpenflexPath $BuildDir
$yamlPath = Resolve-OpenflexPath $Yaml
$csvPath = Resolve-OpenflexPath $Csv
$tclSource = Join-Path $scriptRoot "route_from_post_place_openflex_finish.tcl"
$tclTarget = Join-Path $buildDirPath "route_from_post_place_openflex_finish.tcl"
$postPlaceDcp = Join-Path $buildDirPath "outputs\\post_place.dcp"

if (!(Test-Path -LiteralPath $tclSource)) {
    throw "Missing Tcl source: $tclSource"
}

if (!(Test-Path -LiteralPath $buildDirPath)) {
    throw "Missing build directory: $buildDirPath"
}

if (!(Test-Path -LiteralPath $postPlaceDcp)) {
    throw "Missing post-place checkpoint: $postPlaceDcp"
}

if (!(Test-Path -LiteralPath $yamlPath)) {
    throw "Missing OpenFlex YAML file: $yamlPath"
}

Copy-Item -LiteralPath $tclSource -Destination $tclTarget -Force

subst $DriveLetter $buildDirPath | Out-Null
try {
    cmd /c "$DriveLetter && vivado.bat -mode batch -source route_from_post_place_openflex_finish.tcl"
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado resume route failed with exit code $LASTEXITCODE."
    }
} finally {
    subst $DriveLetter /d | Out-Null
}

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if ($null -ne $pythonCmd) {
    $pythonExe = $pythonCmd.Source
} else {
    $pythonExe = Join-Path $env:USERPROFILE "envs\\openflex\\Scripts\\python.exe"
}

if (!(Test-Path -LiteralPath $pythonExe)) {
    throw "Could not find python.exe. Activate the openflex environment or install Python in PATH."
}

$pythonCode = @"
from openflex.config import FlexConfig

cfg = FlexConfig(r"$yamlPath")
if len(cfg.combinations) != 1:
    raise RuntimeError(f"Expected exactly one parameter combination, found {len(cfg.combinations)}")

cfg.process_vivado_results(cfg.combinations[0], r"$csvPath")
print(r"$csvPath")
"@

$pythonCode | & $pythonExe -
if ($LASTEXITCODE -ne 0) {
    throw "OpenFlex CSV post-processing failed with exit code $LASTEXITCODE."
}

Write-Host "Route recovery finished."
Write-Host "Reports updated in $buildDirPath\\outputs"
Write-Host "CSV updated at $csvPath"
