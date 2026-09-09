# AGENTS.md

This file provides Codex-specific guidance for the `draw-steel-codex` repository.

## Required Repository Guidance

Before modifying files in this repository, read `CLAUDE.md` in full. Treat its
architecture, lifecycle, Lua constraints, editing, and deployment guidance as
repository instructions, subject to the overrides below.

## Codex Overrides

- User, system, skill, and `AGENTS.md` instructions take precedence over
  `CLAUDE.md`.
- For compendium content under `data/`, use `validate_yaml.py` and the live
  references under `data/docs/`. Those sources supersede legacy compendium
  paths or content-workflow guidance in `CLAUDE.md`.
- Where `CLAUDE.md` names Claude Code or Claude-specific tools, use the
  equivalent Codex workflow or tool. If a required integration is unavailable,
  stop and ask the user instead of inventing a substitute.
- This is a nested Git repository with its own history. Run Git commands from
  this repository, not from the parent DMHub repository.

