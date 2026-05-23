#!/usr/bin/env bash
# Sanity check script executed inside the built container to verify dependencies.
set -euo pipefail

TOOL_NAME="${1:-}"

if [ -z "$TOOL_NAME" ]; then
  echo "Error: TOOL_NAME must be specified as first argument (claude, antigravity, codex, opencode)." >&2
  exit 1
fi

echo "=== Verifying Container Setup for: $TOOL_NAME ==="

# Check common terminal utilities
for cmd in tmux htop lazygit start-tmux-layout; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "✔ Utility '$cmd' is installed and accessible."
  else
    echo "✘ ERROR: Utility '$cmd' is NOT installed or not on PATH!" >&2
    exit 1
  fi
done

# Validate start-tmux-layout syntax
if bash -n /usr/local/bin/start-tmux-layout; then
  echo "✔ start-tmux-layout bash syntax is valid."
else
  echo "✘ ERROR: start-tmux-layout has syntax errors!" >&2
  exit 1
fi

# Verify the respective AI CLI tool
case "$TOOL_NAME" in
  claude)
    # Check for Claude Code command
    if command -v claude >/dev/null 2>&1; then
      echo "✔ claude CLI command is present."
    else
      echo "✘ ERROR: claude CLI command is NOT present!" >&2
      exit 1
    fi
    ;;
  antigravity)
    if command -v agy >/dev/null 2>&1; then
      echo "✔ agy CLI command is present."
    else
      echo "✘ ERROR: agy CLI command is NOT present!" >&2
      exit 1
    fi
    ;;
  codex)
    if command -v codex >/dev/null 2>&1; then
      echo "✔ codex CLI command is present."
    else
      echo "✘ ERROR: codex CLI command is NOT present!" >&2
      exit 1
    fi
    ;;
  opencode)
    if command -v opencode >/dev/null 2>&1; then
      echo "✔ opencode CLI command is present."
    else
      echo "✘ ERROR: opencode CLI command is NOT present!" >&2
      exit 1
    fi
    ;;
  *)
    echo "✘ ERROR: Unknown tool name: $TOOL_NAME" >&2
    exit 1
    ;;
esac

echo "=== All Container Sanity Checks Passed for $TOOL_NAME ==="
exit 0
