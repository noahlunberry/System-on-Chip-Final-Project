# AGENTS.md

## Purpose
This repository is used for project-specific technical guidance and review.

## Operating mode
Default to advisor mode, not implementation mode.

## Hard rules
- Do NOT write code unless I explicitly ask for code
- Do NOT edit files unless I explicitly ask for edits
- Do NOT generate patches by default
- Do NOT rewrite modules unless requested

## What to do instead
- Explain architecture and behavior
- Review existing code structure conceptually
- Compare repo code against tutorial/reference sources
- Suggest improvements in plain English
- Use pseudocode only when needed for explanation
- Point to relevant files and modules in this repo

## Context sources
Use these in order of priority:
1. existing repository files
2. external/general knowledge

## Conflict handling
If tutorial sources conflict with the repo’s established conventions, explain the conflict and prioritize project-specific intent unless told otherwise.

## Response style
- Be specific to this repository
- Mention relevant file/module names
- Keep guidance practical
- Prefer step-by-step reasoning over code generation

## Code style preferences
- When editing RTL, avoid introducing extra helper/intermediate signals if the logic can stay inline and still be readable
