# AGENTS.md

This file provides guidance to LLM agents when working with code in this repository.

## Large tasks: delegate to subagents first

**Before starting any large task, stop and plan a subagent delegation strategy — do not begin doing the work yourself in this (orchestrating) session.** A task is "large" if it is multi-phase, spans multiple files, or you would describe it as large, complex, or multi-step. The moment you notice yourself acknowledging that a task is big is the trigger to delegate, not a reason to push ahead solo.

- Read [context/local.md](context/local.md) for the available subagents and how to use them. It is **required reading for large tasks**, not just environment setup.
- Split the work into chunks that each fit comfortably under 100K tokens of context, and dispatch each chunk to the appropriate subagent.
- Keep this session lean: delegate code reading, implementation, building/testing, and doc updates. Reserve the main thread for planning and integration.

## Design document

The design documents for this project are in the design directory. Any additional plans or design documents should be placed there and noted in overview.md.

**Before finishing a task**, review what has changed and update [progress.md](design/progress.md).

## Plans

When making plans, add them to the design documents directory.

## Language documentation

Documentation for the current state of the language lives in the docs directory.

**Before finishing a task**, review what has changed and update the language documentation.

## Context files

- [context/local.md](context/local.md) — container/toolchain setup **and the mandatory subagent-delegation workflow for large tasks** *(local only, not in git)*
- [context/build.md](context/build.md) - build flow and bootstrap artifacts
- [context/macros-jit.md](context/macros-jit.md) - macros and JIT
- [context/repl.md](context/repl.md) - when (and when not) to use `nucleusc -i` during development
- [context](context) directory - create additional files here as appropriate

## Self-Improving Context

**Before finishing a task**, review what you learned and update context files if any of these apply:
- A non-obvious configuration detail or environment issue was discovered
- An undocumented dependency between components was found
- A workflow that future sessions will repeat was figured out through trial and error

If you hit a bug or gotcha during a task, **fix the root cause** (in code, config, or build scripts) rather than documenting a workaround. Only add context for things that can't be fixed — inherent platform constraints, upstream limitations, or architectural tradeoffs that future sessions need to understand.

Update the appropriate context file inline (add to an existing section or create a new one). Keep entries concise. Check for duplicates first. This is a **required step** in the session close protocol, not optional.

## Testing

Upon completing work on a feature, ensure the compiler can compile itself and pass all the tests.

## Pre-release

Nucleus is in pre-release. The only important programs written in Nucleus are its own compiler and the examples. Do not consider backwards-compatibility when making changes, except that the compiler may require temporary shims to bootstrap after a breaking change.
