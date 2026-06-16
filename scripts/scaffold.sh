#!/usr/bin/env bash
# Ralph Loop Scaffolder
# Creates .ralph/ directory structure and copies templates into the current project.
# Usage: scaffold.sh [--goal "project goal"] [--template-dir /path/to/templates]

set -euo pipefail

GOAL=""
TEMPLATE_DIR=""
VIKUNJA_TASK_ID=""
COMPLETION_PROMISE=""
TDD="false"
PLAYWRIGHT="false"
ENGINE="claude"
MODEL=""
WARNINGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --goal)                 [ $# -lt 2 ] && echo "ERROR: --goal requires a value" && exit 1;               GOAL="$2";                 shift 2 ;;
        --template-dir)         [ $# -lt 2 ] && echo "ERROR: --template-dir requires a value" && exit 1;       TEMPLATE_DIR="$2";         shift 2 ;;
        --engine)               [ $# -lt 2 ] && echo "ERROR: --engine requires a value" && exit 1;             ENGINE="$2";               shift 2 ;;
        --model)                [ $# -lt 2 ] && echo "ERROR: --model requires a value" && exit 1;              MODEL="$2";                shift 2 ;;
        --vikunja-task-id)      [ $# -lt 2 ] && echo "ERROR: --vikunja-task-id requires a value" && exit 1;    VIKUNJA_TASK_ID="$2";      shift 2 ;;
        --completion-promise)   [ $# -lt 2 ] && echo "ERROR: --completion-promise requires a value" && exit 1; COMPLETION_PROMISE="$2";   shift 2 ;;
        --tdd)                  TDD="true";                shift ;;
        --playwright)           PLAYWRIGHT="true";         shift ;;
        -h|--help)
            echo "Usage: scaffold.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --goal TEXT               Project goal (required)"
            echo "  --template-dir PATH       Template directory"
            echo "  --engine ENGINE           Coding agent CLI: claude | codex | opencode | ccrun (default: claude)"
            echo "  --model MODEL             Model for the engine (default: engine-specific)"
            echo "  --vikunja-task-id ID      Vikunja parent task ID"
            echo "  --completion-promise TEXT  Completion promise"
            echo "  --tdd                     Enable TDD mode"
            echo "  --playwright              Enable Playwright browser verification"
            echo "  -h, --help                Show this help"
            exit 0
            ;;
        *)
            echo "WARNING: Unknown argument: $1 (if this is a value for a preceding flag, check the flag name)"
            WARNINGS+=("Unknown argument '$1' was ignored")
            shift
            ;;
    esac
done

# --- Validate engine ---
case "$ENGINE" in
    claude|codex|opencode|ccrun) ;;
    *) echo "ERROR: Unknown --engine '$ENGINE' (expected: claude, codex, opencode, ccrun)"; exit 1 ;;
esac

# Resolve template directory (default: sibling templates/ dir)
if [ -z "$TEMPLATE_DIR" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TEMPLATE_DIR="$SCRIPT_DIR/../templates"
fi

if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "ERROR: Template directory not found: $TEMPLATE_DIR"
    exit 1
fi

# --- Banner ---
echo ""
echo "  ralph ~ scaffold"
echo "  ─────────────────"
echo ""
echo "  Project:    $(basename "$(pwd)")"
echo "  Templates:  $TEMPLATE_DIR"
echo ""

# --- Validation ---
if [ -z "$GOAL" ]; then
    echo "WARNING: No --goal provided. Placeholders will remain in generated files."
    echo "         Edit .ralph/config.sh and prompts manually before running."
    WARNINGS+=("No --goal provided — placeholders {{GOAL}} and {{PROJECT_GOAL}} remain in files")
    echo ""
fi

# Engine binary presence check
if ! command -v "$ENGINE" &>/dev/null; then
    WARNINGS+=("'$ENGINE' CLI not found in PATH — install it before running ./loop.sh build")
fi

# MCP-backed integrations (Vikunja, Playwright) are wired for Claude Code. codex
# and opencode support MCP too, but require their own server configuration.
if [ "$ENGINE" != "claude" ] && { [ -n "$VIKUNJA_TASK_ID" ] || [ "$PLAYWRIGHT" = "true" ]; }; then
    WARNINGS+=("Engine is '$ENGINE' but MCP-based features (Vikunja/Playwright) are configured for Claude Code — set up the equivalent MCP servers in $ENGINE's config, or expect those steps to be skipped")
fi

if [ -n "$VIKUNJA_TASK_ID" ]; then
    if [ "$ENGINE" = "claude" ] && ! command -v claude &>/dev/null; then
        WARNINGS+=("claude CLI not found — Vikunja integration requires Claude Code with vikunja MCP server configured")
    else
        WARNINGS+=("Vikunja task source set (#$VIKUNJA_TASK_ID) — ensure the vikunja MCP server is configured for $ENGINE")
    fi
fi

if [ -n "$COMPLETION_PROMISE" ]; then
    PROMISE_LEN=${#COMPLETION_PROMISE}
    if [ "$PROMISE_LEN" -gt 100 ]; then
        echo "WARNING: Completion promise is $PROMISE_LEN chars. Keep it short for reliable matching."
        WARNINGS+=("Completion promise is long ($PROMISE_LEN chars) — may cause matching issues")
    fi
fi

if [ "$TDD" = "true" ] && [ -z "$GOAL" ]; then
    WARNINGS+=("TDD enabled but no goal set — Claude won't know what to test")
fi

# --- Create directory structure ---
mkdir -p .ralph/logs .ralph/state
echo "[+] Created .ralph/logs/ and .ralph/state/"

# --- Copy templates ---
copy_template() {
    local src="$1"
    local dst="$2"
    if [ -f "$dst" ]; then
        echo "[ ] Skipped $dst (already exists)"
    else
        cp "$src" "$dst"
        echo "[+] Created $dst"
    fi
}

copy_template "$TEMPLATE_DIR/config.sh.tmpl"              ".ralph/config.sh"
copy_template "$TEMPLATE_DIR/prompt-build.md.tmpl"         ".ralph/prompt-build.md"
copy_template "$TEMPLATE_DIR/prompt-plan.md.tmpl"          ".ralph/prompt-plan.md"
copy_template "$TEMPLATE_DIR/learnings.md.tmpl"            ".ralph/learnings.md"
copy_template "$TEMPLATE_DIR/loop.sh.tmpl"                 "./loop.sh"
copy_template "$TEMPLATE_DIR/IMPLEMENTATION_PLAN.md.tmpl"  "./IMPLEMENTATION_PLAN.md"

chmod +x ./loop.sh

# --- Fill in goal if provided ---
if [ -n "$GOAL" ]; then
    # Use perl for safe substitution — avoids sed delimiter collisions with special chars
    export GOAL
    perl -pi -e 's/\{\{GOAL\}\}/$ENV{GOAL}/g'            .ralph/config.sh
    perl -pi -e 's/\{\{PROJECT_GOAL\}\}/$ENV{GOAL}/g'    .ralph/prompt-build.md
    perl -pi -e 's/\{\{PROJECT_GOAL\}\}/$ENV{GOAL}/g'    .ralph/prompt-plan.md
    perl -pi -e 's/\{\{GOAL\}\}/$ENV{GOAL}/g'            IMPLEMENTATION_PLAN.md
    echo "[+] Filled in project goal"
fi

# --- Set engine and model ---
export ENGINE
perl -pi -e 's/^RALPH_ENGINE=.*/qq{RALPH_ENGINE="$ENV{ENGINE}"}/e' .ralph/config.sh
if [ -n "$MODEL" ]; then
    export MODEL
    perl -pi -e 's/^RALPH_MODEL=.*/qq{RALPH_MODEL="$ENV{MODEL}"}/e' .ralph/config.sh
    echo "[+] Engine: $ENGINE, model: $MODEL"
elif [ "$ENGINE" != "claude" ]; then
    # codex/opencode: empty model = use the CLI's own configured default
    perl -pi -e 's/^RALPH_MODEL=.*/RALPH_MODEL=""/' .ralph/config.sh
    echo "[+] Engine: $ENGINE, model: (engine default)"
else
    echo "[+] Engine: $ENGINE, model: opus"
fi

# --- Fill in Vikunja task ID if provided ---
if [ -n "$VIKUNJA_TASK_ID" ]; then
    export VIKUNJA_TASK_ID
    perl -pi -e 's/RALPH_VIKUNJA_TASK_ID=""/qq~RALPH_VIKUNJA_TASK_ID="$ENV{VIKUNJA_TASK_ID}"~/e' .ralph/config.sh
    echo "[+] Set Vikunja parent task ID: #$VIKUNJA_TASK_ID"
fi

# --- Fill in completion promise if provided ---
if [ -n "$COMPLETION_PROMISE" ]; then
    export COMPLETION_PROMISE
    perl -pi -e 's/RALPH_COMPLETION_PROMISE=""/qq~RALPH_COMPLETION_PROMISE="$ENV{COMPLETION_PROMISE}"~/e' .ralph/config.sh
    echo "[+] Set completion promise: $COMPLETION_PROMISE"
fi

# --- Enable TDD mode if requested ---
if [ "$TDD" = "true" ]; then
    perl -pi -e 's/RALPH_TDD="false"/RALPH_TDD="true"/g' .ralph/config.sh
    echo "[+] TDD mode enabled (Red-Green-Refactor workflow)"
fi

# --- Enable Playwright browser verification if requested ---
if [ "$PLAYWRIGHT" = "true" ]; then
    perl -pi -e 's/RALPH_PLAYWRIGHT="false"/RALPH_PLAYWRIGHT="true"/g' .ralph/config.sh
    echo "[+] Playwright browser verification enabled"
fi

# --- Auto-detect build/test/lint commands ---
BUILD_CMD=""
TEST_CMD=""
LINT_CMD=""

if [ -f "package.json" ]; then
    # Node.js / TypeScript
    BUILD_CMD="npm run build"
    TEST_CMD="npm test"
    LINT_CMD="npm run lint"
    # Check for specific scripts
    if grep -q '"check"[[:space:]]*:' package.json 2>/dev/null; then
        LINT_CMD="npm run check"
    elif grep -q '"typecheck"[[:space:]]*:' package.json 2>/dev/null; then
        LINT_CMD="npm run lint && npm run typecheck"
    fi
elif [ -f "Cargo.toml" ]; then
    BUILD_CMD="cargo build"
    TEST_CMD="cargo test"
    LINT_CMD="cargo clippy"
elif [ -f "go.mod" ]; then
    BUILD_CMD="go build ./..."
    TEST_CMD="go test ./..."
    LINT_CMD="go vet ./..."
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
    BUILD_CMD="python -m py_compile *.py"
    TEST_CMD="pytest"
    LINT_CMD="ruff check ."
elif [ -f "pom.xml" ]; then
    BUILD_CMD="mvn compile"
    TEST_CMD="mvn test"
    LINT_CMD="mvn checkstyle:check"
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    BUILD_CMD="./gradlew build"
    TEST_CMD="./gradlew test"
    LINT_CMD="./gradlew check"
elif [ -f "Makefile" ]; then
    BUILD_CMD="make"
    TEST_CMD="make test"
    LINT_CMD="make lint"
fi

if [ -n "$BUILD_CMD" ]; then
    export BUILD_CMD TEST_CMD LINT_CMD
    perl -pi -e 's/\{\{BUILD_CMD\}\}/$ENV{BUILD_CMD}/g' .ralph/prompt-build.md
    perl -pi -e 's/\{\{TEST_CMD\}\}/$ENV{TEST_CMD}/g'   .ralph/prompt-build.md
    perl -pi -e 's/\{\{LINT_CMD\}\}/$ENV{LINT_CMD}/g'   .ralph/prompt-build.md
    echo "[+] Auto-detected commands: build=$BUILD_CMD test=$TEST_CMD lint=$LINT_CMD"
else
    export BUILD_CMD="echo 'No build command configured -- edit .ralph/prompt-build.md'"
    export TEST_CMD="echo 'No test command configured -- edit .ralph/prompt-build.md'"
    export LINT_CMD="echo 'No lint command configured -- edit .ralph/prompt-build.md'"
    perl -pi -e 's/\{\{BUILD_CMD\}\}/$ENV{BUILD_CMD}/g' .ralph/prompt-build.md
    perl -pi -e 's/\{\{TEST_CMD\}\}/$ENV{TEST_CMD}/g'   .ralph/prompt-build.md
    perl -pi -e 's/\{\{LINT_CMD\}\}/$ENV{LINT_CMD}/g'   .ralph/prompt-build.md
    echo "[!] Could not auto-detect build commands. Edit .ralph/prompt-build.md manually."
fi

# --- Auto-gitignore ---
if [ -f ".gitignore" ]; then
    if ! grep -qF '.ralph/' .gitignore; then
        echo "" >> .gitignore
        echo "# Ralph loop artifacts" >> .gitignore
        echo ".ralph/" >> .gitignore
        echo "[+] Added .ralph/ to .gitignore"
    else
        echo "[ ] .ralph/ already in .gitignore"
    fi
else
    echo "# Ralph loop artifacts" > .gitignore
    echo ".ralph/" >> .gitignore
    echo "[+] Created .gitignore with .ralph/"
fi

# --- Summary ---
echo ""
echo "  ─────────────────"
echo "  done."
echo ""
echo "  Configuration:"
echo "  ├── Engine:    $ENGINE${MODEL:+ ($MODEL)}"
echo "  ├── Goal:      ${GOAL:-"(not set — edit files manually)"}"
if [ -n "$VIKUNJA_TASK_ID" ]; then
    echo "  ├── Vikunja:   task #$VIKUNJA_TASK_ID"
fi
if [ -n "$COMPLETION_PROMISE" ]; then
    echo "  ├── Promise:   $COMPLETION_PROMISE"
fi
if [ "$TDD" = "true" ]; then
    echo "  ├── TDD:       enabled"
fi
if [ "$PLAYWRIGHT" = "true" ]; then
    echo "  ├── Playwright: enabled"
fi
echo "  └── Build:     ${BUILD_CMD:-"(not detected)"}"
echo ""

# Show warnings if any
if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo "  Warnings:"
    for w in "${WARNINGS[@]}"; do
        echo "  ⚠  $w"
    done
    echo ""
fi

echo "  Next steps:"
echo "  1. Review .ralph/config.sh"
echo "  2. Review .ralph/prompt-build.md"
echo "  3. Run:  ./loop.sh plan      # Generate implementation plan"
echo "  4. Run:  ./loop.sh build     # Start building"
echo "  5. Or:   ./loop.sh build --delay 3h"
echo ""
