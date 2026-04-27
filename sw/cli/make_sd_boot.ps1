param(
    [string]$VitisRoot = "C:\Xilinx\Vitis\2024.2",
    [string]$Workspace = "",
    [string]$Bit = "",
    [string]$Elf = "",
    [string]$Fsbl = "",
    [string]$Pmufw = "",
    [string]$OutputDir = "",
    [string]$SdDrive = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path

if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = Join-Path $RepoRoot "build\vitis_cli"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $RepoRoot "build\sd_boot"
}
if ([string]::IsNullOrWhiteSpace($Bit)) {
    $Bit = Join-Path $RepoRoot "build\vivado\zuboard_bnn_fcc\zuboard_bnn_fcc.runs\impl_1\zuboard_bnn_fcc_bd_wrapper.bit"
}
if ([string]::IsNullOrWhiteSpace($Elf)) {
    $Elf = Get-ChildItem -Path $Workspace -Recurse -Filter "bnn_fcc_demo.elf" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if ([string]::IsNullOrWhiteSpace($Fsbl)) {
    $Fsbl = Get-ChildItem -Path $Workspace -Recurse -Filter "fsbl*.elf" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "boot|zynqmp_fsbl" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if ([string]::IsNullOrWhiteSpace($Pmufw)) {
    $Pmufw = Get-ChildItem -Path $Workspace -Recurse -Filter "pmufw.elf" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "boot|zynqmp_pmufw" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

$BootgenBat = Join-Path $VitisRoot "bin\bootgen.bat"
if (!(Test-Path -LiteralPath $BootgenBat)) {
    $BootgenBat = "bootgen"
}

if (!(Test-Path -LiteralPath $Bit)) {
    throw "Could not find bitstream: $Bit. Run the Vivado build first."
}
if ([string]::IsNullOrWhiteSpace($Elf) -or !(Test-Path -LiteralPath $Elf)) {
    throw "Could not find bnn_fcc_demo.elf under $Workspace. Run sw\cli\build_app.ps1 first."
}
if ([string]::IsNullOrWhiteSpace($Fsbl) -or !(Test-Path -LiteralPath $Fsbl)) {
    throw "Could not find FSBL ELF under $Workspace. Run sw\cli\build_app.ps1 first."
}
if ([string]::IsNullOrWhiteSpace($Pmufw) -or !(Test-Path -LiteralPath $Pmufw)) {
    throw "Could not find PMUFW ELF under $Workspace. Run sw\cli\build_app.ps1 first."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$StageDir = Join-Path $OutputDir "stage"
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

$StageFsbl = Join-Path $StageDir "fsbl.elf"
$StagePmufw = Join-Path $StageDir "pmufw.elf"
$StageBit = Join-Path $StageDir "system.bit"
$StageElf = Join-Path $StageDir "bnn_fcc_demo.elf"
$Bif = Join-Path $StageDir "boot.bif"
$BootBin = Join-Path $OutputDir "BOOT.BIN"

Copy-Item -Force -LiteralPath $Fsbl -Destination $StageFsbl
Copy-Item -Force -LiteralPath $Pmufw -Destination $StagePmufw
Copy-Item -Force -LiteralPath $Bit -Destination $StageBit
Copy-Item -Force -LiteralPath $Elf -Destination $StageElf

@"
the_ROM_image:
{
  [bootloader, destination_cpu=a53-0] fsbl.elf
  [pmufw_image] pmufw.elf
  [destination_device=pl] system.bit
  [destination_cpu=a53-0, exception_level=el-3] bnn_fcc_demo.elf
}
"@ | Set-Content -Encoding ASCII -Path $Bif

Push-Location $StageDir
try {
    & $BootgenBat -arch zynqmp -image $Bif -w -o $BootBin
    if ($LASTEXITCODE -ne 0) {
        throw "bootgen failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Created SD boot image."
Write-Host "BOOT.BIN: $BootBin"
Write-Host "FSBL:     $Fsbl"
Write-Host "PMUFW:    $Pmufw"
Write-Host "Bit:      $Bit"
Write-Host "ELF:      $Elf"

if (![string]::IsNullOrWhiteSpace($SdDrive)) {
    $SdRoot = $SdDrive
    if ($SdRoot.Length -eq 1) {
        $SdRoot = "${SdRoot}:\"
    }
    if ($SdRoot.Length -eq 2 -and $SdRoot[1] -eq ':') {
        $SdRoot = "$SdRoot\"
    }
    if (!(Test-Path -LiteralPath $SdRoot)) {
        throw "SD drive path does not exist: $SdRoot"
    }
    Copy-Item -Force -LiteralPath $BootBin -Destination (Join-Path $SdRoot "BOOT.BIN")
    Write-Host "Copied BOOT.BIN to $SdRoot"
}
