param(
    [string]$VitisRoot = "C:\Xilinx\Vitis\2024.2",
    [string]$Workspace = "",
    [string]$Xsa = "",
    [switch]$NoClean
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path

if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = Join-Path $RepoRoot "build\vitis_cli"
}

if ([string]::IsNullOrWhiteSpace($Xsa)) {
    $Xsa = Join-Path $RepoRoot "build\vivado\zuboard_bnn_fcc\zuboard_bnn_fcc.xsa"
}

$XsctBat = Join-Path $VitisRoot "bin\xsct.bat"
if (!(Test-Path -LiteralPath $XsctBat)) {
    throw "Could not find XSCT: $XsctBat"
}

if (!(Test-Path -LiteralPath $Xsa)) {
    throw "Could not find XSA: $Xsa. Run the Vivado build first."
}

$env:BNN_REPO_ROOT = $RepoRoot
$env:BNN_VITIS_WORKSPACE = $Workspace
$env:BNN_XSA = $Xsa
$env:BNN_CLEAN = if ($NoClean) { "0" } else { "1" }

if (!$NoClean -and (Test-Path -LiteralPath $Workspace)) {
    $ResolvedWorkspace = (Resolve-Path -LiteralPath $Workspace).Path
    $BuildRoot = (Resolve-Path -LiteralPath (Join-Path $RepoRoot "build")).Path
    if (!$ResolvedWorkspace.StartsWith($BuildRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove workspace outside repo build directory: $ResolvedWorkspace"
    }
    Remove-Item -Recurse -Force -LiteralPath $ResolvedWorkspace
}

$BuildScript = Join-Path $ScriptDir "build_app.tcl"

Push-Location "C:\Xilinx"
try {
    & $XsctBat $BuildScript
    if ($LASTEXITCODE -ne 0) {
        throw "XSCT app build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$Elf = Get-ChildItem -Path $Workspace -Recurse -Filter "bnn_fcc_demo.elf" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 -ExpandProperty FullName

if ([string]::IsNullOrWhiteSpace($Elf) -or !(Test-Path -LiteralPath $Elf)) {
    throw "Build command completed, but bnn_fcc_demo.elf was not found under $Workspace"
}

Write-Host ""
Write-Host "Built BNN demo app."
Write-Host "Workspace: $Workspace"
Write-Host "ELF: $Elf"
