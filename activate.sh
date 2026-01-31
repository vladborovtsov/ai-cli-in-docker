# Source this file to add AI Docker helpers to your shell.
# Usage:
#   source ./activate.sh
#   codex-docker-build
#   codex-docker-shell
#   gemini-docker-build
#   gemini-docker-shell

CODEX_IMAGE_NAME="my-codex-image"
GEMINI_IMAGE_NAME="my-gemini-image"
CLAUDE_IMAGE_NAME="my-claude-image"
CODEX_CONFIG_PATH="$HOME/.codex-docker-config"
GEMINI_CONFIG_PATH="$HOME/.gemini-cli-docker-config"
CLAUDE_CONFIG_PATH="$HOME/.claude-docker-config"
CODEX_TERM_TITLE_ENABLE="${CODEX_ITERM_TITLE_ENABLE:-1}" # Control whether iTerm/tab title tweaks are applied (default: on). Set to "0" to disable.

# Determine the directory of this script (the repo root), even when sourced from elsewhere.
# Works with Bash and most POSIX shells; realpath fallback if available.
if [ -n "$BASH_SOURCE" ]; then
  _codex_script_path="$BASH_SOURCE"
else
  # Fallback: when $BASH_SOURCE is not set (other shells), try $0 if sourced via ". ./activate.sh"
  _codex_script_path="$0"
fi
# Resolve to an absolute directory
if command -v realpath >/dev/null 2>&1; then
  CODEX_REPO_DIR="$(dirname "$(realpath "$_codex_script_path")")"
else
  # Portable resolution: cd into the script dir and print pwd
  CODEX_REPO_DIR="$(cd "$(dirname "$_codex_script_path")" 2>/dev/null && pwd)"
fi
unset _codex_script_path

codex-docker-build() {
  # Accept optional flag: --no-cache
  local no_cache_flag=""
  if [ "${1-}" = "--no-cache" ]; then
    no_cache_flag="--no-cache"
    shift
  fi
  if [ -n "${1-}" ]; then
    echo "Usage: codex-docker-build [--no-cache]" >&2
    return 2
  fi
  if [ -z "$CODEX_REPO_DIR" ]; then
    echo "Failed to locate repository directory for docker build." >&2
    return 1
  fi
  echo "Building Docker image '$CODEX_IMAGE_NAME' from: $CODEX_REPO_DIR (Dockerfile.codex)" >&2
  local old_image_id
  old_image_id=$(docker images -q "$CODEX_IMAGE_NAME" 2>/dev/null)

  if docker build --pull ${no_cache_flag} -f "$CODEX_REPO_DIR/Dockerfile.codex" -t "$CODEX_IMAGE_NAME" "$CODEX_REPO_DIR"; then
    if [ -n "$old_image_id" ]; then
      local new_image_id
      new_image_id=$(docker images -q "$CODEX_IMAGE_NAME" 2>/dev/null)
      if [ "$old_image_id" != "$new_image_id" ]; then
        echo "Cleaning up previous image version ($old_image_id)..." >&2
        docker rmi "$old_image_id" 2>/dev/null || true
      fi
    fi
  fi
}

codex-docker-shell() {
  local cwd
  cwd="$(pwd)"
  if [ "$cwd" = "$HOME" ]; then
    echo "⚠️ Warning: You are running codex-docker-shell from your HOME directory." >&2
    echo "This will mount your entire HOME into the container workspace." >&2
    printf "Proceed with mounting HOME? [y/N]: " >&2
    IFS= read -r confirm
    case "$confirm" in
      [yY]|[yY][eE][sS]) ;;
      *) echo "Canceled." >&2; return 1 ;;
    esac
  fi


  if [ "${CODEX_TERM_TITLE_ENABLE}" = "1" ]; then
    local _codex_title="codex+$(basename "${cwd}")"
    if [ -n "${ITERM_SESSION_ID-}" ] || [ "${TERM_PROGRAM-}" = "iTerm.app" ]; then
      if command -v base64 >/dev/null 2>&1; then
        printf '\033]1337;SetUserVar=%s=%s\007' "JOB_NAME" "$(printf "%s" "${_codex_title}" | base64)" 2>/dev/null || true
      fi
    fi
    # OSC 1: icon name (many terminals use this as a title source)
    printf '\033]1;%s\007' "${_codex_title}" 2>/dev/null || true
    # OSC 0: window title (tab title)
    printf '\033]0;%s\007' "${_codex_title}" 2>/dev/null || true
  fi

  docker run --rm -it \
    --entrypoint "/bin/bash" \
    -v "/etc/localtime:/etc/localtime:ro" \
    -v "$CODEX_CONFIG_PATH:/root/.codex" \
    -v "${cwd}:/workspace/$(basename "${cwd}")" \
    -w "/workspace/$(basename "${cwd}")" \
    -e TZ="${TZ:-$(readlink /etc/localtime | sed -E 's/.*zoneinfo\/(.*)/\1/' 2>/dev/null || echo "UTC")}" \
    -e TERM="${TERM:-xterm-256color}" \
    -e TMUX_SESSION="$(basename "${cwd}")" \
    -e AI_NAME="codex" \
    -e AI_COMMAND="codex" \
    "$CODEX_IMAGE_NAME" \
    -lc "start-tmux-layout"
}

codex-auth-docker-run() {
  local cwd
  cwd="$(pwd)"
  if [ "$cwd" = "$HOME" ]; then
    echo "⚠️ Warning: You are running codex-auth-docker-run from your HOME directory." >&2
    echo "This will mount your entire HOME into the container workspace." >&2
    printf "Proceed with mounting HOME? [y/N]: " >&2
    IFS= read -r confirm
    case "$confirm" in
      [yY]|[yY][eE][sS]) ;;
      *) echo "Canceled." >&2; return 1 ;;
    esac
  fi
  docker run --rm -it \
    --network="host" \
    --entrypoint="/bin/bash" \
    -v "/etc/localtime:/etc/localtime:ro" \
    -v "$CODEX_CONFIG_PATH:/root/.codex" \
    -v "${cwd}:/workspace/$(basename "${cwd}")" \
    -w "/workspace/$(basename "${cwd}")" \
    -e TZ="${TZ:-$(readlink /etc/localtime | sed -E 's/.*zoneinfo\/(.*)/\1/' 2>/dev/null || echo "UTC")}" \
    "$CODEX_IMAGE_NAME" \
    -c ". /root/.nvm/nvm.sh && screen codex auth"
}

gemini-docker-build() {
  # Accept optional flag: --no-cache
  local no_cache_flag=""
  if [ "${1-}" = "--no-cache" ]; then
    no_cache_flag="--no-cache"
    shift
  fi
  if [ -n "${1-}" ]; then
    echo "Usage: gemini-docker-build [--no-cache]" >&2
    return 2
  fi
  if [ -z "$CODEX_REPO_DIR" ]; then
    echo "Failed to locate repository directory for docker build." >&2
    return 1
  fi
  echo "Building Docker image '$GEMINI_IMAGE_NAME' from: $CODEX_REPO_DIR (Dockerfile.gemini)" >&2
  local old_image_id
  old_image_id=$(docker images -q "$GEMINI_IMAGE_NAME" 2>/dev/null)

  if docker build --pull ${no_cache_flag} -f "$CODEX_REPO_DIR/Dockerfile.gemini" -t "$GEMINI_IMAGE_NAME" "$CODEX_REPO_DIR"; then
    if [ -n "$old_image_id" ]; then
      local new_image_id
      new_image_id=$(docker images -q "$GEMINI_IMAGE_NAME" 2>/dev/null)
      if [ "$old_image_id" != "$new_image_id" ]; then
        echo "Cleaning up previous image version ($old_image_id)..." >&2
        docker rmi "$old_image_id" 2>/dev/null || true
      fi
    fi
  fi
}

gemini-docker-shell() {
  local cwd
  cwd="$(pwd)"
  if [ "$cwd" = "$HOME" ]; then
    echo "⚠️ Warning: You are running gemini-docker-shell from your HOME directory." >&2
    echo "This will mount your entire HOME into the container workspace." >&2
    printf "Proceed with mounting HOME? [y/N]: " >&2
    IFS= read -r confirm
    case "$confirm" in
      [yY]|[yY][eE][sS]) ;;
      *) echo "Canceled." >&2; return 1 ;;
    esac
  fi


  if [ "${CODEX_TERM_TITLE_ENABLE}" = "1" ]; then
    local _gemini_title="gemini+$(basename "${cwd}")"
    if [ -n "${ITERM_SESSION_ID-}" ] || [ "${TERM_PROGRAM-}" = "iTerm.app" ]; then
      if command -v base64 >/dev/null 2>&1; then
        printf '\033]1337;SetUserVar=%s=%s\007' "JOB_NAME" "$(printf "%s" "${_gemini_title}" | base64)" 2>/dev/null || true
      fi
    fi
    # OSC 1: icon name (many terminals use this as a title source)
    printf '\033]1;%s\007' "${_gemini_title}" 2>/dev/null || true
    # OSC 0: window title (tab title)
    printf '\033]0;%s\007' "${_gemini_title}" 2>/dev/null || true
  fi

  docker run --rm -it \
    --entrypoint "/bin/bash" \
    -v "/etc/localtime:/etc/localtime:ro" \
    -v "$GEMINI_CONFIG_PATH:/root/.gemini" \
    -v "${cwd}:/workspace/$(basename "${cwd}")" \
    -w "/workspace/$(basename "${cwd}")" \
    -e TZ="${TZ:-$(readlink /etc/localtime | sed -E 's/.*zoneinfo\/(.*)/\1/' 2>/dev/null || echo "UTC")}" \
    -e TERM="${TERM:-xterm-256color}" \
    -e TMUX_SESSION="$(basename "${cwd}")" \
    -e AI_NAME="gemini" \
    -e AI_COMMAND="gemini" \
    "$GEMINI_IMAGE_NAME" \
    -lc "start-tmux-layout"
}

claude-docker-build() {
  # Accept optional flag: --no-cache
  local no_cache_flag=""
  if [ "${1-}" = "--no-cache" ]; then
    no_cache_flag="--no-cache"
    shift
  fi
  if [ -n "${1-}" ]; then
    echo "Usage: claude-docker-build [--no-cache]" >&2
    return 2
  fi
  if [ -z "$CODEX_REPO_DIR" ]; then
    echo "Failed to locate repository directory for docker build." >&2
    return 1
  fi
  echo "Building Docker image '$CLAUDE_IMAGE_NAME' from: $CODEX_REPO_DIR (Dockerfile.claude)" >&2
  local old_image_id
  old_image_id=$(docker images -q "$CLAUDE_IMAGE_NAME" 2>/dev/null)

  if docker build --pull ${no_cache_flag} -f "$CODEX_REPO_DIR/Dockerfile.claude" -t "$CLAUDE_IMAGE_NAME" "$CODEX_REPO_DIR"; then
    if [ -n "$old_image_id" ]; then
      local new_image_id
      new_image_id=$(docker images -q "$CLAUDE_IMAGE_NAME" 2>/dev/null)
      if [ "$old_image_id" != "$new_image_id" ]; then
        echo "Cleaning up previous image version ($old_image_id)..." >&2
        docker rmi "$old_image_id" 2>/dev/null || true
      fi
    fi
  fi
}

claude-docker-shell() {
  local cwd
  cwd="$(pwd)"
  if [ "$cwd" = "$HOME" ]; then
    echo "⚠️ Warning: You are running claude-docker-shell from your HOME directory." >&2
    echo "This will mount your entire HOME into the container workspace." >&2
    printf "Proceed with mounting HOME? [y/N]: " >&2
    IFS= read -r confirm
    case "$confirm" in
      [yY]|[yY][eE][sS]) ;;
      *) echo "Canceled." >&2; return 1 ;;
    esac
  fi


  if [ "${CODEX_TERM_TITLE_ENABLE}" = "1" ]; then
    local _claude_title="claude+$(basename "${cwd}")"
    if [ -n "${ITERM_SESSION_ID-}" ] || [ "${TERM_PROGRAM-}" = "iTerm.app" ]; then
      if command -v base64 >/dev/null 2>&1; then
        printf '\033]1337;SetUserVar=%s=%s\007' "JOB_NAME" "$(printf "%s" "${_claude_title}" | base64)" 2>/dev/null || true
      fi
    fi
    # OSC 1: icon name (many terminals use this as a title source)
    printf '\033]1;%s\007' "${_claude_title}" 2>/dev/null || true
    # OSC 0: window title (tab title)
    printf '\033]0;%s\007' "${_claude_title}" 2>/dev/null || true
  fi

  docker run --rm -it \
    --entrypoint "/bin/bash" \
    -v "/etc/localtime:/etc/localtime:ro" \
    -v "$CLAUDE_CONFIG_PATH:/root/.claude" \
    -v "${cwd}:/workspace/$(basename "${cwd}")" \
    -w "/workspace/$(basename "${cwd}")" \
    -e TZ="${TZ:-$(readlink /etc/localtime | sed -E 's/.*zoneinfo\/(.*)/\1/' 2>/dev/null || echo "UTC")}" \
    -e TERM="${TERM:-xterm-256color}" \
    -e TMUX_SESSION="$(basename "${cwd}")" \
    -e AI_NAME="claude" \
    -e AI_COMMAND="claude" \
    "$CLAUDE_IMAGE_NAME" \
    -lc "start-tmux-layout"
}

codex-deactivate() {
  unset -f codex-docker-build codex-docker-shell codex-auth-docker-run gemini-docker-build gemini-docker-shell claude-docker-build claude-docker-shell codex-deactivate
}