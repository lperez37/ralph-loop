# Ralph Loop

> **Default for long-running loops:** use `./loop.sh supervise build [N]`, not plain `./loop.sh build [N]`. `supervise build` wraps the normal fresh-context loop with a lightweight restart supervisor: it restarts if the child loop exits while monitorable work remains, backs off via the loop's Claude-limit handling, writes `.ralph/state/supervisor.json`, and stops automatically once the task plan or completion promise is done. Use plain `build` only for short foreground runs you are actively watching.

**lperez37's flavor** of the Ralph Loop. My own opinionated take on supervised autonomous development with Claude Code.

## What is this

A Ralph Loop is an external bash wrapper around a coding-agent CLI that turns it into an autonomous builder. Instead of one long interactive session where context accumulates until the model loses track, each iteration starts fresh: the agent reads the plan, the config and the learnings from disk, picks the next task, implements it, validates it, commits and pushes. Then the loop restarts with a clean context window.

It is **engine-agnostic** — pick whichever CLI you have set up:

| Engine | CLI | Non-interactive call | Model format |
|--------|-----|----------------------|--------------|
| `claude` (default) | [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | `claude -p` (stdin) | plain, e.g. `opus`, `sonnet` |
| `codex` | [OpenAI Codex CLI](https://developers.openai.com/codex/cli) | `codex exec -` (stdin) | e.g. `gpt-5.3-codex` |
| `opencode` | [opencode](https://opencode.ai/docs) | `opencode run` (arg) | `provider/model`, e.g. `anthropic/claude-sonnet-4-5` |
| `ccrun` | [ccrun](https://github.com/lperez37/ccrun) | `ccrun` (prompt on stdin) | plain, e.g. `opus`, `sonnet` |

Set the engine once with `--engine` at scaffold time (or `RALPH_ENGINE` in `.ralph/config.sh`); everything else — circuit breaker, promises, learnings, notifications — works identically across all four.

`ccrun` is the odd one out: it is not Anthropic's CLI but a small wrapper of mine that drives the interactive Claude Code REPL headlessly so the run stays on my Claude **subscription** instead of the metered programmatic pool. See [Subscription-pool loops with ccrun](#subscription-pool-loops-with-ccrun) below.

### Subscription-pool loops with ccrun

[`ccrun`](https://github.com/lperez37/ccrun) is a separate small CLI (not part of this repo) that I use as the `ccrun` engine. **It is an optional dependency** — you only need it if you scaffold with `--engine ccrun`.

**Why it exists.** As of Anthropic's 2026-06-15 billing split, `claude -p` and the Agent SDK draw from a capped, metered *programmatic* pool billed at API rates. The **interactive** REPL keeps running on your normal Claude subscription. ccrun drives that interactive REPL headlessly — it spawns `claude` inside a detached tmux session, feeds it one turn, and prints the final assistant message on stdout (the same stdin-in / stdout-out contract as `claude -p`). So a Ralph loop run via `--engine ccrun` stays on the subscription pool instead of burning metered programmatic credit.

**Install.** Requires Node ≥ 22, tmux, the `claude` CLI on PATH, and an interactive subscription login.

```bash
git clone https://github.com/lperez37/ccrun && cd ccrun && bash scripts/install.sh
# or run straight from GitHub:
npx github:lperez37/ccrun
```

**Use.** Scaffold with `--engine ccrun` (or set `RALPH_ENGINE="ccrun"` in `.ralph/config.sh`). The model is a plain name like `sonnet` or `opus`. Tune the per-iteration hard cap with `RALPH_CCRUN_TIMEOUT` (seconds; ccrun kills the tmux session and returns exit 124 if a turn runs over).

```bash
bash scaffold.sh --goal "..." --template-dir ./templates --engine ccrun --model sonnet
```

**The trade-off — be honest about it.** Per iteration you only get the final assistant message in the log; there is no `--output-format stream-json` equivalent, so the per-iteration audit trail is thinner than `claude -p`. Lean on git commits and the completion promise for verification instead of the log. It has been validated driving real Ralph loops end-to-end.

The problem it solves is simple. Running an agent once works for small tasks. But for anything that takes more than a few iterations (a multi-file feature, a migration, a full project scaffold), a single session degrades. The context fills up, the model starts forgetting earlier decisions, and you end up babysitting it. The Ralph Loop fixes this by externalizing state to disk. Every iteration gets the full picture without the accumulated noise.

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
  loop.sh build -->  iterates: engine reads prompt, picks next task,
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

Each iteration gets **fresh context**. The agent reads the plan, config and learnings from disk. No context window accumulation across iterations.

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

# Review the plan, then build under supervision for long runs
./loop.sh supervise build 50
```

Or the simplest version, a promise-only loop with no plan:

```bash
bash /tmp/ralph-loop/scripts/scaffold.sh \
  --goal "Fix the flaky auth tests" \
  --template-dir /tmp/ralph-loop/templates \
  --completion-promise "ALL AUTH TESTS PASS ON 3 CONSECUTIVE RUNS"

./loop.sh supervise build 25
```

## Use as a Claude Code skill

This repo ships as a Claude Code skill. Once installed, you can ask Claude Code to set up and drive the loop for you with `/ralph-loop setup "goal"` (or just "set up a ralph loop to build X").

### Install

Symlink the skill into your Claude Code skills directory (keeps it in sync with the repo):

```bash
git clone https://github.com/lperez37/ralph-loop.git
ln -s "$(pwd)/ralph-loop/skill/ralph-loop" ~/.claude/skills/ralph-loop
```

Or copy it if you do not want a live link to the repo:

```bash
git clone https://github.com/lperez37/ralph-loop.git
cp -rL ralph-loop/skill/ralph-loop ~/.claude/skills/ralph-loop
```

The `-L` flag follows the skill's internal symlinks to `templates/` and `scripts/` so the copied directory is self-contained.

### Use

Open any project in Claude Code and say something like:

| Command | What it does |
|---------|-------------|
| `/ralph-loop setup "goal"` | Scaffold `.ralph/`, copy templates, configure, add to `.gitignore` |
| `/ralph-loop plan` | Generate `IMPLEMENTATION_PLAN.md` |
| `/ralph-loop build [N]` | Start the build loop |
| `./loop.sh supervise build [N]` | Recommended launcher for long unattended loops |
| `/ralph-loop run [plan\|build]` | Launch the loop from inside the current Claude Code session |
| `/ralph-loop status` | Show progress |
| `/ralph-loop resume` | Pick up where the last run left off |
| `/ralph-loop clean` | Remove `.ralph/` (preserves `IMPLEMENTATION_PLAN.md` and learnings) |

Claude handles scaffolding, template copying, config questions and running the loop. The full command reference lives in [`skill/ralph-loop/SKILL.md`](skill/ralph-loop/SKILL.md).

## Requirements

- One of the supported engine CLIs (pick at least one):
  - [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude` command) — the default
  - [OpenAI Codex CLI](https://developers.openai.com/codex/cli) (`codex` command) — `npm i -g @openai/codex`
  - [opencode](https://opencode.ai/docs) (`opencode` command)
  - [ccrun](https://github.com/lperez37/ccrun) (`ccrun` command) — optional, only for `--engine ccrun`; runs the loop on your Claude subscription instead of the metered programmatic pool (needs Node ≥ 22, tmux, and the `claude` CLI). See [Subscription-pool loops with ccrun](#subscription-pool-loops-with-ccrun)
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
| `--engine ENGINE` | Coding agent CLI: `claude` (default), `codex`, `opencode`, or `ccrun` |
| `--model MODEL` | Model for the engine (default: engine-specific) |
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
| `supervise build [N]` | Recommended for long unattended build loops; restarts while monitorable work remains |
| `plan [N]` | Plan mode. N = max iterations, default 5 |
| `status` | Show progress from `.ralph/state/progress.json` |
| `clean` | Remove `.ralph/` (preserves IMPLEMENTATION_PLAN.md and learnings) |
| `clean --all` | Remove everything |

| Option | Description |
|--------|-------------|
| `--delay DURATION` | Delay start (e.g. `3h`, `30m`, `1h30m`) |
| `--at TIME` | Start at specific time (e.g. `01:30`) |
| `--iteration-delay SECONDS` | Pause N seconds between iterations (default: `0`) |
| `--engine ENGINE` | Override engine (`claude` \| `codex` \| `opencode` \| `ccrun`) |
| `--model MODEL` | Override model (default: engine-specific) |
| `--prompt FILE` | Override prompt file |

```bash
./loop.sh supervise build 50          # Recommended for long unattended loops
./loop.sh build 50                    # Plain foreground build, 50 iterations
./loop.sh build --delay 3h            # Start in 3 hours
./loop.sh build --at 01:30            # Start at 1:30 AM
./loop.sh build --iteration-delay 300 # Pause 5 min between iterations
./loop.sh plan                        # Generate implementation plan
./loop.sh status                      # Check progress
```

## Project structure after setup

```
your-project/
├── loop.sh                       # Loop runner (executable)
├── IMPLEMENTATION_PLAN.md        # Task plan (at root for easy reference)
└── .ralph/                       # Hidden, gitignored
    ├── config.sh                 # Configuration (bash-sourceable)
    ├── prompt-build.md           # Build prompt (fed to the engine each iteration)
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
| `RALPH_ENGINE` | `claude` | Coding agent CLI: `claude`, `codex`, `opencode`, or `ccrun` |
| `RALPH_MODEL` | `opus` | Model for the engine. Empty = engine's own default (claude falls back to `opus`) |
| `RALPH_CODEX_SANDBOX` | (empty) | codex only. Sandbox policy (`read-only`/`workspace-write`/`danger-full-access`); empty = fully autonomous |
| `RALPH_OPENCODE_AGENT` | `build` | opencode only. Agent to run (`build` edits files, `plan` is read-only) |
| `RALPH_CCRUN_TIMEOUT` | `1500` | ccrun only. Per-iteration hard timeout (seconds); exit 124 if a turn runs over |
| `RALPH_DEFAULT_BUILD_ITERATIONS` | `25` | Default build iterations |
| `RALPH_DEFAULT_PLAN_ITERATIONS` | `5` | Default plan iterations |
| `RALPH_PROJECT_GOAL` | | One-line project goal |
| `RALPH_COMPLETION_PROMISE` | | Verification contract text |
| `RALPH_TDD` | `false` | Enable Red-Green-Refactor per task |
| `RALPH_PLAYWRIGHT` | `false` | Enable Playwright MCP browser verification |
| `RALPH_MAX_STALL` | `3` | Circuit breaker: consecutive no-change iterations |
| `RALPH_LIMIT_BACKOFF_INITIAL_SECONDS` | `300` | Initial retry delay after a Claude session/rate-limit failure. Applies to `claude -p` and `ccrun` when their failed output matches a limit message. |
| `RALPH_LIMIT_BACKOFF_MAX_SECONDS` | `5400` | Maximum capped retry delay for Claude limit backoff. Each retry doubles the base delay and adds 75-125% jitter. |
| `RALPH_ITERATION_DELAY` | `0` | Seconds to sleep between iterations. `0` disables. Override per-run with `--iteration-delay` |
| `RALPH_VIKUNJA_TASK_ID` | | Vikunja parent task ID |
| `RALPH_GH_ISSUES` | `false` | Enable GitHub Issues as task source |
| `RALPH_GH_LABEL` | `ralph-loop` | GitHub label for issue-sourced tasks |
| `RALPH_DEV_CMD` | | Dev server start command (e.g. `npm run dev`) |
| `RALPH_DEV_PORT` | | Dev server port for health checks |
| `RALPH_NTFY_TOPIC` | `ralph-loop` | ntfy notification topic |
| `RALPH_NTFY_URL` | | Full ntfy URL (overrides topic) |

## Features

### Engines (claude / codex / opencode / ccrun)

The loop drives any of four coding-agent CLIs. Choose at scaffold time:

```bash
# Default — Claude Code
bash scaffold.sh --goal "..." --template-dir ./templates

# OpenAI Codex CLI
bash scaffold.sh --goal "..." --template-dir ./templates --engine codex
# optionally pin a model: --model gpt-5.3-codex

# opencode (model uses provider/model format)
bash scaffold.sh --goal "..." --template-dir ./templates \
  --engine opencode --model anthropic/claude-sonnet-4-5
```

How each engine is invoked per iteration:

| Engine | Command | Autonomy flag |
|--------|---------|---------------|
| `claude` | `claude -p --model M --dangerously-skip-permissions --verbose` (prompt on stdin) | `--dangerously-skip-permissions` |
| `codex` | `codex exec -m M --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -` (prompt on stdin) | `--dangerously-bypass-approvals-and-sandbox` (or set `RALPH_CODEX_SANDBOX`) |
| `opencode` | `opencode run -m M --agent build --dangerously-skip-permissions "<prompt>"` (prompt as arg) | `--dangerously-skip-permissions` + the `build` agent (`RALPH_OPENCODE_AGENT`) |
| `ccrun` | `ccrun --model M --cwd "$PWD" --timeout T` (prompt on stdin) | runs the interactive REPL headlessly in tmux; per-turn cap via `RALPH_CCRUN_TIMEOUT` |

Notes:
- **Model leave-empty = engine default.** With `RALPH_MODEL=""`, codex and opencode use whatever model their own config/auth selects. `claude` falls back to `opus`.
- **Claude limit backoff.** If `claude -p` or `ccrun` exits non-zero with a Claude session/rate-limit message, the loop retries the same iteration with exponential backoff and jitter using `RALPH_LIMIT_BACKOFF_INITIAL_SECONDS` / `RALPH_LIMIT_BACKOFF_MAX_SECONDS`.
- **codex sandbox.** By default the loop runs codex fully unattended (the bypass flag), mirroring Claude's `--dangerously-skip-permissions`. Set `RALPH_CODEX_SANDBOX=workspace-write` (or `danger-full-access`) to run sandboxed instead.
- **MCP-backed extras.** Vikunja and Playwright steps are wired for Claude Code's MCP. codex and opencode support MCP too, but you must configure the equivalent servers in their own config; otherwise those optional steps are simply skipped.
- **`AGENTS.md`** is the shared backpressure file — all three CLIs read it natively, so the same project works across engines.

You can also override the engine for a single run without re-scaffolding:

```bash
./loop.sh build --engine codex
./loop.sh build --engine opencode --model anthropic/claude-sonnet-4-5
```

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

### Per-iteration delay

Pause between iterations to throttle long-running loops — useful when running for many hours and you want to spread Claude subscription token usage rather than burning through it in a burst.

```bash
./loop.sh build --iteration-delay 300   # Sleep 5 min between iterations
```

Or set `RALPH_ITERATION_DELAY` in `.ralph/config.sh` to make it the default for the project. `0` (default) disables the pause. The delay is skipped after the final iteration and after any completion/circuit-breaker exit, so it never adds idle time at the end of a run.

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

## License

MIT
