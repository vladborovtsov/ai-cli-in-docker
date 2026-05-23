# Source this file to add AI Docker helpers to your shell.
# Usage:
#   source ./activate.sh
#   codex-docker-build
#   codex-docker-shell
#   antigravity-docker-build
#   antigravity-docker-shell
#   opencode-docker-build
#   opencode-docker-shell
#   claude-docker-build
#   claude-docker-shell
#   docker-ai-build-all

CODEX_IMAGE_NAME="my-codex-image"
ANTIGRAVITY_IMAGE_NAME="my-antigravity-image"
CLAUDE_IMAGE_NAME="my-claude-image"
OPENCODE_IMAGE_NAME="my-opencode-image"

if [ -n "${AI_DOCKER_PROFILE-}" ] && [ -z "${AI_DOCKER_PROFILE_ENV_OVERRIDE-}" ]; then
  export AI_DOCKER_PROFILE_ENV_OVERRIDE="$AI_DOCKER_PROFILE"
fi

_ai_docker_migrate_legacy() {
  local old_ignore_dir="$HOME/.ai-docker-ignore"
  local new_profiles_dir="$HOME/.ai-docker-profiles"
  if [ -d "$old_ignore_dir" ] && [ ! -d "$new_profiles_dir" ]; then
    mv "$old_ignore_dir" "$new_profiles_dir"
  fi

  local legacy_codex="$HOME/.codex-docker-config"
  local legacy_gemini="$HOME/.gemini-cli-docker-config"
  local legacy_claude="$HOME/.claude-docker-config"
  local legacy_opencode="$HOME/.opencode-docker"
  local legacy_recents="$HOME/.ai-docker-recents"

  local target_dir="$HOME/.ai-docker-profiles/default"

  # Helper to migrate directory
  migrate_dir() {
    local src="$1"
    local dest="$2"
    if [ -d "$src" ]; then
      mkdir -p "$(dirname "$dest")"
      if [ ! -d "$dest" ]; then
        mv "$src" "$dest"
      else
        # Target exists, merge files
        for f in "$src"/* "$src"/.*; do
          [ "$(basename "$f")" = "." ] && continue
          [ "$(basename "$f")" = ".." ] && continue
          [ -e "$f" ] || continue
          mv "$f" "$dest/"
        done
        rmdir "$src" 2>/dev/null || rm -rf "$src"
      fi
    fi
  }

  # Migrate recents file
  if [ -f "$legacy_recents" ]; then
    mkdir -p "$target_dir"
    mv "$legacy_recents" "$target_dir/ai-docker-recents"
  elif [ -d "$legacy_recents" ]; then
    mkdir -p "$target_dir"
    if [ -f "$legacy_recents/recents" ]; then
      mv "$legacy_recents/recents" "$target_dir/ai-docker-recents"
    elif [ -f "$legacy_recents/ai-docker-recents" ]; then
      mv "$legacy_recents/ai-docker-recents" "$target_dir/ai-docker-recents"
    fi
    rm -rf "$legacy_recents"
  fi

  migrate_dir "$legacy_codex" "$target_dir/codex-docker-config"
  migrate_dir "$legacy_gemini" "$target_dir/antigravity-cli-docker-config"
  migrate_dir "$legacy_claude" "$target_dir/claude-docker-config"
  migrate_dir "$legacy_opencode" "$target_dir/opencode-docker"
}

_ai_docker_get_project_profile() {
  local target_path="$1"
  local map_file="$HOME/.ai-docker-profiles/project-profiles"
  if [ -f "$map_file" ]; then
    local resolved_target
    resolved_target=$(cd "$target_path" 2>/dev/null && pwd || echo "$target_path")
    while IFS= read -r line || [ -n "$line" ]; do
      [[ "$line" =~ ^# ]] && continue
      [ -z "$line" ] && continue
      local p_path="${line%:*}"
      local p_profile="${line##*:}"
      if [ "$p_path" = "$resolved_target" ]; then
        echo "$p_profile"
        return 0
      fi
    done < "$map_file"
  fi
  return 0
}

_ai_docker_set_project_profile() {
  local target_path="$1"
  local profile_name="$2"
  local map_file="$HOME/.ai-docker-profiles/project-profiles"
  mkdir -p "$(dirname "$map_file")"
  
  local resolved_target
  resolved_target=$(cd "$target_path" 2>/dev/null && pwd || echo "$target_path")

  local tmp_file="${map_file}.tmp"
  local found=0
  if [ -f "$map_file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if [ -n "$line" ]; then
        local p_path="${line%:*}"
        if [ "$p_path" = "$resolved_target" ]; then
          if [ -n "$profile_name" ]; then
            echo "${resolved_target}:${profile_name}" >> "$tmp_file"
          fi
          found=1
        else
          echo "$line" >> "$tmp_file"
        fi
      fi
    done < "$map_file"
  fi

  if [ "$found" -eq 0 ] && [ -n "$profile_name" ]; then
    echo "${resolved_target}:${profile_name}" >> "$tmp_file"
  fi

  if [ -f "$tmp_file" ]; then
    mv "$tmp_file" "$map_file"
  else
    > "$map_file"
  fi
}

_ai_docker_load_profile() {
  local target_profile="${1-}"
  local directory="${2-}"

  # Migrate legacy config paths
  _ai_docker_migrate_legacy

  if [ -n "$target_profile" ]; then
    AI_DOCKER_PROFILE="$target_profile"
  fi

  if [ -z "${AI_DOCKER_PROFILE-}" ]; then
    if [ -n "${AI_DOCKER_PROFILE_ENV_OVERRIDE-}" ]; then
      AI_DOCKER_PROFILE="$AI_DOCKER_PROFILE_ENV_OVERRIDE"
    else
      # Check directory mapping
      local check_dir="${directory:-$(pwd)}"
      local resolved_dir
      resolved_dir=$(cd "$check_dir" 2>/dev/null && pwd || echo "$check_dir")
      
      local mapped_profile=""
      if [ -n "$resolved_dir" ]; then
        mapped_profile=$(_ai_docker_get_project_profile "$resolved_dir" || true)
      fi

      if [ -n "$mapped_profile" ]; then
        AI_DOCKER_PROFILE="$mapped_profile"
      else
        local active_profile_file="$HOME/.ai-docker-active-profile"
        if [ -f "$active_profile_file" ]; then
          AI_DOCKER_PROFILE="$(cat "$active_profile_file" | tr -d '\r\n[:space:]')"
        else
          AI_DOCKER_PROFILE="default"
        fi
      fi
    fi
  fi

  AI_DOCKER_PROFILE="${AI_DOCKER_PROFILE:-default}"

  local profile_dir="$HOME/.ai-docker-profiles/$AI_DOCKER_PROFILE"
  CODEX_CONFIG_PATH="$profile_dir/codex-docker-config"
  ANTIGRAVITY_CONFIG_PATH="$profile_dir/antigravity-cli-docker-config"
  CLAUDE_CONFIG_PATH="$profile_dir/claude-docker-config"
  OPENCODE_DOCKER_DIR="$profile_dir/opencode-docker"
  AI_DOCKER_RECENTS_FILE="$profile_dir/ai-docker-recents"

  # Migrate profile-level config folder if it exists
  if [ -d "$profile_dir/gemini-cli-docker-config" ] && [ ! -d "$ANTIGRAVITY_CONFIG_PATH" ]; then
    mv "$profile_dir/gemini-cli-docker-config" "$ANTIGRAVITY_CONFIG_PATH"
  fi

  for dir in \
    "$CODEX_CONFIG_PATH" \
    "$ANTIGRAVITY_CONFIG_PATH" \
    "$CLAUDE_CONFIG_PATH" \
    "$OPENCODE_DOCKER_DIR"
  do
    mkdir -p "$dir"
    touch "$dir/docker-env.env"
    if [ "$dir" = "$CLAUDE_CONFIG_PATH" ]; then
      touch "$dir/claude.json"
    fi
  done
  mkdir -p "$OPENCODE_DOCKER_DIR/local" "$OPENCODE_DOCKER_DIR/config"
}

_ai_docker_load_profile "" "$(pwd)"

ai-docker-profile() {
  local target="${1-}"
  if [ -z "$target" ]; then
    echo "Current profile: ${AI_DOCKER_PROFILE:-default}"
    echo "Available profiles:"
    echo "  default"
    local ignore_dir="$HOME/.ai-docker-profiles"
    if [ -d "$ignore_dir" ]; then
      for d in "$ignore_dir"/*; do
        if [ -d "$d" ]; then
          local name
          name=$(basename "$d")
          if [ "$name" != "default" ] && [ "$name" != "project-profiles" ]; then
            echo "  $name"
          fi
        fi
      done
    fi
    return 0
  fi

  local sanitized
  sanitized=$(echo "$target" | tr -cd 'a-zA-Z0-9_-')
  if [ "$sanitized" != "$target" ] || [ -z "$target" ]; then
    echo "Error: Invalid profile name. Only alphanumeric, dashes, and underscores are allowed." >&2
    return 1
  fi

  echo "$target" > "$HOME/.ai-docker-active-profile"
  _ai_docker_load_profile "$target"
  
  if [ "$(pwd)" != "$HOME" ]; then
    _ai_docker_set_project_profile "$(pwd)" "$target"
    echo "Profile '$target' activated and mapped to current directory."
  else
    echo "Profile '$target' activated globally."
  fi
}


AI_DOCKER_TERM_TITLE_ENABLE="${AI_DOCKER_TERM_TITLE_ENABLE:-${CODEX_ITERM_TITLE_ENABLE:-1}}" # Control whether iTerm/tab title tweaks are applied (default: on). Set to "0" to disable.

# Determine the directory of this script (the repo root), even when sourced from elsewhere.
# Works with Bash and most POSIX shells; realpath fallback if available.
if [ -n "${BASH_SOURCE-}" ]; then
  _ai_docker_script_path="$BASH_SOURCE"
else
  # Fallback: when $BASH_SOURCE is not set (other shells), try $0 if sourced via ". ./activate.sh"
  _ai_docker_script_path="$0"
fi
# Resolve to an absolute directory
if command -v realpath >/dev/null 2>&1; then
  AI_DOCKER_REPO_DIR="$(dirname "$(realpath "$_ai_docker_script_path")")"
else
  # Portable resolution: cd into the script dir and print pwd
  AI_DOCKER_REPO_DIR="$(cd "$(dirname "$_ai_docker_script_path")" 2>/dev/null && pwd)"
fi
unset _ai_docker_script_path

_ai_docker_update_recents() {
  local path_to_add="$1"
  if [ -z "$path_to_add" ] || [ ! -d "$path_to_add" ]; then
    return
  fi

  local resolved_add
  resolved_add=$(cd "$path_to_add" 2>/dev/null && pwd || echo "$path_to_add")

  local dirs=()
  dirs+=("$resolved_add")

  if [ -f "$AI_DOCKER_RECENTS_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if [ -n "$line" ] && [ -d "$line" ]; then
        local resolved
        resolved=$(cd "$line" 2>/dev/null && pwd || echo "$line")
        if [ -d "$resolved" ]; then
          dirs+=("$resolved")
        fi
      fi
    done < "$AI_DOCKER_RECENTS_FILE"
  fi

  local unique_dirs=()
  for d in "${dirs[@]}"; do
    if [ "${#unique_dirs[@]}" -ge 10 ]; then
      break
    fi
    local dup=0
    if [ "${#unique_dirs[@]}" -gt 0 ]; then
      for u in "${unique_dirs[@]}"; do
        if [ "$u" = "$d" ]; then
          dup=1
          break
        fi
      done
    fi
    if [ "$dup" -eq 0 ]; then
      unique_dirs+=("$d")
    fi
  done

  if [ "${#unique_dirs[@]}" -gt 0 ]; then
    printf "%s\n" "${unique_dirs[@]}" > "$AI_DOCKER_RECENTS_FILE"
  else
    > "$AI_DOCKER_RECENTS_FILE"
  fi
}

_ai_docker_is_linux_host() {
  [ "$(uname -s 2>/dev/null || echo "")" = "Linux" ]
}

_ai_docker_should_mount_localtime() {
  _ai_docker_is_linux_host && [ -e "/etc/localtime" ]
}

_ai_docker_detect_tz() {
  if [ -n "${TZ-}" ]; then
    echo "$TZ"
    return
  fi

  if command -v timedatectl >/dev/null 2>&1; then
    local tz_timedatectl
    tz_timedatectl="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
    if [ -n "$tz_timedatectl" ] && [ "$tz_timedatectl" != "n/a" ]; then
      echo "$tz_timedatectl"
      return
    fi
  fi

  if [ -f "/etc/timezone" ]; then
    local tz_file
    tz_file="$(tr -d '\r\n' < /etc/timezone 2>/dev/null || true)"
    if [ -n "$tz_file" ]; then
      echo "$tz_file"
      return
    fi
  fi

  local localtime_path=""
  if command -v realpath >/dev/null 2>&1; then
    localtime_path="$(realpath /etc/localtime 2>/dev/null || true)"
  fi
  if [ -z "$localtime_path" ]; then
    localtime_path="$(readlink /etc/localtime 2>/dev/null || true)"
  fi
  case "$localtime_path" in
    *zoneinfo/*)
      echo "${localtime_path#*zoneinfo/}"
      return
      ;;
  esac

  if command -v systemsetup >/dev/null 2>&1; then
    local tz_systemsetup
    tz_systemsetup="$(systemsetup -gettimezone 2>/dev/null | sed -E 's/^Time Zone: *//; s/^[[:space:]]+//; s/[[:space:]]+$//' || true)"
    if [ -n "$tz_systemsetup" ]; then
      echo "$tz_systemsetup"
      return
    fi
  fi

  echo "UTC"
}

_ai_docker_should_use_host_network() {
  case "${AI_DOCKER_USE_HOST_NETWORK:-auto}" in
    1|true|TRUE|yes|YES) return 0 ;;
    0|false|FALSE|no|NO) return 1 ;;
  esac
  _ai_docker_is_linux_host
}

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
  if [ -z "$AI_DOCKER_REPO_DIR" ]; then
    echo "Failed to locate repository directory for docker build." >&2
    return 1
  fi
  echo "Building Docker image '$CODEX_IMAGE_NAME' from: $AI_DOCKER_REPO_DIR (Dockerfile.codex)" >&2
  local old_image_id
  old_image_id=$(docker images -q "$CODEX_IMAGE_NAME" 2>/dev/null)

  if docker build --pull ${no_cache_flag} -f "$AI_DOCKER_REPO_DIR/Dockerfile.codex" -t "$CODEX_IMAGE_NAME" "$AI_DOCKER_REPO_DIR"; then
    if [ -n "$old_image_id" ]; then
      local new_image_id
      new_image_id=$(docker images -q "$CODEX_IMAGE_NAME" 2>/dev/null)
      if [ "$old_image_id" != "$new_image_id" ]; then
        echo "Cleaning up previous image version ($old_image_id)..." >&2
        docker rmi "$old_image_id" 2>/dev/null || true
      fi
    fi
  else
    return $?
  fi
}

codex-docker-shell() {
  local cwd
  if [ -n "${1-}" ]; then
    if [ ! -d "$1" ]; then
      echo "Error: Directory '$1' does not exist." >&2
      return 1
    fi
    cwd=$(cd "$1" && pwd)
  else
    cwd="$(pwd)"
  fi

  _ai_docker_load_profile "" "$cwd"
  _ai_docker_update_recents "$cwd"

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


  if [ "${AI_DOCKER_TERM_TITLE_ENABLE}" = "1" ]; then
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

  local workspace_name
  workspace_name="$(basename "${cwd}")"
  local tz_value
  tz_value="$(_ai_docker_detect_tz)"

  local docker_args=(
    --rm -it
    --env-file "$CODEX_CONFIG_PATH/docker-env.env"
    --entrypoint "/bin/bash"
  )
  if _ai_docker_should_mount_localtime; then
    docker_args+=(-v "/etc/localtime:/etc/localtime:ro")
  fi
  if [ -f "$HOME/.gitconfig" ]; then
    docker_args+=(-v "$HOME/.gitconfig:/root/.gitconfig:ro")
  fi
  if [ -f "$HOME/.config/git/config" ]; then
    docker_args+=(-v "$HOME/.config/git/config:/root/.config/git/config:ro")
  fi
  docker_args+=(
    -v "$CODEX_CONFIG_PATH:/root/.codex"
    -v "${cwd}:/workspace/${workspace_name}"
    -w "/workspace/${workspace_name}"
    -e "TZ=${tz_value}"
    -e "TERM=${TERM:-xterm-256color}"
    -e "TMUX_SESSION=${workspace_name}"
    -e "AI_DOCKER_PROFILE=${AI_DOCKER_PROFILE}"
    -e AI_NAME=codex
    -e AI_COMMAND=codex
    "$CODEX_IMAGE_NAME"
    -lc "start-tmux-layout"
  )

  docker run "${docker_args[@]}"
}

codex-auth-docker-run() {
  local cwd
  if [ -n "${1-}" ]; then
    if [ ! -d "$1" ]; then
      echo "Error: Directory '$1' does not exist." >&2
      return 1
    fi
    cwd=$(cd "$1" && pwd)
  else
    cwd="$(pwd)"
  fi

  _ai_docker_load_profile "" "$cwd"
  _ai_docker_update_recents "$cwd"

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
  local workspace_name
  workspace_name="$(basename "${cwd}")"
  local tz_value
  tz_value="$(_ai_docker_detect_tz)"

  local docker_args=(
    --rm -it
    --env-file "$CODEX_CONFIG_PATH/docker-env.env"
    --entrypoint="/bin/bash"
  )
  if _ai_docker_should_use_host_network; then
    docker_args+=(--network="host")
  fi
  if _ai_docker_should_mount_localtime; then
    docker_args+=(-v "/etc/localtime:/etc/localtime:ro")
  fi
  docker_args+=(
    -v "$CODEX_CONFIG_PATH:/root/.codex"
    -v "${cwd}:/workspace/${workspace_name}"
    -w "/workspace/${workspace_name}"
    -e "TZ=${tz_value}"
    "$CODEX_IMAGE_NAME"
    -c ". /root/.nvm/nvm.sh && screen codex auth"
  )

  docker run "${docker_args[@]}"
}

antigravity-docker-build() {
  # Accept optional flag: --no-cache
  local no_cache_flag=""
  if [ "${1-}" = "--no-cache" ]; then
    no_cache_flag="--no-cache"
    shift
  fi
  if [ -n "${1-}" ]; then
    echo "Usage: antigravity-docker-build [--no-cache]" >&2
    return 2
  fi
  if [ -z "$AI_DOCKER_REPO_DIR" ]; then
    echo "Failed to locate repository directory for docker build." >&2
    return 1
  fi
  echo "Building Docker image '$ANTIGRAVITY_IMAGE_NAME' from: $AI_DOCKER_REPO_DIR (Dockerfile.antigravity)" >&2
  local old_image_id
  old_image_id=$(docker images -q "$ANTIGRAVITY_IMAGE_NAME" 2>/dev/null)

  if docker build --pull ${no_cache_flag} -f "$AI_DOCKER_REPO_DIR/Dockerfile.antigravity" -t "$ANTIGRAVITY_IMAGE_NAME" "$AI_DOCKER_REPO_DIR"; then
    if [ -n "$old_image_id" ]; then
      local new_image_id
      new_image_id=$(docker images -q "$ANTIGRAVITY_IMAGE_NAME" 2>/dev/null)
      if [ "$old_image_id" != "$new_image_id" ]; then
        echo "Cleaning up previous image version ($old_image_id)..." >&2
        docker rmi "$old_image_id" 2>/dev/null || true
      fi
    fi
  else
    return $?
  fi
}

antigravity-docker-shell() {
  local cwd
  if [ -n "${1-}" ]; then
    if [ ! -d "$1" ]; then
      echo "Error: Directory '$1' does not exist." >&2
      return 1
    fi
    cwd=$(cd "$1" && pwd)
  else
    cwd="$(pwd)"
  fi

  _ai_docker_load_profile "" "$cwd"
  _ai_docker_update_recents "$cwd"

  if [ "$cwd" = "$HOME" ]; then
    echo "⚠️ Warning: You are running antigravity-docker-shell from your HOME directory." >&2
    echo "This will mount your entire HOME into the container workspace." >&2
    printf "Proceed with mounting HOME? [y/N]: " >&2
    IFS= read -r confirm
    case "$confirm" in
      [yY]|[yY][eE][sS]) ;;
      *) echo "Canceled." >&2; return 1 ;;
    esac
  fi


  if [ "${AI_DOCKER_TERM_TITLE_ENABLE}" = "1" ]; then
    local _antigravity_title="antigravity+$(basename "${cwd}")"
    if [ -n "${ITERM_SESSION_ID-}" ] || [ "${TERM_PROGRAM-}" = "iTerm.app" ]; then
      if command -v base64 >/dev/null 2>&1; then
        printf '\033]1337;SetUserVar=%s=%s\007' "JOB_NAME" "$(printf "%s" "${_antigravity_title}" | base64)" 2>/dev/null || true
      fi
    fi
    # OSC 1: icon name (many terminals use this as a title source)
    printf '\033]1;%s\007' "${_antigravity_title}" 2>/dev/null || true
    # OSC 0: window title (tab title)
    printf '\033]0;%s\007' "${_antigravity_title}" 2>/dev/null || true
  fi

  local workspace_name
  workspace_name="$(basename "${cwd}")"
  local tz_value
  tz_value="$(_ai_docker_detect_tz)"

  local docker_args=(
    --rm -it
    --env-file "$ANTIGRAVITY_CONFIG_PATH/docker-env.env"
    --entrypoint "/bin/bash"
  )
  if _ai_docker_should_mount_localtime; then
    docker_args+=(-v "/etc/localtime:/etc/localtime:ro")
  fi
  if [ -f "$HOME/.gitconfig" ]; then
    docker_args+=(-v "$HOME/.gitconfig:/root/.gitconfig:ro")
  fi
  if [ -f "$HOME/.config/git/config" ]; then
    docker_args+=(-v "$HOME/.config/git/config:/root/.config/git/config:ro")
  fi
  docker_args+=(
    -v "$ANTIGRAVITY_CONFIG_PATH:/root/.gemini"
    -v "${cwd}:/workspace/${workspace_name}"
    -w "/workspace/${workspace_name}"
    -e "TZ=${tz_value}"
    -e "TERM=${TERM:-xterm-256color}"
    -e "TMUX_SESSION=${workspace_name}"
    -e "AI_DOCKER_PROFILE=${AI_DOCKER_PROFILE}"
    -e AI_NAME=antigravity
    -e AI_COMMAND=agy
    "$ANTIGRAVITY_IMAGE_NAME"
    -lc "start-tmux-layout"
  )

  docker run "${docker_args[@]}"
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
  if [ -z "$AI_DOCKER_REPO_DIR" ]; then
    echo "Failed to locate repository directory for docker build." >&2
    return 1
  fi
  echo "Building Docker image '$CLAUDE_IMAGE_NAME' from: $AI_DOCKER_REPO_DIR (Dockerfile.claude)" >&2
  local old_image_id
  old_image_id=$(docker images -q "$CLAUDE_IMAGE_NAME" 2>/dev/null)

  if docker build --pull ${no_cache_flag} -f "$AI_DOCKER_REPO_DIR/Dockerfile.claude" -t "$CLAUDE_IMAGE_NAME" "$AI_DOCKER_REPO_DIR"; then
    if [ -n "$old_image_id" ]; then
      local new_image_id
      new_image_id=$(docker images -q "$CLAUDE_IMAGE_NAME" 2>/dev/null)
      if [ "$old_image_id" != "$new_image_id" ]; then
        echo "Cleaning up previous image version ($old_image_id)..." >&2
        docker rmi "$old_image_id" 2>/dev/null || true
      fi
    fi
  else
    return $?
  fi
}

claude-docker-shell() {
  local cwd
  if [ -n "${1-}" ]; then
    if [ ! -d "$1" ]; then
      echo "Error: Directory '$1' does not exist." >&2
      return 1
    fi
    cwd=$(cd "$1" && pwd)
  else
    cwd="$(pwd)"
  fi

  _ai_docker_load_profile "" "$cwd"
  _ai_docker_update_recents "$cwd"

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


  if [ "${AI_DOCKER_TERM_TITLE_ENABLE}" = "1" ]; then
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

  local workspace_name
  workspace_name="$(basename "${cwd}")"
  local tz_value
  tz_value="$(_ai_docker_detect_tz)"

  local docker_args=(
    --rm -it
    --env-file "$CLAUDE_CONFIG_PATH/docker-env.env"
    --entrypoint "/bin/bash"
  )
  if _ai_docker_should_mount_localtime; then
    docker_args+=(-v "/etc/localtime:/etc/localtime:ro")
  fi
  if [ -f "$HOME/.gitconfig" ]; then
    docker_args+=(-v "$HOME/.gitconfig:/root/.gitconfig:ro")
  fi
  if [ -f "$HOME/.config/git/config" ]; then
    docker_args+=(-v "$HOME/.config/git/config:/root/.config/git/config:ro")
  fi
  docker_args+=(
    -v "$CLAUDE_CONFIG_PATH:/root/.claude"
    -v "${cwd}:/workspace/${workspace_name}"
    -w "/workspace/${workspace_name}"
    -e "TZ=${tz_value}"
    -e "TERM=${TERM:-xterm-256color}"
    -e "TMUX_SESSION=${workspace_name}"
    -e "AI_DOCKER_PROFILE=${AI_DOCKER_PROFILE}"
    -e AI_NAME=claude
    -e AI_COMMAND=claude
    "$CLAUDE_IMAGE_NAME"
    -lc "ln -sf /root/.claude/claude.json /root/.claude.json; start-tmux-layout"
  )

  docker run "${docker_args[@]}"
}

opencode-docker-build() {
  # Accept optional flag: --no-cache
  local no_cache_flag=""
  if [ "${1-}" = "--no-cache" ]; then
    no_cache_flag="--no-cache"
    shift
  fi
  if [ -n "${1-}" ]; then
    echo "Usage: opencode-docker-build [--no-cache]" >&2
    return 2
  fi
  if [ -z "$AI_DOCKER_REPO_DIR" ]; then
    echo "Failed to locate repository directory for docker build." >&2
    return 1
  fi
  echo "Building Docker image '$OPENCODE_IMAGE_NAME' from: $AI_DOCKER_REPO_DIR (Dockerfile.opencode)" >&2
  local old_image_id
  old_image_id=$(docker images -q "$OPENCODE_IMAGE_NAME" 2>/dev/null)

  if docker build --pull ${no_cache_flag} -f "$AI_DOCKER_REPO_DIR/Dockerfile.opencode" -t "$OPENCODE_IMAGE_NAME" "$AI_DOCKER_REPO_DIR"; then
    if [ -n "$old_image_id" ]; then
      local new_image_id
      new_image_id=$(docker images -q "$OPENCODE_IMAGE_NAME" 2>/dev/null)
      if [ "$old_image_id" != "$new_image_id" ]; then
        echo "Cleaning up previous image version ($old_image_id)..." >&2
        docker rmi "$old_image_id" 2>/dev/null || true
      fi
    fi
  else
    return $?
  fi
}

docker-ai-build-all() {
  codex-docker-build --no-cache || return $?
  antigravity-docker-build --no-cache || return $?
  opencode-docker-build --no-cache || return $?
  claude-docker-build --no-cache || return $?
}

opencode-docker-shell() {
  local cwd
  if [ -n "${1-}" ]; then
    if [ ! -d "$1" ]; then
      echo "Error: Directory '$1' does not exist." >&2
      return 1
    fi
    cwd=$(cd "$1" && pwd)
  else
    cwd="$(pwd)"
  fi

  _ai_docker_load_profile "" "$cwd"
  _ai_docker_update_recents "$cwd"

  if [ "$cwd" = "$HOME" ]; then
    echo "⚠️ Warning: You are running opencode-docker-shell from your HOME directory." >&2
    echo "This will mount your entire HOME into the container workspace." >&2
    printf "Proceed with mounting HOME? [y/N]: " >&2
    IFS= read -r confirm
    case "$confirm" in
      [yY]|[yY][eE][sS]) ;;
      *) echo "Canceled." >&2; return 1 ;;
    esac
  fi


  if [ "${AI_DOCKER_TERM_TITLE_ENABLE}" = "1" ]; then
    local _opencode_title="opencode+$(basename "${cwd}")"
    if [ -n "${ITERM_SESSION_ID-}" ] || [ "${TERM_PROGRAM-}" = "iTerm.app" ]; then
      if command -v base64 >/dev/null 2>&1; then
        printf '\033]1337;SetUserVar=%s=%s\007' "JOB_NAME" "$(printf "%s" "${_opencode_title}" | base64)" 2>/dev/null || true
      fi
    fi
    # OSC 1: icon name (many terminals use this as a title source)
    printf '\033]1;%s\007' "${_opencode_title}" 2>/dev/null || true
    # OSC 0: window title (tab title)
    printf '\033]0;%s\007' "${_opencode_title}" 2>/dev/null || true
  fi

  local workspace_name
  workspace_name="$(basename "${cwd}")"
  local tz_value
  tz_value="$(_ai_docker_detect_tz)"

  local docker_args=(
    --rm -it
    --env-file "$OPENCODE_DOCKER_DIR/docker-env.env"
    --entrypoint "/bin/bash"
  )
  if _ai_docker_should_mount_localtime; then
    docker_args+=(-v "/etc/localtime:/etc/localtime:ro")
  fi
  if [ -f "$HOME/.gitconfig" ]; then
    docker_args+=(-v "$HOME/.gitconfig:/root/.gitconfig:ro")
  fi
  if [ -f "$HOME/.config/git/config" ]; then
    docker_args+=(-v "$HOME/.config/git/config:/root/.config/git/config:ro")
  fi
  docker_args+=(
    -v "$OPENCODE_DOCKER_DIR/local:/root/.local"
    -v "$OPENCODE_DOCKER_DIR/config:/root/.config/opencode"
    -v "${cwd}:/workspace/${workspace_name}"
    -w "/workspace/${workspace_name}"
    -e "TZ=${tz_value}"
    -e "TERM=${TERM:-xterm-256color}"
    -e "TMUX_SESSION=${workspace_name}"
    -e "AI_DOCKER_PROFILE=${AI_DOCKER_PROFILE}"
    -e AI_NAME=opencode
    -e AI_COMMAND=opencode
    -e PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
    "$OPENCODE_IMAGE_NAME"
    -lc "start-tmux-layout"
  )

  docker run "${docker_args[@]}"
}

ai-docker() {
  if [ -x "$AI_DOCKER_REPO_DIR/ai-docker.sh" ]; then
    _ai_docker_load_profile "" "$(pwd)"
    "$AI_DOCKER_REPO_DIR/ai-docker.sh" "$@"
    local exit_code=$?
    _ai_docker_load_profile "" "$(pwd)"
    return $exit_code
  else
    echo "Error: ai-docker.sh not found or not executable in $AI_DOCKER_REPO_DIR" >&2
    return 1
  fi
}

ai-docker-deactivate() {
  unset -f _ai_docker_migrate_legacy _ai_docker_get_project_profile _ai_docker_set_project_profile _ai_docker_load_profile ai-docker-profile _ai_docker_update_recents _ai_docker_is_linux_host _ai_docker_should_mount_localtime _ai_docker_detect_tz _ai_docker_should_use_host_network codex-docker-build codex-docker-shell codex-auth-docker-run antigravity-docker-build antigravity-docker-shell claude-docker-build claude-docker-shell opencode-docker-build opencode-docker-shell docker-ai-build-all ai-docker ai-docker-deactivate
}
