# Ralph Loop

**lperez37's flavor** of the Ralph Loop. My own opinionated take on supervised autonomous development with Claude Code.

## What is this

A Ralph Loop is an external bash wrapper around `claude -p` that turns Claude Code into an autonomous builder. Instead of one long interactive session where context accumulates until the model loses track, each iteration starts fresh: Claude reads the plan, the config and the learnings from disk, picks the next task, implements it, validates it, commits and pushes. Then the loop restarts with a clean context window.

The problem it solves is simple. Running `claude -p` once works for small tasks. But for anything that takes more than a few iterations (a multi-file feature, a migration, a full project scaffold), a single session degrades. The context fills up, Claude starts forgetting earlier decisions, and you end up babysitting it. The Ralph Loop fixes this by externalizing state to disk. Every iteration gets the full picture without the accumulated noise.

**Why this is better than building without it:**
- **Fresh context every iteration.** No degradation over long tasks. Iteration 25 is as sharp as iteration 1.
- **Circuit breakers.** If Claude gets stuck and produces no commits for N consecutive iterations, the loop stops instead of burning through your usage limits.
- **Persistent learnings.** Mistakes from iteration 3 become constraints in iteration 4. Claude accumulates knowledge without accumulating context.
- **Completion promises.** The loop does not just check off tasks. It can verify a contract like `ALL TESTS PASS AND ALL ENDPOINTS RETURN 200` before exiting.
- **You do not have to watch it.** Push notifications via ntfy tell you when it finishes, gets stuck or hits the circuit breaker.

**Working around session and usage limits.** Claude Code has session limits and weekly usage caps. The `--delay` and `--at` flags let you schedule loops to run during off-peak hours or spread work across days. Run `./loop.sh build --at 01:30` to kick off a build at 1:30 AM when your usage resets, or `--delay 3h` to space out multiple loops. This turns a weekly limit into a scheduling problem instead of a blocker.

This is not the canonical Ralph Loop implementation. I shaped it around how I actually work: the defaults, the integrations (Vikunja, GitHub Issues, Playwright MCP) and the workflow that make sense for my projects.

## How it works

```
You define a goal
        |
        v
  scaffold.sh sets up .ralph/ directory
        |
        v
  loop.sh plan  -->  generates IMPLEMENTATION_PLAN.md
        |
        v
  loop.sh build -->  iterates: claude -p reads prompt, picks next task,
        |            implements, validates, commits, pushes
        |
        v   (each iteration)
  [read learnings] -> [pick task] -> [implement] -> [build/test/lint]
        |                                                  |
        |                                         pass?    |  fail?
        |                                           |      |
        |                                  [commit+push] [fix it]
        |                                           |
        v                                           v
  [append learnings] <-----------------------------/
        |
        v
  Exit when: all tasks done | promise fulfilled | max iterations | circuit breaker
```

Each iteration gets **fresh context**. Claude reads the plan, config and learnings from disk. No context window accumulation across iterations.

## Quick start

```bash
# Clone into your project
git clone https://github.com/lperez37/ralph-loop.git /tmp/ralph-loop

# Scaffold a project
cd your-project/
bash /tmp/ralph-loop/scripts/scaffold.sh \
  --goal "Build user authentication with JWT" \
  --template-dir /tmp/ralph-loop/templates

# Generate a plan
./loop.sh plan

# Review the plan, then build
./loop.sh build
```

Or the simplest version, a promise-only loop with no plan:

```bash
bash /tmp/ralph-loop/scripts/scaffold.sh \
  --goal "Fix the flaky auth tests" \
  --template-dir /tmp/ralph-loop/templates \
  --completion-promise "ALL AUTH TESTS PASS ON 3 CONSECUTIVE RUNS"

./loop.sh build
```

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude` command)
- `git` (the loop tracks progress via commits)
- `bash` 4+, `perl` (for template substitution)
- `curl` (for ntfy notifications, optional)
- `python3` (for `status` command JSON formatting, optional)

## Commands

### `scaffold.sh`

Sets up the `.ralph/` directory structure in your project.

```bash
bash scaffold.sh --goal "Your goal here" --template-dir /path/to/templates [options]
```

| Option | Description |
|--------|-------------|
| `--goal TEXT` | Project goal (fills templates) |
| `--template-dir PATH` | Path to the `templates/` directory |
| `--vikunja-task-id ID` | Drive the loop from a Vikunja task tree |
| `--completion-promise TEXT` | Verification contract (see [Completion promises](#completion-promises)) |
| `--tdd` | Enable Test-Driven Development mode |
| `--playwright` | Enable Playwright MCP browser verification after each task |

Auto-detects build/test/lint commands for Node.js, Rust, Go, Python, Java (Maven/Gradle) and Makefile projects.

### `loop.sh`

The main loop runner.

```bash
./loop.sh [command] [options]
```

| Command | Description |
|---------|-------------|
| `build [N]` | Build mode (default). N = max iterations, default 25 |
| `plan [N]` | Plan mode. N = max iterations, default 5 |
| `status` | Show progress from `.ralph/state/progress.json` |
| `clean` | Remove `.ralph/` (preserves IMPLEMENTATION_PLAN.md and learnings) |
| `clean --all` | Remove everything |

| Option | Description |
|--------|-------------|
| `--delay DURATION` | Delay start (e.g. `3h`, `30m`, `1h30m`) |
| `--at TIME` | Start at specific time (e.g. `01:30`) |
| `--model MODEL` | Override Claude model (default: `opus`) |
| `--prompt FILE` | Override prompt file |

```bash
./loop.sh build 50                # 50 iterations
./loop.sh build --delay 3h        # Start in 3 hours
./loop.sh build --at 01:30        # Start at 1:30 AM
./loop.sh plan                    # Generate implementation plan
./loop.sh status                  # Check progress
```

## Project structure after setup

```
your-project/
├── loop.sh                       # Loop runner (executable)
├── IMPLEMENTATION_PLAN.md        # Task plan (at root for easy reference)
└── .ralph/                       # Hidden, gitignored
    ├── config.sh                 # Configuration (bash-sourceable)
    ├── prompt-build.md           # Build prompt (fed to claude -p)
    ├── prompt-plan.md            # Plan prompt
    ├── learnings.md              # Persistent memory across iterations
    ├── logs/
    │   └── ralph_build_*.log     # Full session logs
    └── state/
        └── progress.json         # Machine-readable progress
```

## Configuration

All variables live in `.ralph/config.sh`:

| Variable | Default | Description |
|----------|---------|-------------|
| `RALPH_MODEL` | `opus` | Claude model |
| `RALPH_DEFAULT_BUILD_ITERATIONS` | `25` | Default build iterations |
| `RALPH_DEFAULT_PLAN_ITERATIONS` | `5` | Default plan iterations |
| `RALPH_PROJECT_GOAL` | | One-line project goal |
| `RALPH_COMPLETION_PROMISE` | | Verification contract text |
| `RALPH_TDD` | `false` | Enable Red-Green-Refactor per task |
| `RALPH_PLAYWRIGHT` | `false` | Enable Playwright MCP browser verification |
| `RALPH_MAX_STALL` | `3` | Circuit breaker: consecutive no-change iterations |
| `RALPH_VIKUNJA_TASK_ID` | | Vikunja parent task ID |
| `RALPH_GH_ISSUES` | `false` | Enable GitHub Issues as task source |
| `RALPH_GH_LABEL` | `ralph-loop` | GitHub label for issue-sourced tasks |
| `RALPH_DEV_CMD` | | Dev server start command (e.g. `npm run dev`) |
| `RALPH_DEV_PORT` | | Dev server port for health checks |
| `RALPH_NTFY_TOPIC` | `ralph-loop` | ntfy notification topic |
| `RALPH_NTFY_URL` | | Full ntfy URL (overrides topic) |

## Features

### Circuit breaker

Stops automatically after N consecutive iterations with no git commits (default: 3). Prevents infinite loops when Claude gets stuck. Configurable via `RALPH_MAX_STALL`.

### Completion promises

A verification contract. The loop does not just check off tasks, it proves the system actually works.

```bash
bash scaffold.sh \
  --goal "Migrate to PostgreSQL" \
  --completion-promise "ALL TESTS PASS AND ALL ENDPOINTS RETURN EXPECTED STATUS CODES"
```

Claude can only exit the loop by outputting `<promise>EXACT TEXT</promise>` when the statement is genuinely true. The comparison is literal and case-sensitive. Claude is explicitly instructed not to output false promises.

Suggested promises by project type:

| Type | Promise |
|------|---------|
| Web app (Playwright) | `BUILD SUCCEEDS AND ALL E2E TESTS PASS` |
| Web app (no E2E) | `BUILD SUCCEEDS AND ALL TESTS PASS AND DEV SERVER RESPONDS 200` |
| API / backend | `BUILD SUCCEEDS AND ALL TESTS PASS AND ALL ENDPOINTS RETURN EXPECTED STATUS CODES` |
| CLI tool | `SCRIPT RUNS WITHOUT ERRORS AND PRODUCES EXPECTED OUTPUT` |
| Library | `BUILD SUCCEEDS AND ALL TESTS PASS AND NO TYPE ERRORS` |
| Refactoring | `ALL EXISTING TESTS PASS AND NO TYPE ERRORS AND NO LINT WARNINGS` |
| Bug fix | `THE BUG IS FIXED AND THE REGRESSION TEST PASSES` |
| Infrastructure | `ALL CONTAINERS START AND HEALTH CHECKS PASS` |
| Data pipeline | `PIPELINE RUNS END-TO-END AND OUTPUT MATCHES EXPECTED SCHEMA` |

### TDD mode

When enabled (`--tdd` or `RALPH_TDD=true`), every task follows Red-Green-Refactor:

1. **RED** -- Write a failing test first. Run tests, verify it fails.
2. **GREEN** -- Write minimum implementation. Run tests, verify it passes.
3. **IMPROVE** -- Refactor. Tests stay green. Cover edge cases. Target 80%+ coverage.

### Persistent learnings

`.ralph/learnings.md` accumulates knowledge across iterations:

- **Codebase Patterns** -- conventions, helpers, existing code to reuse
- **Signs** -- learned constraints from mistakes (format: `**Sign:** [constraint] -- discovered iteration N ([what went wrong])`)

Claude reads learnings at the start of every iteration and appends after each task. Learnings survive `./loop.sh clean` (only deleted with `clean --all`).

### Notifications

Push notifications via [ntfy](https://ntfy.sh) on start, completion, circuit breaker and interruption.

- Default topic: `ralph-loop` on ntfy.sh
- Quiet hours (00:00-07:00 CET): minimum priority
- Override with `RALPH_NTFY_URL` for a self-hosted instance

> **Self-hosted ntfy:** If you run your own ntfy server, you need to set `RALPH_NTFY_URL` in `.ralph/config.sh` to your instance's full URL (e.g. `https://ntfy.yourdomain.com/your-topic`). The default points to the public `ntfy.sh` service. It will not reach your self-hosted server unless you update this variable.

### Playwright MCP browser verification

When enabled (`--playwright` or `RALPH_PLAYWRIGHT=true`), Claude uses the Playwright MCP server to verify UI changes after each task:

1. Navigates to `http://localhost:RALPH_DEV_PORT` via `mcp__playwright__browser_navigate`
2. Takes a page snapshot via `mcp__playwright__browser_snapshot` to verify rendering
3. Checks `mcp__playwright__browser_console_messages` for JS errors
4. For UI-affecting tasks, interacts with the page to verify changes

Requires:
- [Playwright MCP server](https://github.com/anthropics/mcp-servers) configured in Claude settings
- `RALPH_DEV_CMD` and `RALPH_DEV_PORT` set (the loop manages the dev server lifecycle)

```bash
bash scaffold.sh \
  --goal "Build dashboard with charts" \
  --playwright \
  --completion-promise "BUILD SUCCEEDS AND ALL E2E TESTS PASS"
```

### Delayed start

```bash
./loop.sh build --delay 3h        # Start in 3 hours
./loop.sh build --at 01:30        # Start at 01:30 (tomorrow if past)
```

### Dev server management

If `RALPH_DEV_CMD` and `RALPH_DEV_PORT` are configured, the loop auto-starts the dev server before iterations and health-checks it.

### Task sources

The loop supports three task sources (or none, promise-only):

| Source | Config | How it works |
|--------|--------|-------------|
| Standalone | (default) | Claude explores codebase, generates plan |
| GitHub Issues | `RALPH_GH_ISSUES=true` | Tasks from labeled issues |
| Vikunja | `RALPH_VIKUNJA_TASK_ID=ID` | Tasks from Vikunja subtree, syncs completion back |
| Promise-only | `RALPH_COMPLETION_PROMISE=...` | No plan, just goal + verification |

## IMPLEMENTATION_PLAN.md format

```markdown
### Task N: [Title]
- **Files:** src/foo.ts, src/bar.ts
- **Action:** What to do (specific, actionable)
- **Verify:** `npm run build && npm test`
- **Parallel:** true
- **Status:** [ ] Pending
```

Tasks are marked `[x]` and moved to a `## Completed` section when done.

## Prompt engineering

The build prompt uses a numbered step system:

| Range | Purpose |
|-------|---------|
| `0a-0f` | Context loading (config, learnings, plan, agents, source files) |
| `1-5` | Main workflow (choose task, implement, validate, commit) |
| `99` | Append learnings after each task |
| `999` | Maintain AGENTS.md (under 60 lines) |
| `9998` | Output `RALPH_COMPLETE` when all tasks done |
| `9999` | Output `<promise>` when completion promise is true |

Edit `.ralph/prompt-build.md` to customize for your project.

## Completion signals

The loop exits when it detects one of these (checked each iteration, in order):

1. **Promise tag** -- `<promise>EXACT TEXT</promise>` matches `RALPH_COMPLETION_PROMISE`
2. **RALPH_COMPLETE** -- all tasks in IMPLEMENTATION_PLAN.md marked complete
3. **Max iterations** -- reached `MAX_ITERATIONS`
4. **Circuit breaker** -- `RALPH_MAX_STALL` consecutive iterations with no git changes

## Legacy migration

If you have an older Ralph setup (`.ralph-config`, `PROMPT_build.md` at root, `.ralph-logs/`), the new `loop.sh` falls back to legacy locations automatically. To fully migrate:

```bash
bash scaffold.sh --goal "Your goal"     # Creates new structure
mv PROMPT_build.md .ralph/prompt-build.md
mv .ralph-config .ralph/config.sh
mv .ralph-logs/* .ralph/logs/
```

## License

MIT
