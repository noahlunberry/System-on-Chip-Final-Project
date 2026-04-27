param(
    [string]$VitisRoot = "C:\Xilinx\Vitis\2024.2",
    [string]$Workspace = "",
    [string]$Bit = "",
    [string]$Elf = "",
    [string]$PsuInit = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path

if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = Join-Path $RepoRoot "build\vitis_cli"
}

if ([string]::IsNullOrWhiteSpace($Bit)) {
    $Bit = Join-Path $RepoRoot "build\vivado\zuboard_bnn_fcc\zuboard_bnn_fcc.runs\impl_1\zuboard_bnn_fcc_bd_wrapper.bit"
}

if ([string]::IsNullOrWhiteSpace($PsuInit)) {
    $PsuInit = Join-Path $RepoRoot "build\vivado\zuboard_bnn_fcc\zuboard_bnn_fcc.gen\sources_1\bd\zuboard_bnn_fcc_bd\ip\zuboard_bnn_fcc_bd_zynq_ultra_ps_e_0_0\psu_init.tcl"
}

if ([string]::IsNullOrWhiteSpace($Elf)) {
    $Elf = Get-ChildItem -Path $Workspace -Recurse -Filter "bnn_fcc_demo.elf" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

$XsctBat = Join-Path $VitisRoot "bin\xsct.bat"
if (!(Test-Path -LiteralPath $XsctBat)) {
    throw "Could not find XSCT: $XsctBat"
}
if (!(Test-Path -LiteralPath $Bit)) {
    throw "Could not find bitstream: $Bit. Run the Vivado build first."
}
if (!(Test-Path -LiteralPath $PsuInit)) {
    throw "Could not find psu_init.tcl: $PsuInit. Run the Vivado build first."
}
if ([string]::IsNullOrWhiteSpace($Elf) -or !(Test-Path -LiteralPath $Elf)) {
    throw "Could not find bnn_fcc_demo.elf under $Workspace. Run sw\cli\build_app.ps1 first."
}

$env:BNN_BIT = $Bit
$env:BNN_ELF = $Elf
$env:BNN_PSU_INIT = $PsuInit

$RunScript = Join-Path $ScriptDir "run_jtag.tcl"

Push-Location "C:\Xilinx"
try {
    & $XsctBat $RunScript
    if ($LASTEXITCODE -ne 0) {
        throw "XSCT JTAG run failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
