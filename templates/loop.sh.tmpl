#!/usr/bin/env bash
# Ralph Wiggum Loop — Supervised autonomous development
# Usage: ./loop.sh [plan|build] [max_iterations] [--delay DURATION] [--at TIME]
# Examples:
#   ./loop.sh                    # Build mode, default iterations
#   ./loop.sh plan               # Plan mode
#   ./loop.sh build 50           # Build mode, 50 iterations
#   ./loop.sh build --delay 3h   # Build mode, start in 3 hours
#   ./loop.sh build --at 01:30   # Build mode, start at 01:30

set -euo pipefail

# --- Load config (new location, fallback to legacy) ---
if [ -f .ralph/config.sh ]; then
    source .ralph/config.sh
elif [ -f .ralph-config ]; then
    source .ralph-config
fi

# --- Portable ISO timestamp (GNU date -Iseconds fallback) ---
iso_timestamp() {
    date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'
}

# --- Defaults ---
DEFAULT_BUILD_ITERATIONS="${RALPH_DEFAULT_BUILD_ITERATIONS:-25}"
DEFAULT_PLAN_ITERATIONS="${RALPH_DEFAULT_PLAN_ITERATIONS:-5}"
MODEL="${RALPH_MODEL:-opus}"
LOG_DIR=".ralph/logs"
STATE_DIR=".ralph/state"
DELAY=""
START_AT=""
PROMPT_FILE=""

# --- Help ---
show_help() {
    cat <<'HELP'
Ralph Wiggum Loop — Supervised autonomous development

USAGE
  ./loop.sh [command] [options]

COMMANDS
  build [N]           Build mode (default). N = max iterations (default: 25)
  plan [N]            Plan mode. N = max iterations (default: 5)
  status              Show progress from .ralph/state/progress.json
  clean               Remove .ralph/ directory (keep IMPLEMENTATION_PLAN.md)
  clean --all         Remove .ralph/ AND IMPLEMENTATION_PLAN.md
  help, --help, -h    Show this help

OPTIONS
  --delay DURATION    Delay start (e.g., 3h, 30m, 1h30m)
  --at TIME           Start at specific time (e.g., 01:30, 23:00)
  --model MODEL       Override model (default: opus)
  --prompt FILE       Override prompt file

EXAMPLES
  ./loop.sh                       Build mode, default iterations
  ./loop.sh plan                  Generate implementation plan
  ./loop.sh build 50              Build with 50 iterations
  ./loop.sh build --delay 3h      Start building in 3 hours
  ./loop.sh build --at 01:30      Start building at 01:30
  ./loop.sh status                Check loop progress
  ./loop.sh clean                 Remove .ralph/ artifacts

LIFECYCLE (via Claude Code skill)
  /ralph-loop setup "goal"        Scaffold project for Ralph loop
  /ralph-loop run [build|plan]    Run loop from within Claude session
  /ralph-loop resume              Pick up where last loop left off

CONFIG
  .ralph/config.sh                Loop settings (model, iterations, notifications)
  .ralph/prompt-build.md          Build mode prompt
  .ralph/prompt-plan.md           Plan mode prompt
HELP
    exit 0
}

# --- Parse arguments ---
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        help|--help|-h) show_help ;;
        --delay)  [ $# -lt 2 ] && echo "ERROR: --delay requires a value" && exit 1; DELAY="$2";       shift 2 ;;
        --at)     [ $# -lt 2 ] && echo "ERROR: --at requires a value" && exit 1;    START_AT="$2";    shift 2 ;;
        --model)  [ $# -lt 2 ] && echo "ERROR: --model requires a value" && exit 1; MODEL="$2";      shift 2 ;;
        --prompt) [ $# -lt 2 ] && echo "ERROR: --prompt requires a value" && exit 1; PROMPT_FILE="$2"; shift 2 ;;
        *)        POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]:-}"

# --- Status command ---
if [ "${1:-}" = "status" ]; then
    if [ -f "$STATE_DIR/progress.json" ]; then
        echo "=== Ralph Loop Status ==="
        python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f\"Status:     {d['status']}\")
print(f\"Iteration:  {d['iteration']}/{d['max_iterations']}\")
print(f\"Tasks:      {d['tasks_done']}/{d['tasks_total']} done, {d['tasks_pending']} pending\")
print(f\"Stalls:     {d['stall_count']}\")
print(f\"Branch:     {d['branch']}\")
print(f\"Last SHA:   {d['last_sha']}\")
print(f\"Elapsed:    {d['elapsed']}\")
print(f\"Updated:    {d['updated_at']}\")
" < "$STATE_DIR/progress.json" 2>/dev/null || cat "$STATE_DIR/progress.json"
        echo "========================="
    else
        echo "No progress state found. Run ./loop.sh build first."
        if [ -f IMPLEMENTATION_PLAN.md ]; then
            DONE=$(grep -cE '(\- \[x\]|\*\*Status:\*\* \[x\])' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
            PENDING=$(grep -cE '(\- \[ \]|\*\*Status:\*\* \[ \])' IMPLEMENTATION_PLAN.md 2>/dev/null || echo 0)
            echo "IMPLEMENTATION_PLAN.md: $DONE done, $PENDING pending"
        fi
    fi
    exit 0
fi

# --- Clean command ---
if [ "${1:-}" = "clean" ]; then
    if [ -d "$STATE_DIR/loop.lock" ]; then
        LOCK_PID=$(cat "$STATE_DIR/loop.lock/pid" 2>/dev/null || echo "")
        if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
            echo "WARNING: A Ralph loop is currently running (PID $LOCK_PID)."
            echo "         Cleaning now will break the running loop."
            echo "         Kill it first: kill $LOCK_PID"
            exit 1
        fi
    fi
    if [ "${2:-}" = "--all" ]; then
        rm -rf .ralph/ IMPLEMENTATION_PLAN.md
        echo "Removed .ralph/, IMPLEMENTATION_PLAN.md, and learnings."
    else
        # Preserve learnings across clean cycles
        LEARNINGS_BAK=""
        if [ -f .ralph/learnings.md ]; then
            LEARNINGS_BAK=$(mktemp)
            cp .ralph/learnings.md "$LEARNINGS_BAK"
        fi
        rm -rf .ralph/
        if [ -n "$LEARNINGS_BAK" ]; then
            mkdir -p .ralph
            mv "$LEARNINGS_BAK" .ralph/learnings.md
            echo "Removed .ralph/ directory. IMPLEMENTATION_PLAN.md and learnings.md preserved."
        else
            echo "Removed .ralph/ directory. IMPLEMENTATION_PLAN.md preserved."
        fi
    fi
    exit 0
fi

# --- Mode selection ---
if [ "${1:-}" = "plan" ]; then
    MODE="plan"
    PROMPT_FILE="${PROMPT_FILE:-.ralph/prompt-plan.md}"
    MAX_ITERATIONS=${2:-$DEFAULT_PLAN_ITERATIONS}
elif [ "${1:-}" = "build" ]; then
    MODE="build"
    PROMPT_FILE="${PROMPT_FILE:-.ralph/prompt-build.md}"
    MAX_ITERATIONS=${2:-$DEFAULT_BUILD_ITERATIONS}
elif [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    MODE="build"
    PROMPT_FILE="${PROMPT_FILE:-.ralph/prompt-build.md}"
    MAX_ITERATIONS=$1
else
    MODE="build"
    PROMPT_FILE="${PROMPT_FILE:-.ralph/prompt-build.md}"
    MAX_ITERATIONS=$DEFAULT_BUILD_ITERATIONS
fi

# --- Fallback to legacy prompt locations ---
if [ ! -f "$PROMPT_FILE" ]; then
    if [ "$MODE" = "plan" ] && [ -f "PROMPT_plan.md" ]; then
        PROMPT_FILE="PROMPT_plan.md"
    elif [ "$MODE" = "build" ] && [ -f "PROMPT_build.md" ]; then
        PROMPT_FILE="PROMPT_build.md"
    fi
fi

# --- Safety checks ---
if [ ! -f "$PROMPT_FILE" ]; then
    echo "ERROR: $PROMPT_FILE not found. Run scaffold.sh first (see README)."
    exit 1
fi

if [ ! -f "AGENTS.md" ] && [ "$MODE" = "build" ]; then
    echo "WARNING: AGENTS.md not found. Ralph will have no backpressure commands."
fi

# --- Handle delayed start ---
parse_duration() {
    local input="$1"
    local total_seconds=0
    [[ "$input" =~ ([0-9]+)h ]] && total_seconds=$((total_seconds + ${BASH_REMATCH[1]} * 3600))
    [[ "$input" =~ ([0-9]+)m ]] && total_seconds=$((total_seconds + ${BASH_REMATCH[1]} * 60))
    [[ "$input" =~ ([0-9]+)s ]] && total_seconds=$((total_seconds + ${BASH_REMATCH[1]}))
    [[ "$input" =~ ^[0-9]+$ ]]  && total_seconds=$((input * 3600))
    echo "$total_seconds"
}

# GNU date check (--delay and --at need date -d which is GNU-only)
if [ -n "$START_AT" ] || [ -n "$DELAY" ]; then
    if ! date -d "1 second" +%s &>/dev/null; then
        echo "ERROR: --delay and --at require GNU date (coreutils)."
        echo "       On macOS: brew install coreutils && export PATH=\"\$(brew --prefix coreutils)/libexec/gnubin:\$PATH\""
        exit 1
    fi
fi

if [ -n "$START_AT" ]; then
    NOW_EPOCH=$(date +%s)
    TARGET_EPOCH=$(date -d "$START_AT" +%s 2>/dev/null || date -d "today $START_AT" +%s 2>/dev/null)
    if [ "$TARGET_EPOCH" -le "$NOW_EPOCH" ]; then
        TARGET_EPOCH=$(date -d "tomorrow $START_AT" +%s 2>/dev/null || echo "$TARGET_EPOCH")
    fi
    SLEEP_SECONDS=$((TARGET_EPOCH - NOW_EPOCH))
    if [ "$SLEEP_SECONDS" -gt 0 ]; then
        WAKE_TIME=$(date -d "@$TARGET_EPOCH" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
        echo "  zzZ  Ralph is napping until $WAKE_TIME ($SLEEP_SECONDS seconds)"
        echo "       Press Ctrl+C to cancel"
        sleep "$SLEEP_SECONDS"
    fi
elif [ -n "$DELAY" ]; then
    SLEEP_SECONDS=$(parse_duration "$DELAY")
    if [ "$SLEEP_SECONDS" -gt 0 ]; then
        WAKE_TIME=$(date -d "+${SLEEP_SECONDS} seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
        echo "  zzZ  Ralph is napping for $DELAY ($SLEEP_SECONDS seconds)"
        echo "       Will start at: $WAKE_TIME"
        echo "       Press Ctrl+C to cancel"
        sleep "$SLEEP_SECONDS"
    fi
fi

# --- Dev server management (optional) ---
ensure_dev_server() {
    local dev_cmd="${RALPH_DEV_CMD:-}"
    local dev_port="${RALPH_DEV_PORT:-}"
    [ -z "$dev_cmd" ] && return 0
    [ -z "$dev_port" ] && return 0

    # Fast path: configured port responds. Nothing to do.
    if curl -s "http://localhost:$dev_port" > /dev/null 2>&1; then
        return 0
    fi

    # Port silent but we previously spawned a dev-server and it's still alive.
    # Almost always means the server auto-bumped to a different port because
    # $dev_port was taken, or $dev_port is misconfigured. Do NOT spawn another.
    if [ -n "${DEV_PID:-}" ] && kill -0 "$DEV_PID" 2>/dev/null; then
        echo "[Ralph] WARNING: DEV_PID $DEV_PID is alive but port $dev_port is not responding."
        echo "[Ralph]          Does RALPH_DEV_PORT match the port your dev server actually binds?"
        echo "[Ralph]          Not spawning a second instance. Check $LOG_DIR/dev-server.log"
        return 0
    fi

    # Port silent, no tracked PID, but a process matching $dev_cmd exists.
    # Likely started manually or in a previous run. Don't stack a duplicate.
    if pgrep -f -- "$dev_cmd" > /dev/null 2>&1; then
        echo "[Ralph] WARNING: A process matching '$dev_cmd' is already running,"
        echo "[Ralph]          but port $dev_port is not responding. Not re-spawning."
        echo "[Ralph]          Check RALPH_DEV_PORT or kill the stray process."
        return 0
    fi

    # Genuinely no dev server running. Start one.
    echo "[Ralph] Starting dev server: $dev_cmd"
    bash -c "$dev_cmd" &>"$LOG_DIR/dev-server.log" &
    DEV_PID=$!
    echo "[Ralph] Dev server PID: $DEV_PID"
    sleep 5
    if ! curl -s "http://localhost:$dev_port" > /dev/null 2>&1; then
        echo "[Ralph] WARNING: Dev server may not have started. Check $LOG_DIR/dev-server.log"
    fi
}

# --- Notification helper ---
NTFY_URL="${RALPH_NTFY_URL:-https://ntfy.sh/${RALPH_NTFY_TOPIC:-ralph-loop}}"

notify() {
    local title="${1//$'\n'/ }"
    local message="${2//$'\n'/ }"
    local tags="${3:-robot}"

    local cet_hour
    cet_hour=$(TZ="Europe/Amsterdam" date +%H)
    local priority="high"
    if [ "$cet_hour" -ge 0 ] && [ "$cet_hour" -lt 7 ]; then
        priority="min"
    fi

    curl -s -o /dev/null \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -H "Tags: $tags" \
        -d "$message" \
        "$NTFY_URL" 2>/dev/null || true
}

elapsed() {
    local secs=$(( $(date +%s) - START_EPOCH ))
    local h=$((secs / 3600)) m=$(((secs % 3600) / 60))
    if [ "$h" -gt 0 ]; then echo "${h}h ${m}m"
    else echo "${m}m"; fi
}

# --- Count tasks in IMPLEMENTATION_PLAN.md ---
# Matches both "- [x] Title" checkboxes and "**Status:** [x]" field format
count_tasks() {
    local status="$1"
    if [ ! -f IMPLEMENTATION_PLAN.md ]; then echo "0"; return; fi
    case "$status" in
        done)    grep -cE '(\- \[x\]|\*\*Status:\*\* \[x\])' IMPLEMENTATION_PLAN.md 2>/dev/null || echo "0" ;;
        pending) grep -cE '(\- \[ \]|\*\*Status:\*\* \[ \])' IMPLEMENTATION_PLAN.md 2>/dev/null || echo "0" ;;
        total)   grep -cE '(\- \[.\]|\*\*Status:\*\* \[.\])' IMPLEMENTATION_PLAN.md 2>/dev/null || echo "0" ;;
    esac
}

# --- JSON helper ---
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

# --- Write progress state ---
write_progress() {
    mkdir -p "$STATE_DIR"
    local tasks_done tasks_pending tasks_total
    tasks_done=$(count_tasks done)
    tasks_pending=$(count_tasks pending)
    tasks_total=$(count_tasks total)

    local branch_safe mode_safe model_safe started_safe
    branch_safe=$(json_escape "$CURRENT_BRANCH")
    mode_safe=$(json_escape "$MODE")
    model_safe=$(json_escape "$MODEL")
    started_safe=$(json_escape "$STARTED_AT")

    cat > "$STATE_DIR/progress.json" <<PROGRESS_EOF
{
  "iteration": $ITERATION,
  "max_iterations": $MAX_ITERATIONS,
  "mode": "$mode_safe",
  "model": "$model_safe",
  "branch": "$branch_safe",
  "last_sha": "$(git rev-parse --short HEAD 2>/dev/null || echo 'none')",
  "stall_count": $CONSECUTIVE_NO_CHANGES,
  "tasks_done": $tasks_done,
  "tasks_pending": $tasks_pending,
  "tasks_total": $tasks_total,
  "started_at": "$started_safe",
  "updated_at": "$(iso_timestamp)",
  "elapsed": "$(elapsed)",
  "status": "running"
}
PROGRESS_EOF
}

# --- Lock (atomic mkdir to prevent concurrent loops) ---
LOCK_DIR="$STATE_DIR/loop.lock"
mkdir -p "$LOG_DIR" "$STATE_DIR"
if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"
else
    LOCK_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "unknown")
    if kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "ERROR: Another Ralph loop is already running (PID $LOCK_PID)"
        echo "If this is stale, remove $LOCK_DIR manually."
        exit 1
    else
        # Stale lock from a crashed run, take over
        echo $$ > "$LOCK_DIR/pid"
    fi
fi

# --- Setup logging ---
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/ralph_${MODE}_${TIMESTAMP}.log"
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
STARTED_AT=$(iso_timestamp)

echo ""
echo "  ralph ~ $MODE"
echo "  ─────────────────"
echo "  model:      $MODEL"
echo "  iterations: $MAX_ITERATIONS"
echo "  branch:     $CURRENT_BRANCH"
echo "  prompt:     $PROMPT_FILE"
echo "  log:        $LOG_FILE"
echo "  started:    $(date '+%Y-%m-%d %H:%M:%S')"
PROMISE_CFG="${RALPH_COMPLETION_PROMISE:-}"
[ -n "$PROMISE_CFG" ] && echo "  promise:    $PROMISE_CFG"
[ "${RALPH_TDD:-false}" = "true" ] && echo "  tdd:        on"
[ -n "${RALPH_VIKUNJA_TASK_ID:-}" ] && echo "  vikunja:    #$RALPH_VIKUNJA_TASK_ID"
echo ""

START_EPOCH=$(date +%s)

# --- Signal handling ---
cleanup() {
    echo ""
    echo "[Ralph] Interrupted. Writing final state..."
    write_progress
    perl -pi -e 's/"status": "running"/"status": "interrupted"/' "$STATE_DIR/progress.json" 2>/dev/null || true
    notify "Ralph interrupted ($(elapsed))" "Stopped at iteration ${ITERATION:-0} on $CURRENT_BRANCH" "stop_sign"
    rm -rf "$LOCK_DIR"
    [ -n "${DEV_PID:-}" ] && kill "$DEV_PID" 2>/dev/null || true
    exit 1
}
trap cleanup SIGINT SIGTERM
trap 'rm -rf "$LOCK_DIR"' EXIT

# Start dev server if configured
ensure_dev_server

notify "Ralph started" "$MODE mode on $CURRENT_BRANCH. $MAX_ITERATIONS iterations, model: $MODEL" "rocket"

# --- Main loop ---
ITERATION=0
CONSECUTIVE_NO_CHANGES=0
MAX_NO_CHANGE_ITERATIONS="${RALPH_MAX_STALL:-3}"

while true; do
    if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
        echo "[Ralph] Reached max iterations: $MAX_ITERATIONS"
        notify "Ralph done ($(elapsed))" "Reached max $MAX_ITERATIONS iterations on $CURRENT_BRANCH in $(elapsed)" "checkered_flag"
        break
    fi

    ITERATION=$((ITERATION + 1))
    echo ""
    echo "--- Iteration $ITERATION/$MAX_ITERATIONS [$MODE] $(date '+%H:%M:%S') ---"

    # Ensure dev server is alive
    ensure_dev_server

    # Track state for circuit breaker
    BEFORE_COMMITS=$(git rev-parse HEAD 2>/dev/null || echo "none")

    # Run Claude with fresh context
    LOG_OFFSET=$({ wc -c < "$LOG_FILE"; } 2>/dev/null || echo 0)

    set +e
    { echo "Ralph iteration $ITERATION/$MAX_ITERATIONS on branch $CURRENT_BRANCH"; cat "$PROMPT_FILE"; } | \
        claude -p \
        --model "$MODEL" \
        --dangerously-skip-permissions \
        --verbose \
        2>&1 | tee -a "$LOG_FILE"
    CLAUDE_EXIT=${PIPESTATUS[1]:-$?}
    set -e

    if [ "${CLAUDE_EXIT:-0}" -ne 0 ]; then
        echo "[Ralph] WARNING: Claude exited with code $CLAUDE_EXIT. Continuing loop..."
    fi

    # Push changes
    git push origin "$CURRENT_BRANCH" 2>/dev/null || \
        git push -u origin "$CURRENT_BRANCH" 2>/dev/null || true

    # Circuit breaker: detect no-progress loops
    AFTER_COMMITS=$(git rev-parse HEAD 2>/dev/null || echo "none")

    if [ "$BEFORE_COMMITS" = "$AFTER_COMMITS" ]; then
        CONSECUTIVE_NO_CHANGES=$((CONSECUTIVE_NO_CHANGES + 1))
        echo "[Ralph] WARNING: No changes detected ($CONSECUTIVE_NO_CHANGES consecutive)"
        if [ $CONSECUTIVE_NO_CHANGES -ge $MAX_NO_CHANGE_ITERATIONS ]; then
            echo "[Ralph] CIRCUIT BREAKER: $MAX_NO_CHANGE_ITERATIONS iterations with no changes. Stopping."
            notify "Ralph stuck ($(elapsed))" "Circuit breaker after $ITERATION iterations on $CURRENT_BRANCH -- no changes detected" "warning"
            break
        fi
    else
        CONSECUTIVE_NO_CHANGES=0
    fi

    # Write progress
    write_progress

    # Check for completion signals (only in current iteration's output)

    # Check for <promise> tag (completion promise verification)
    COMPLETION_PROMISE="${RALPH_COMPLETION_PROMISE:-}"
    if [ -n "$COMPLETION_PROMISE" ]; then
        PROMISE_TEXT=$(tail -c +"$((LOG_OFFSET + 1))" "$LOG_FILE" 2>/dev/null | perl -0777 -ne \
            'if (/<promise>(.*?)<\/promise>/s) { $_ = $1; s/^\s+|\s+$//g; s/\s+/ /g; print }' \
            2>/dev/null || echo "")
        if [ -n "$PROMISE_TEXT" ]; then
            if [ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]; then
                echo "[Ralph] Promise fulfilled: $COMPLETION_PROMISE"
                notify "Ralph promise fulfilled ($(elapsed))" "Promise: $COMPLETION_PROMISE — after $ITERATION iterations on $CURRENT_BRANCH in $(elapsed)" "white_check_mark"
                break
            else
                echo "[Ralph] Promise mismatch. Expected: '$COMPLETION_PROMISE', got: '$PROMISE_TEXT'"
            fi
        fi
    fi

    # Check for RALPH_COMPLETE (task-based completion)
    if tail -c +"$((LOG_OFFSET + 1))" "$LOG_FILE" 2>/dev/null | grep -q "RALPH_COMPLETE"; then
        echo "[Ralph] Completion signal detected. All tasks done!"
        notify "Ralph complete ($(elapsed))" "All tasks done after $ITERATION iterations on $CURRENT_BRANCH in $(elapsed)" "white_check_mark"
        break
    fi

    echo "[Ralph] Iteration $ITERATION complete. Restarting with fresh context..."
done

# --- Write final progress ---
ITERATION=${ITERATION:-0}
write_progress
# Update status to finished
perl -pi -e 's/"status": "running"/"status": "finished"/' "$STATE_DIR/progress.json" 2>/dev/null || true
rm -rf "$LOCK_DIR"

# --- Post-run summary ---
echo ""
echo "  ralph ~ done"
echo "  ─────────────────"
echo "  iterations: $ITERATION"
echo "  elapsed:    $(elapsed)"
echo "  tasks:      $(count_tasks done)/$(count_tasks total) complete, $(count_tasks pending) remaining"
echo "  log:        $LOG_FILE"
echo ""

echo ""
echo "--- Git Summary ---"
[ "$ITERATION" -gt 0 ] && git log --oneline -"$ITERATION" 2>/dev/null || true
echo "-------------------"

# GitHub issues summary (if configured)
if [ "${RALPH_GH_ISSUES:-false}" = "true" ]; then
    echo ""
    echo "--- GitHub Issues ---"
    gh issue list --label "${RALPH_GH_LABEL:-ralph-loop}" --state all \
        --json number,title,state \
        --jq '.[] | "\(.state)\t#\(.number)\t\(.title)"' 2>/dev/null || true
    echo "---------------------"
fi

# Vikunja task summary (if configured)
if [ -n "${RALPH_VIKUNJA_TASK_ID:-}" ]; then
    echo ""
    echo "--- Vikunja Task #$RALPH_VIKUNJA_TASK_ID ---"
    echo "Subtask completion synced during build iterations."
    echo "Check full status: /vikunja get $RALPH_VIKUNJA_TASK_ID"
    echo "-------------------------------"
fi
