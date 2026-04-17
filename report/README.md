# Report Workspace

This directory contains a lightweight LaTeX report scaffold for the `bnn_fcc_contest` repository.

## Local Tool Setup

Local compilation on Windows is set up around MiKTeX.

Install MiKTeX with:

```powershell
winget install --id MiKTeX.MiKTeX --accept-package-agreements --accept-source-agreements --silent
```

After installation:

- reopen PowerShell so `pdflatex` is added to `PATH`, or
- use `build.ps1`, which also checks the default MiKTeX install path directly.

MiKTeX is configured to auto-install missing LaTeX packages on first use, so the
first compile may take longer and may require internet access.

## Layout

- `main.tex`: main report entry point
- `build.ps1`: local compile helper for the full report or a standalone figure
- `sections/`: report text split into editable section files
- `figures/`: reusable TikZ figure sources and standalone wrappers

## Current Figure

- `figures/config_manager_diagram.tex`: reusable TikZ source
- `figures/config_manager_diagram_standalone.tex`: standalone preview wrapper
- `figures/data_in_manager_diagram.tex`: data-input datapath figure
- `figures/data_in_manager_diagram_standalone.tex`: standalone preview wrapper
- `figures/config_manager_parser_fsmd.tex`: parser FSMD figure
- `figures/config_manager_pad_fsm_fsmd.tex`: pad-FSM FSMD figure
- `figures/config_controller_fsmd.tex`: layer-local config-controller FSMD figure

## Typical Workflow

Compile the full report from `report/`:

```powershell
.\build.ps1
```

Preview just the config-manager figure:

```powershell
.\build.ps1 -File .\figures\config_manager_diagram_standalone.tex
```

If you prefer to compile manually, run two `pdflatex` passes:

```powershell
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

This report template intentionally uses plain `pdflatex` instead of `latexmk`
so it does not require a separate Perl installation.

## Notes

- The report text is intentionally minimal and repo-specific so we can build it out together.
- The current template assumes a standard technical report. If you want IEEE, ACM, or a course-specific format, we can swap the document class next.
