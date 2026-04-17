param(
    [string]$File = "main.tex",
    [int]$Passes = 2
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetPath = Join-Path $scriptDir $File

if (!(Test-Path -LiteralPath $targetPath)) {
    throw "LaTeX target not found: $targetPath"
}

$pdflatexCmd = Get-Command pdflatex.exe -ErrorAction SilentlyContinue
$pdflatex = if ($pdflatexCmd) {
    $pdflatexCmd.Source
} else {
    $fallback = Join-Path $env:LOCALAPPDATA "Programs\MiKTeX\miktex\bin\x64\pdflatex.exe"
    if (Test-Path -LiteralPath $fallback) { $fallback } else { $null }
}

if (-not $pdflatex) {
    throw "pdflatex.exe was not found. Install MiKTeX or reopen PowerShell so PATH refreshes."
}

$targetDir = Split-Path -Parent $targetPath
$targetName = Split-Path -Leaf $targetPath
$pdfPath = Join-Path $targetDir ([System.IO.Path]::ChangeExtension($targetName, ".pdf"))

$env:PATH = "$(Split-Path -Parent $pdflatex);$env:PATH"

Push-Location $targetDir
try {
    for ($pass = 1; $pass -le $Passes; $pass++) {
        Write-Host ("pdflatex pass {0}/{1}: {2}" -f $pass, $Passes, $targetName)
        & $pdflatex -interaction=nonstopmode -halt-on-error $targetName
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }

    Write-Host "Built PDF: $pdfPath"
} finally {
    Pop-Location
}
