# Ralph Loop Reference

## .ralph/ Directory Structure

```
.ralph/
├── config.sh                 # Bash-sourceable configuration
├── prompt-build.md           # Build mode prompt (fed to the engine each iteration)
├── prompt-plan.md            # Plan mode prompt
├── learnings.md              # Persistent inter-iteration memory (append-only)
├── logs/
│   ├── ralph_build_*.log     # Full session logs (stdout + stderr)
│   └── session-*.log         # In-session mode logs
└── state/
    └── progress.json         # Machine-readable loop state
```

## progress.json Format

```json
{
  "iteration": 5,
  "max_iterations": 25,
  "mode": "build",
  "engine": "claude",
  "model": "opus",
  "branch": "feat/my-feature",
  "last_sha": "abc1234",
  "stall_count": 0,
  "tasks_done": 3,
  "tasks_pending": 7,
  "tasks_total": 10,
  "started_at": "2026-04-06T14:30:00+02:00",
  "updated_at": "2026-04-06T15:45:00+02:00",
  "elapsed": "1h 15m",
  "status": "running"
}
```

Status values: `running`, `finished`.

## IMPLEMENTATION_PLAN.md Task Format

```markdown
### Task N: [Title]
- **Files:** src/foo.ts, src/bar.ts
- **Action:** What to do (specific, actionable)
- **Verify:** `npm run build && npm test`
- **Parallel:** true
- **Status:** [ ] Pending
```

- `Files:` lists all files the task will touch. Used for parallel detection.
- `Parallel: true` means this task has no file overlap with adjacent tasks.
- `Status: [ ] Pending` / `[x] Complete` — checked by loop for progress tracking.
- Completed tasks are moved to the `## Completed` section.

## Troubleshooting

### Circuit breaker triggered too early
The loop stops after `RALPH_MAX_STALL` (default 3) consecutive iterations with no git commits. Common causes:
- Claude is reading/planning but not committing yet. Increase `RALPH_MAX_STALL` to 5.
- The prompt doesn't instruct Claude to commit. Check `.ralph/prompt-build.md`.
- Build is failing silently. Check the latest log in `.ralph/logs/`.

### Dev server won't start
If `RALPH_DEV_CMD` is set but the server fails to start:
- Check `/tmp/ralph-dev-server.log` for errors.
- Ensure the port isn't already in use: `lsof -i :PORT`.
- Try starting the server manually first.

### Notifications not arriving
- Verify ntfy URL: `curl -d "test" https://ntfy.sh/TOPIC`
- Check if `RALPH_NTFY_URL` or `RALPH_NTFY_TOPIC` is set correctly in config.
- During quiet hours (00:00-07:00 local time), notifications use minimum priority.

### RALPH_COMPLETE not detected
The loop greps the log file for the literal string `RALPH_COMPLETE`. Ensure:
- The build prompt ends with: `After ALL tasks complete, output: RALPH_COMPLETE`
- Claude is actually outputting the string (check the latest log).
- The string appears on its own (not inside a code block or quoted).

### Promise not matching
The `<promise>` tag extraction uses literal string comparison. Common issues:
- Whitespace differences: the extraction trims leading/trailing whitespace and collapses internal whitespace
- Case sensitivity: comparison is case-sensitive — `ALL TESTS PASS` ≠ `All Tests Pass`
- Extra text: `<promise>ALL TESTS PASS AND MORE</promise>` won't match `ALL TESTS PASS`
- Check the log for `[Ralph] Promise mismatch` lines to see what was extracted vs expected

### Permission errors
Each engine runs fully unattended by default:
- `claude` → `--dangerously-skip-permissions`
- `codex` → `--dangerously-bypass-approvals-and-sandbox` (override with `RALPH_CODEX_SANDBOX`)
- `opencode` → `--dangerously-skip-permissions` + the `build` agent (override with `RALPH_OPENCODE_AGENT`)

If the engine needs elevated permissions:
- Ensure the user running loop.sh has appropriate file/git permissions.
- For GitHub operations, ensure `gh auth status` shows authenticated.

### Wrong engine / model errors
- `'codex' CLI not found` / `'opencode' CLI not found`: install the engine, or switch with `--engine claude`.
- opencode model errors: opencode needs `provider/model` (e.g. `anthropic/claude-sonnet-4-5`), not a bare name.
- codex authentication: codex uses its own auth (`codex login` or `OPENAI_API_KEY`); the loop does not manage it.
- Leave `RALPH_MODEL=""` to let codex/opencode pick their own configured default model.

## Advanced: Parallel Execution

Parallel execution is a future enhancement. The current templates support it at the prompt level (Claude uses parallel subagents within each iteration). For multi-process parallelism via tmux:

### Concept (not yet in loop.sh.tmpl)
```bash
# Detect parallel candidates from IMPLEMENTATION_PLAN.md
# Tasks with non-overlapping Files: fields and Parallel: true
# Launch up to 3 claude -p instances in tmux panes
# Each gets its own log file
# Wait for all to complete, then check git status
```

### Why subagent parallelism is preferred
Within a single Claude session, the model can launch multiple subagents that work in parallel on independent files. This is:
- Simpler than managing multiple processes
- No merge conflicts (single git working tree)
- Already supported by the prompt templates ("Maximize parallelism with subagents")

Multi-process parallelism (tmux/worktrees) is useful when tasks are large enough to warrant separate full sessions.

## TDD Mode

When `RALPH_TDD=true` in config, step 2 of the build prompt changes from "implement the task" to the Red-Green-Refactor cycle:

```
2a. RED — Write failing test → run tests → verify FAIL
2b. GREEN — Write minimum implementation → run tests → verify PASS
2c. IMPROVE — Refactor, add edge case tests → tests stay green → target 80%+ coverage
```

TDD mode is off by default. It adds overhead per task (more iterations consumed) but produces higher quality code with comprehensive test coverage.

### Edge cases Claude must test (when TDD is on)

| Category | Examples |
|---|---|
| Null/undefined | Missing params, null fields |
| Empty inputs | Empty string, empty array, `{}` |
| Invalid types | String where number expected |
| Boundaries | 0, -1, MAX_INT, empty file |
| Error paths | Network failure, DB error, timeout |
| Special chars | Unicode, emojis, SQL injection chars |

### TDD + learnings interaction

In TDD mode, Signs become especially valuable — they capture testing mistakes:
```
- **Sign:** Always mock external APIs in unit tests — discovered iteration 2 (test hit real API and failed in CI)
- **Sign:** Test error paths, not just happy path — discovered iteration 4 (null input crashed handler)
```

## Completion Promises

### Architecture

The promise is orthogonal to the task source. It layers on top:

```
Task Source (what to do)           ×  Completion Signal (how to verify)
├── IMPLEMENTATION_PLAN.md              ├── RALPH_COMPLETE (task checkboxes)
├── GitHub Issues                       └── <promise> (actual verification)
└── None (promise-only loop)
```

Any combination works. Promise-only loops (no task source) are the simplest mode.

### How loop.sh detects promises

```bash
# Extract <promise> content using perl (handles multiline)
PROMISE_TEXT=$(echo "$ITER_OUTPUT" | perl -0777 -pe \
  's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g')

# Literal comparison against RALPH_COMPLETION_PROMISE
if [ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]; then
    # Exit loop — promise fulfilled
fi
```

- Checked BEFORE `RALPH_COMPLETE` each iteration
- Perl regex handles multiline output and trims whitespace
- Comparison is literal and case-sensitive
- If no `RALPH_COMPLETION_PROMISE` is set, promise checking is skipped entirely

### Promise anti-pattern: false promises

The build prompt explicitly tells Claude:
> "Do NOT output a false promise to escape the loop, even if you think you are stuck."

If Claude is stuck, it should document the issue in learnings.md and Known Issues, NOT output a false promise. The circuit breaker handles genuinely stuck loops.

## Learnings Document

### Format

```markdown
# Learnings

Persistent memory across Ralph loop iterations. Append-only — never delete entries.

## Codebase Patterns

- All API routes use the `withAuth` middleware wrapper
- Pagination helper exists at src/lib/paginate.ts
- CSS modules use camelCase, not kebab-case

## Signs

- **Sign:** Always run typecheck before commit — discovered iteration 3 (committed with type errors)
- **Sign:** Use existing pagination helper — discovered iteration 4 (created duplicate logic)
- **Sign:** Check for existing imports before adding — discovered iteration 5 (duplicate import broke build)
```

### Lifecycle

| When | Action |
|------|--------|
| Scaffold | Created from template (empty sections) |
| Iteration start (step 0b) | Read by Claude for context |
| After each task (step 99) | Claude appends patterns and signs |
| Loop end | Preserved (survives `/ralph-loop clean`) |
| `/ralph-loop clean --all` | Deleted with everything else |

### Signs vs AGENTS.md Operational Notes

Both store learnings, but serve different purposes:
- **Signs** (learnings.md): Discovered during THIS loop run. Specific, tactical, append-only.
- **Operational Notes** (AGENTS.md): Curated project knowledge. Concise, maintained, kept under 60 lines.

Signs that prove universally useful should be promoted to AGENTS.md Operational Notes.

## Task Sources

| Source | Config | Plan source | Completion sync |
|--------|--------|-------------|-----------------|
| Standalone | (default) | Claude explores codebase | IMPLEMENTATION_PLAN.md only |
| GitHub Issues | `RALPH_GH_ISSUES=true` | Claude explores + reads issues | IMPLEMENTATION_PLAN.md + optional issue close |

## Environment Variables (CLI overrides)

These can be passed directly to loop.sh:

```bash
./loop.sh build --engine codex      # Override engine (claude|codex|opencode)
./loop.sh build --model sonnet      # Override model
./loop.sh build --prompt custom.md  # Use custom prompt file
./loop.sh build --delay 2h          # Delayed start
./loop.sh build --at 03:00          # Start at specific time
```
