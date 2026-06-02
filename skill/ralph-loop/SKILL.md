---
name: ralph-loop
description: |
  Set up and run a supervised Ralph Wiggum loop for autonomous iterative development.
  Ships battle-tested templates for loop.sh, prompts, and config. Supports lifecycle
  management (setup, status, resume, clean), delayed start, circuit breaker, ntfy
  notifications, and in-session monitoring. Accepts task sources from GitHub Issues
  or standalone plans. Use when the user says "ralph loop", "set up a loop",
  "autonomous development", "iterative build loop", "ralph status", "ralph clean",
  or wants to run Claude Code autonomously on a plan.
argument-hint: "[setup|plan|build|run|status|resume|clean] [args...]"
---

# Ralph Wiggum Loop

Supervised autonomous development using `loop.sh` — an external bash loop that runs a coding-agent CLI in iterations with fresh context each time. The engine is configurable: **`claude`** (Claude Code, default), **`codex`** (OpenAI Codex CLI), or **`opencode`**. Set it with `--engine` at setup or `RALPH_ENGINE` in `.ralph/config.sh`; all loop features behave identically across engines.

| Engine | Per-iteration invocation | Model format |
|--------|--------------------------|--------------|
| `claude` | `claude -p` (prompt on stdin) | plain (`opus`, `sonnet`) |
| `codex` | `codex exec -` (prompt on stdin) | e.g. `gpt-5.3-codex` |
| `opencode` | `opencode run "<prompt>"` (prompt as arg) | `provider/model` |

## Commands

| Command | What it does |
|---------|-------------|
| `/ralph-loop setup "goal"` | Scaffold `.ralph/`, copy templates, configure, add to `.gitignore` |
| `/ralph-loop plan` | Generate or regenerate IMPLEMENTATION_PLAN.md (via loop or interactively) |
| `/ralph-loop build [N] [--delay T] [--at HH:MM]` | Start building from IMPLEMENTATION_PLAN.md |
| `/ralph-loop run [plan\|build] [N]` | In-session: launch loop.sh in background, follow output |
| `/ralph-loop status` | Show progress: tasks done/remaining, stalls, elapsed time |
| `/ralph-loop resume` | Pick up where the last loop left off |
| `/ralph-loop clean` | Remove `.ralph/` directory (keep IMPLEMENTATION_PLAN.md) |
| `/ralph-loop clean --all` | Remove `.ralph/` AND IMPLEMENTATION_PLAN.md |
| `/ralph-loop` (no args) | Interactive setup with questions |

## Setup

### `/ralph-loop setup "goal"`

1. Locate the skill directory and run the scaffold script. The skill ships with its own `scripts/` and `templates/` directories, so both live next to `SKILL.md`:

```bash
SKILL_DIR=$(find ~/.claude/skills -path "*/ralph-loop/scripts/scaffold.sh" -print -quit 2>/dev/null | xargs -r dirname | xargs -r dirname)
if [ -z "$SKILL_DIR" ]; then
  echo "Cannot find ralph-loop skill in ~/.claude/skills. See https://github.com/lperez37/ralph-loop for installation."
  exit 1
fi
bash "$SKILL_DIR/scripts/scaffold.sh" --goal "THE_GOAL" --template-dir "$SKILL_DIR/templates"
```

Optional flags: `--engine claude|codex|opencode`, `--model MODEL`, `--completion-promise "TEXT"`, `--tdd`, `--playwright`

To scaffold for a non-Claude engine:

```bash
bash "$SKILL_DIR/scripts/scaffold.sh" --goal "THE_GOAL" --template-dir "$SKILL_DIR/templates" --engine codex
bash "$SKILL_DIR/scripts/scaffold.sh" --goal "THE_GOAL" --template-dir "$SKILL_DIR/templates" --engine opencode --model anthropic/claude-sonnet-4-5
```

2. After scaffolding, customize the generated files:

   a. **`.ralph/config.sh`** — Set model, iteration counts, notification topic, dev server.
   b. **`.ralph/prompt-build.md`** — Add project-specific instructions. The scaffold auto-detects build/test/lint commands, but review and adjust.
   c. **`IMPLEMENTATION_PLAN.md`** — Either fill manually or run `/ralph-loop plan` to generate.

3. Ask the user these configuration questions (apply answers to `.ralph/config.sh`):
   - Engine? `claude` (default), `codex`, or `opencode`
   - Model preference? (claude default: opus; codex/opencode: leave empty to use the CLI's own default)
   - Max build iterations? (default: 25)
   - Task source? GitHub Issues or standalone plan? (default: standalone)
   - If GitHub Issues: label? (default: ralph-loop)
   - TDD mode? (default: false — enables Red-Green-Refactor workflow)
   - Notification topic on ntfy.sh? (default: ralph-loop)
   - Dev server command and port? (default: none)
   - Playwright browser verification? (default: false — requires Playwright MCP and a dev server)

4. Output the commands to start:
```bash
chmod +x loop.sh
./loop.sh plan                    # Generate implementation plan
./loop.sh build                   # Start building (default iterations)
./loop.sh build 50                # Build with 50 iterations
./loop.sh build --delay 3h        # Start in 3 hours
./loop.sh build --at 01:30        # Start at 01:30
```

### Interactive mode (`/ralph-loop` no args)

Walk through setup questions interactively, then run the scaffold. Same as `setup` but prompts for the goal.

## Build

### `/ralph-loop build [N] [--delay T] [--at HH:MM]`

Tell the user to run:
```bash
./loop.sh build [N] [--delay DURATION] [--at TIME]
```

If they want to run it from the current session, use `/ralph-loop run build` instead.

### `/ralph-loop plan`

Tell the user to run:
```bash
./loop.sh plan
```

Or generate the plan interactively in the current session by reading the codebase and writing IMPLEMENTATION_PLAN.md directly.

## In-Session Mode

### `/ralph-loop run [plan|build] [N]`

Launch loop.sh from within the Claude Code session:

1. Verify `.ralph/` exists and loop.sh is executable.
2. Run the loop in the background:

```bash
./loop.sh build 2>&1 | tee .ralph/logs/session-$(date +%Y%m%d_%H%M%S).log
```

Use the Bash tool with `run_in_background: true`.

3. Report to the user that the loop is running.
4. When the background process completes, read `.ralph/state/progress.json` and the log file to report results.
5. If the user asks for status mid-run, read progress.json:

```bash
cat .ralph/state/progress.json
```

## Status

### `/ralph-loop status`

Read and display the current state:

1. Check if `.ralph/state/progress.json` exists.
2. If yes, parse and display:
   - Current iteration / max iterations
   - Tasks done / total (from IMPLEMENTATION_PLAN.md)
   - Stall count
   - Elapsed time
   - Last commit SHA
   - Status (running / finished)
3. If no progress.json, count tasks from IMPLEMENTATION_PLAN.md directly:

```bash
echo "Done:    $(grep -cE '(\- \[x\]|\*\*Status:\*\* \[x\])' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)"
echo "Pending: $(grep -cE '(\- \[ \]|\*\*Status:\*\* \[ \])' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)"
```

4. Show recent git activity:
```bash
git log --oneline -10
```

### `/ralph-loop resume`

Pick up where the last loop left off:

1. Read `.ralph/state/progress.json` to find last iteration and remaining tasks.
2. Verify IMPLEMENTATION_PLAN.md has pending tasks.
3. Tell the user to run `./loop.sh build` (it naturally picks up pending tasks).
4. Or use `/ralph-loop run build` for in-session mode.

## Clean

### `/ralph-loop clean`

Always delegate to loop.sh — it preserves learnings.md across clean cycles:

```bash
./loop.sh clean
```

This removes `.ralph/` but restores `.ralph/learnings.md` so accumulated patterns and signs survive.

### `/ralph-loop clean --all`

```bash
./loop.sh clean --all
```

Removes `.ralph/`, IMPLEMENTATION_PLAN.md, and learnings. Do NOT remove loop.sh — the user may want to keep it for future runs.

## TDD Mode

When `RALPH_TDD=true`, the build prompt enforces Test-Driven Development for every task:

### Workflow per task

1. **RED** — Write a failing test first that describes the expected behavior. Run tests, verify the new test fails.
2. **GREEN** — Write the minimum implementation to make the test pass. Run tests, verify it passes.
3. **IMPROVE** — Refactor the implementation. Tests must stay green. Cover edge cases: null/undefined, empty inputs, invalid types, boundaries, error paths. Target 80%+ coverage.

### When to enable

- New feature development (especially greenfield)
- Bug fixes (write the regression test first, then fix)
- Refactoring (tests protect against regressions)
- Any project where test coverage is a priority

### Setup

Pass `--tdd` to the scaffold:
```bash
bash scaffold.sh --goal "Build user auth" --template-dir ./templates --tdd
```

Or set `RALPH_TDD="true"` in `.ralph/config.sh` at any time.

### TDD + completion promises

TDD pairs well with promises. Suggested promises for TDD loops:

| Scenario | Promise |
|---|---|
| New feature with tests | `ALL TESTS PASS AND COVERAGE ABOVE 80 PERCENT` |
| Bug fix | `THE BUG IS FIXED AND THE REGRESSION TEST PASSES` |
| Refactoring | `ALL EXISTING TESTS PASS AND NO TYPE ERRORS` |

## Completion Promises

A completion promise is a verification contract — the loop doesn't just check off tasks, it proves the system works. Promises are orthogonal to the task source: they work with IMPLEMENTATION_PLAN.md, GitHub Issues, or no task source at all.

### How it works

1. Set `RALPH_COMPLETION_PROMISE` in config (or pass `--completion-promise` to scaffold)
2. The build prompt tells Claude: only output `<promise>EXACT TEXT</promise>` when the statement is genuinely true
3. `loop.sh` extracts the promise text and compares literally — must be an exact match
4. Claude is explicitly forbidden from outputting false promises to escape the loop

### Promise-only loops

The simplest Ralph loop: no task plan, no issues — just a goal and a promise.

```bash
bash scaffold.sh \
  --goal "Fix the flaky auth tests" \
  --completion-promise "ALL AUTH TESTS PASS ON 3 CONSECUTIVE RUNS"

# No plan needed — Claude works toward the goal until the promise is true
./loop.sh build
```

### Suggesting promises during setup

When running `/ralph-loop setup`, suggest an appropriate completion promise based on the project type. Use these as starting points:

| Project type | Suggested promise |
|---|---|
| Web app (with Playwright) | `BUILD SUCCEEDS AND ALL E2E TESTS PASS` |
| Web app (no E2E) | `BUILD SUCCEEDS AND ALL TESTS PASS AND DEV SERVER RESPONDS 200` |
| API / backend service | `BUILD SUCCEEDS AND ALL TESTS PASS AND ALL ENDPOINTS RETURN EXPECTED STATUS CODES` |
| CLI tool / script | `SCRIPT RUNS WITHOUT ERRORS AND PRODUCES EXPECTED OUTPUT` |
| Library / package | `BUILD SUCCEEDS AND ALL TESTS PASS AND NO TYPE ERRORS` |
| Refactoring | `ALL EXISTING TESTS PASS AND NO TYPE ERRORS AND NO LINT WARNINGS` |
| Bug fix | `THE BUG IS FIXED AND THE REGRESSION TEST PASSES` |
| Infrastructure / Docker | `ALL CONTAINERS START AND HEALTH CHECKS PASS` |
| Data pipeline | `PIPELINE RUNS END-TO-END AND OUTPUT MATCHES EXPECTED SCHEMA` |

These are suggestions — always let the user customize. Promises should be:
- Verifiable by running commands (not subjective)
- Specific enough to prevent false positives
- Short enough to be memorable (one sentence)

## Learnings

`.ralph/learnings.md` is persistent memory across iterations. It has two sections:

### Codebase Patterns

Conventions, helpers, and existing code that Claude discovered and should reuse. Examples:
```
- All API routes use the `withAuth` middleware wrapper
- Pagination helper exists at src/lib/paginate.ts — don't create a new one
- CSS modules use camelCase, not kebab-case
```

### Signs

Learned constraints that prevent repeated mistakes. Named after "traffic signs" — warnings that come from real incidents. Format:
```
- **Sign:** Always run typecheck before commit — discovered iteration 3 (committed with type errors that broke CI)
- **Sign:** Use existing pagination helper at src/lib/paginate.ts — discovered iteration 4 (created duplicate pagination logic)
```

Signs are append-only. Mistakes evaporate, lessons accumulate. Claude reads learnings at the start of every iteration (step 0b) and appends after each completed task (step 99).

## Directory Structure

After setup, the project has:

```
project/
├── loop.sh                       # Loop runner (from template, executable)
├── IMPLEMENTATION_PLAN.md        # Task plan (human-readable, at root for @ references)
├── AGENTS.md                     # Optional: backpressure commands for Claude
└── .ralph/                       # Hidden directory (gitignored)
    ├── config.sh                 # Loop configuration (bash-sourceable)
    ├── prompt-build.md           # Build mode prompt
    ├── prompt-plan.md            # Plan mode prompt
    ├── learnings.md              # Persistent inter-iteration memory
    ├── logs/
    │   └── ralph_build_*.log     # Per-session logs
    └── state/
        └── progress.json         # Machine-readable progress
```

## Prompt Engineering

The prompt templates use a proven numbering pattern:

| Range | Purpose | Example |
|-------|---------|---------|
| `0a-0f` | Context loading | Config, learnings, plan, agents, source files |
| `1-5` | Main workflow | Choose task, implement, validate, commit |
| `99` | Learnings | Append codebase patterns and signs after each task |
| `999` | AGENTS.md | Keep under 60 lines, update operational notes |
| `9998` | Task completion | Output RALPH_COMPLETE when all tasks done |
| `9999` | Promise | Output `<promise>` when completion promise is true |

Key conventions:
- `@IMPLEMENTATION_PLAN.md` and `@AGENTS.md` references tell Claude to read these files.
- "Maximize parallelism with subagents" encourages Claude to use parallel tool calls.
- Build/test/lint commands are validated BEFORE committing.
- Tasks are marked `[x]` and moved to Completed section on success.

### Customizing prompts

Edit `.ralph/prompt-build.md` to add project-specific rules:
- Browser verification steps (Playwright)
- Dev server management
- Specific file patterns or conventions
- GitHub issue references to close

## Configuration Reference

All variables in `.ralph/config.sh`:

| Variable | Default | Description |
|----------|---------|-------------|
| `RALPH_ENGINE` | `claude` | Coding agent CLI: `claude`, `codex`, or `opencode` |
| `RALPH_MODEL` | `opus` | Model for the engine. Empty = engine default (claude falls back to `opus`) |
| `RALPH_CODEX_SANDBOX` | (none) | codex only. Sandbox policy (`read-only`/`workspace-write`/`danger-full-access`); empty = fully autonomous |
| `RALPH_OPENCODE_AGENT` | `build` | opencode only. Agent to run (`build` edits, `plan` is read-only) |
| `RALPH_DEFAULT_BUILD_ITERATIONS` | `25` | Default iterations for build mode |
| `RALPH_DEFAULT_PLAN_ITERATIONS` | `5` | Default iterations for plan mode |
| `RALPH_PROJECT_GOAL` | (none) | One-line project goal |
| `RALPH_GH_ISSUES` | `false` | Enable GitHub Issues integration |
| `RALPH_GH_LABEL` | `ralph-loop` | Label for Ralph-created issues |
| `RALPH_COMPLETION_PROMISE` | (none) | Completion promise text (e.g., `ALL TESTS PASS`) |
| `RALPH_TDD` | `false` | Enable TDD mode (Red-Green-Refactor per task) |
| `RALPH_PLAYWRIGHT` | `false` | Enable Playwright MCP browser verification after each task |
| `RALPH_MAX_STALL` | `3` | Circuit breaker threshold (consecutive no-change iterations) |
| `RALPH_DEV_CMD` | (none) | Dev server start command (e.g., `npm run dev`) |
| `RALPH_DEV_PORT` | (none) | Dev server port to health-check |
| `RALPH_NTFY_TOPIC` | `ralph-loop` | ntfy notification topic |
| `RALPH_NTFY_URL` | (auto) | Full ntfy URL (overrides topic-based URL) |

## Loop Features

### Delayed start
```bash
./loop.sh build --delay 3h        # Sleep for 3 hours, then start
./loop.sh build --at 01:30        # Sleep until 01:30, then start
```

### Circuit breaker
Stops automatically after `RALPH_MAX_STALL` consecutive iterations with no git changes (default: 3).

### Completion signals

The loop watches for two exit signals (checked in order each iteration):

1. **`<promise>` tag** — If `RALPH_COMPLETION_PROMISE` is set in config, the loop extracts text from `<promise>...</promise>` in the output and compares it literally against the configured promise. Match = exit.
2. **`RALPH_COMPLETE`** — The build prompt instructs Claude to output this when all tasks in IMPLEMENTATION_PLAN.md are marked complete.

Either signal causes a clean exit. If both a task plan and a promise are configured, the build prompt requires ALL tasks complete AND the promise to be true.

### Notifications
Sends ntfy push notifications on: start, completion, circuit breaker, and stuck detection. Defaults to `https://ntfy.sh/ralph-loop` — override with `RALPH_NTFY_TOPIC` or `RALPH_NTFY_URL`. Quiet hours (00:00-07:00 local time) use minimum priority.

### Dev server management
If `RALPH_DEV_CMD` and `RALPH_DEV_PORT` are set, the loop auto-starts the dev server before each iteration and health-checks it.

### Progress tracking
After each iteration, loop.sh writes `.ralph/state/progress.json` with iteration count, task progress, stall count, and elapsed time. This enables `/ralph-loop status` and `/ralph-loop resume`.
