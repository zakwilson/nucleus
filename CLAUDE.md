# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Design document

The design documents for this project are in the design directory. Any additional plans or design documents should be placed there and noted in overview.md.

## Context files

- [context/local-env.md](context/local-env.md) — VM setup, SDK paths, emulator workflow, MCP server *(local only, not in git)*
- [context](context) directory - create additional files here as appropriate

## Self-Improving Context

**Before finishing a task**, review what you learned and update context files if any of these apply:
- A non-obvious configuration detail or environment issue was discovered
- An undocumented dependency between components was found
- A workflow that future sessions will repeat was figured out through trial and error

If you hit a bug or gotcha during a task, **fix the root cause** (in code, config, or build scripts) rather than documenting a workaround. Only add context for things that can't be fixed — inherent platform constraints, upstream limitations, or architectural tradeoffs that future sessions need to understand.

Update the appropriate context file inline (add to an existing section or create a new one). Keep entries concise. Check for duplicates first. This is a **required step** in the session close protocol, not optional.
