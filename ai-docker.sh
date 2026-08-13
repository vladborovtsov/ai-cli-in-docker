#!/usr/bin/env bash
# Interactive Terminal User Interface (TUI) for AI CLI in Docker
# Zero-dependency, pure Bash implementation.
set -euo pipefail

# Determine repository root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the existing activate.sh to reuse Docker helper functions
if [ -f "$SCRIPT_DIR/activate.sh" ]; then
  # We temporarily disable pipefail if sourcing might have minor warnings
  set +e
  source "$SCRIPT_DIR/activate.sh"
  set -e
  _ai_docker_migrate_project_ssh_settings
else
  echo "Error: activate.sh not found in $SCRIPT_DIR" >&2
  exit 1
fi

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Get the formatted directory path for docker mounts
get_mount_path() {
  builtin echo "${active_mount_path}"
}

activate_workspace() {
  local target_path="$1"
  if [ -z "$target_path" ] || [ ! -d "$target_path" ]; then
    return 1
  fi
  active_mount_path=$(cd "$target_path" 2>/dev/null && pwd || echo "$target_path")
  
  if [ "$active_mount_path" != "$HOME" ]; then
    local mapped
    mapped=$(_ai_docker_get_project_profile "$active_mount_path")
    if [ -n "$mapped" ]; then
      echo "$mapped" > "$HOME/.ai-docker-active-profile"
      _ai_docker_load_profile "$mapped" "$active_mount_path"
    else
      local active="${AI_DOCKER_PROFILE:-default}"
      _ai_docker_set_project_profile "$active_mount_path" "$active"
      _ai_docker_load_profile "$active" "$active_mount_path"
    fi
  fi
}

# Helper to repeat a character N times
repeat_char() {
  local char="$1"
  local count="$2"
  local val
  builtin printf -v val "%${count}s" ""
  builtin echo -n "${val// /$char}"
}

# Helper to format and truncate paths for display
format_path() {
  local path="$1"
  local max_len=55
  local display
  if [ "$path" = "$HOME" ]; then
    display="~"
  elif [ "${path#$HOME/}" != "$path" ]; then
    display="~/${path#$HOME/}"
  else
    display="$path"
  fi
  if [ "${#display}" -gt "$max_len" ]; then
    local half=$(( (max_len - 5) / 2 ))
    display="${display:0:$half}...${display: -half}"
  fi
  builtin echo "${display}"
}

# Check if a Docker image is built
check_image_built() {
  local image_name="$1"
  if docker images -q "$image_name" >/dev/null 2>&1 && [ -n "$(docker images -q "$image_name" 2>&1)" ]; then
    echo -e "${GREEN}Built${RESET}"
  else
    echo -e "${RED}Not Built${RESET}"
  fi
}

# State variables
LAUNCH_DIR=$(pwd)
RECENTS_FILE="${AI_DOCKER_RECENTS_FILE:-$HOME/.ai-docker-recents}"
active_mount_path=$(cd "$LAUNCH_DIR" 2>/dev/null && pwd || echo "$LAUNCH_DIR")

current_menu="main"
selected_index=0
menu_lines=0
force_clear=1
selected_profile_name=""
profile_action_items=(
  "👉 Activate Profile"
  "✏️  Rename Profile"
  "🗑️  Delete Profile"
  "⬅️  Back to Profile List"
)

# Image status caching variables
claude_built=""
antigravity_built=""
codex_built=""
opencode_built=""

update_image_statuses() {
  claude_built=$(check_image_built "$CLAUDE_IMAGE_NAME")
  antigravity_built=$(check_image_built "$ANTIGRAVITY_IMAGE_NAME")
  codex_built=$(check_image_built "$CODEX_IMAGE_NAME")
  opencode_built=$(check_image_built "$OPENCODE_IMAGE_NAME")
}

# Rendering frame buffering override to eliminate subshells and forks
CAPTURE_OUTPUT=0
FRAME_BUF=""

echo() {
  if [ "${CAPTURE_OUTPUT-0}" -eq 1 ] && [ "${BASH_SUBSHELL-0}" -eq 0 ]; then
    local flag_e=0
    local flag_n=0
    local args=()
    local parsing_opts=1
    for arg in "$@"; do
      if [ "$parsing_opts" -eq 1 ]; then
        if [ "$arg" = "-e" ]; then
          flag_e=1
        elif [ "$arg" = "-n" ]; then
          flag_n=1
        elif [ "$arg" = "-ne" ] || [ "$arg" = "-en" ]; then
          flag_e=1
          flag_n=1
        else
          parsing_opts=0
          args+=("$arg")
        fi
      else
        args+=("$arg")
      fi
    done
    
    local formatted
    if [ "$flag_e" -eq 1 ]; then
      builtin printf -v formatted "%b" "${args[*]-}"
    else
      builtin printf -v formatted "%s" "${args[*]-}"
    fi
    
    if [ "$flag_n" -eq 0 ]; then
      formatted+="
"
    fi
    FRAME_BUF+="$formatted"
  else
    builtin echo "$@"
  fi
}

printf() {
  if [ "${CAPTURE_OUTPUT-0}" -eq 1 ] && [ "${BASH_SUBSHELL-0}" -eq 0 ]; then
    local formatted
    builtin printf -v formatted "$@"
    FRAME_BUF+="$formatted"
  else
    builtin printf "$@"
  fi
}

# Workspace selection items
workspace_items=()
workspace_paths=()

load_workspace_menu() {
  RECENTS_FILE="${AI_DOCKER_RECENTS_FILE:-$HOME/.ai-docker-recents}"
  workspace_items=()
  workspace_paths=()

  # 1. Current directory
  local launch_dir
  launch_dir=$(cd "$LAUNCH_DIR" 2>/dev/null && pwd || builtin echo "$LAUNCH_DIR")
  local launch_profile=""
  if [ "$launch_dir" != "$HOME" ]; then
    local p_prof
    p_prof=$(_ai_docker_get_project_profile "$launch_dir")
    launch_profile=" (profile: ${p_prof:-default})"
  fi
  local formatted_launch_dir
  formatted_launch_dir=$(format_path "$launch_dir")
  workspace_items+=("📍 Current: ${formatted_launch_dir}${launch_profile}")
  workspace_paths+=("$launch_dir")

  # 2. Custom path option
  workspace_items+=("✏️  Enter Custom Path...")
  workspace_paths+=("CUSTOM")

  workspace_items+=("──────────────────────────────────────────────────")
  workspace_paths+=("DIVIDER")

  # 3. Recent directories from file
  if [ -f "$RECENTS_FILE" ]; then
    while IFS= read -r dir || [ -n "$dir" ]; do
      if [ -n "$dir" ] && [ -d "$dir" ]; then
        local resolved
        resolved=$(cd "$dir" 2>/dev/null && pwd || builtin echo "$dir")
        if [ "$resolved" != "$launch_dir" ]; then
          local r_profile=""
          if [ "$resolved" != "$HOME" ]; then
            local p_prof
            p_prof=$(_ai_docker_get_project_profile "$resolved")
            r_profile=" (profile: ${p_prof:-default})"
          fi
          local formatted_resolved
          formatted_resolved=$(format_path "$resolved")
          workspace_items+=("🕒 Recent: ${formatted_resolved}${r_profile}")
          workspace_paths+=("$resolved")
        fi
      fi
    done < "$RECENTS_FILE"
  fi

  workspace_items+=("⬅️  Back to Main Menu")
  workspace_paths+=("BACK")
}

# Recent projects selection items
recents_items=()
recents_paths=()

load_recents_menu() {
  RECENTS_FILE="${AI_DOCKER_RECENTS_FILE:-$HOME/.ai-docker-recents}"
  recents_items=()
  recents_paths=()

  local raw_dirs=()
  if [ -f "$RECENTS_FILE" ]; then
    while IFS= read -r dir || [ -n "$dir" ]; do
      if [ -n "$dir" ] && [ -d "$dir" ]; then
        raw_dirs+=("$dir")
      fi
    done < "$RECENTS_FILE"
  fi

  local map_file="$HOME/.ai-docker-profiles/project-profiles"
  if [ -f "$map_file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [[ "$line" =~ ^# ]] && continue
      [ -z "$line" ] && continue
      local p_path="${line%:*}"
      if [ -n "$p_path" ] && [ -d "$p_path" ]; then
        raw_dirs+=("$p_path")
      fi
    done < "$map_file"
  fi

  local max_recents="${AI_DOCKER_MAX_RECENTS:-30}"
  local seen=()

  for dir in "${raw_dirs[@]}"; do
    if [ "${#recents_items[@]}" -ge "$max_recents" ]; then
      break
    fi
    local resolved
    resolved=$(cd "$dir" 2>/dev/null && pwd || builtin echo "$dir")

    local dup=0
    if [ "${#seen[@]}" -gt 0 ]; then
      for s in "${seen[@]}"; do
        if [ "$s" = "$resolved" ]; then
          dup=1
          break
        fi
      done
    fi

    if [ "$dup" -eq 0 ]; then
      seen+=("$resolved")
      local r_profile=""
      if [ "$resolved" != "$HOME" ]; then
        local p_prof
        p_prof=$(_ai_docker_get_project_profile "$resolved")
        r_profile=" (profile: ${p_prof:-default})"
      fi
      local formatted_resolved
      formatted_resolved=$(format_path "$resolved")
      if [ "$resolved" = "$active_mount_path" ]; then
        recents_items+=("🕒 ${formatted_resolved}${r_profile} (Active)")
      else
        recents_items+=("🕒 ${formatted_resolved}${r_profile}")
      fi
      recents_paths+=("$resolved")
    fi
  done

  if [ "${#recents_items[@]}" -gt 0 ]; then
    recents_items+=("──────────────────────────────────────────────────")
    recents_paths+=("DIVIDER")
  fi

  recents_items+=("⬅️  Back to Main Menu")
  recents_paths+=("BACK")
}

# Menu definition lists
load_main_menu() {
  local ssh_state="Disabled"
  if [ "$(_ai_docker_get_project_ssh_agent "$active_mount_path")" = "1" ]; then
    ssh_state="Enabled"
  fi

  main_items=(
    "💬 Launch Claude Code"
    "🤖 Launch Claude Code (Auto Mode)"
    "💀 Launch Claude Code (Dangerous Mode)"
    "💬 Launch Antigravity CLI"
    "💬 Launch OpenAI Codex"
    "💬 Launch OpenCode"
    "──────────────────────────────────────────────────"
    "📁 Change Workspace Directory..."
    "🕒 Recent Projects..."
    "👤 Switch Active Profile (Current: ${AI_DOCKER_PROFILE:-default})"
    "🔑 Project SSH Agent: [ ${ssh_state} ]"
    "──────────────────────────────────────────────────"
    "🛠️  Rebuild/Update Images..."
    "⚙️  Edit Environment Files..."
    "🧹 Clean up Docker Space..."
    "🚪 Exit"
  )
}

profile_items=()
profile_names=()

load_profile_menu() {
  profile_items=()
  profile_names=()

  # Always include default
  profile_names+=("default")

  local ignore_dir="$HOME/.ai-docker-profiles"
  if [ -d "$ignore_dir" ]; then
    for d in "$ignore_dir"/*; do
      if [ -d "$d" ]; then
        local name
        name=$(basename "$d")
        local found=0
        for existing in "${profile_names[@]}"; do
          if [ "$existing" = "$name" ]; then
            found=1
            break
          fi
        done
        if [ "$found" -eq 0 ]; then
          profile_names+=("$name")
        fi
      fi
    done
  fi

  for name in "${profile_names[@]}"; do
    if [ "$name" = "${AI_DOCKER_PROFILE:-default}" ]; then
      profile_items+=("👤 $name (Active)")
    else
      profile_items+=("👤 $name")
    fi
  done

  profile_items+=("──────────────────────────────────────────────────")
  profile_names+=("DIVIDER")

  profile_items+=("➕ Create New Profile...")
  profile_names+=("CREATE")

  profile_items+=("⬅️ Back to Main Menu")
  profile_names+=("BACK")
}

build_items=(
  "📦 Claude Code (Dockerfile.claude - No Cache)"
  "📦 Antigravity CLI (Dockerfile.antigravity - No Cache)"
  "📦 OpenAI Codex (Dockerfile.codex - No Cache)"
  "📦 OpenCode     (Dockerfile.opencode - No Cache)"
  "🔄 Rebuild ALL  (No Cache)"
  "⬅️ Back to Main Menu"
)

config_items=(
  "📝 Claude Env   (docker-env.env)"
  "📝 Antigravity Env (docker-env.env)"
  "📝 Codex Env    (docker-env.env)"
  "📝 OpenCode Env (docker-env.env)"
  "⬅️ Back to Main Menu"
)

cleanup_items=(
  "🗑️  Prune Stopped Containers"
  "🗑️  Remove Dangling Images"
  "🗑️  Remove ALL Project Images"
  "⬅️ Back to Main Menu"
)

# Helper to get the length of the active menu
get_menu_length() {
  case "$current_menu" in
    main) load_main_menu; echo "${#main_items[@]}" ;;
    profile) load_profile_menu; echo "${#profile_items[@]}" ;;
    profile_actions) echo "${#profile_action_items[@]}" ;;
    build) echo "${#build_items[@]}" ;;
    config) echo "${#config_items[@]}" ;;
    cleanup) echo "${#cleanup_items[@]}" ;;
    workspace) load_workspace_menu; echo "${#workspace_items[@]}" ;;
    recents) load_recents_menu; echo "${#recents_items[@]}" ;;
  esac
}

# Render the active menu
render_menu() {
  local selected="$1"
  local lines_printed=0

  # Calculate layout widths
  local mount_path="${active_mount_path}"
  local base_dir
  if command -v _ai_docker_get_unique_workspace_name >/dev/null 2>&1; then
    base_dir=$(_ai_docker_get_unique_workspace_name "${mount_path}")
  else
    base_dir="${mount_path##*/}"
  fi
  if [ -z "$base_dir" ] || [ "$base_dir" = "." ] || [ "$base_dir" = "/" ]; then
    base_dir="project"
  fi

  # Fixed width to fit standard terminals and prevent horizontal layout wrapping
  local inside_width=80

  # Build header borders and title padding dynamically
  local title_text="🤖 AI CLI IN DOCKER - CONTROL TUI"
  local title_width=33
  local padding=$((inside_width - title_width))
  local left_pad=$((padding / 2))
  local right_pad=$((padding - left_pad))
  
  local left_spaces
  builtin printf -v left_spaces "%${left_pad}s" ""
  local right_spaces
  builtin printf -v right_spaces "%${right_pad}s" ""
  local top_border=$(repeat_char "─" "$inside_width")

  # Header block
  echo -e "${BOLD}┌${top_border}┐${RESET}"
  echo -e "${BOLD}│${left_spaces}${title_text}${right_spaces}│${RESET}"
  echo -e "${BOLD}└${top_border}┘${RESET}"
  
  # Global Context Info (Workspace Path and Profile Name)
  local display_path
  if [ "$mount_path" = "$HOME" ]; then
    display_path="~"
  elif [ "${mount_path#$HOME/}" != "$mount_path" ]; then
    display_path="~/${mount_path#$HOME/}"
  else
    display_path="$mount_path"
  fi
  echo -e "  ${BOLD}Workspace:${RESET} ${display_path} (${base_dir})"
  echo -e "  ${BOLD}Profile:  ${RESET} ${GREEN}${AI_DOCKER_PROFILE:-default}${RESET}"
  echo ""
  lines_printed=7

  case "$current_menu" in
    main)
      load_main_menu
      echo -e "  ${BOLD}Select an action to launch or manage:${RESET}"
      echo ""
      lines_printed=$((lines_printed + 2))

      local statuses=(
        "[$claude_built]"
        "[$claude_built]"
        "[$claude_built]"
        "[$antigravity_built]"
        "[$codex_built]"
        "[$opencode_built]"
        ""
        ""
        ""
        ""
        ""
        ""
        ""
        ""
      )

      for i in "${!main_items[@]}"; do
        local item_text="${main_items[$i]}"
        if [ "$i" -lt 6 ]; then
          if [ "$i" -eq "$selected" ]; then
            printf "  ${CYAN}▸${RESET} ${BOLD}%-32s${RESET} %s\n" "$item_text" "${statuses[$i]}"
          else
            printf "    %-32s %s\n" "$item_text" "${statuses[$i]}"
          fi
        else
          if [ "$i" -eq "$selected" ]; then
            if [[ "$item_text" == ──* ]]; then
              local div_width=$((inside_width - 4))
              local divider_line=$(repeat_char "─" "$div_width")
              printf "  %s\n" "$divider_line"
            else
              printf "  ${CYAN}▸${RESET} ${BOLD}%s${RESET}\n" "$item_text"
            fi
          else
            if [[ "$item_text" == ──* ]]; then
              local div_width=$((inside_width - 4))
              local divider_line=$(repeat_char "─" "$div_width")
              printf "  %s\n" "$divider_line"
            else
              printf "    %s\n" "$item_text"
            fi
          fi
        fi
        lines_printed=$((lines_printed + 1))
      done
      ;;

    profile)
      echo -e "  ${BOLD}Select or change the active profile:${RESET}"
      echo ""
      lines_printed=$((lines_printed + 2))

      load_profile_menu

      for i in "${!profile_items[@]}"; do
        local item_text="${profile_items[$i]}"
        if [ "$i" -eq "$selected" ]; then
          if [[ "$item_text" == ──* ]]; then
            local div_width=$((inside_width - 4))
            local divider_line=$(repeat_char "─" "$div_width")
            printf "  %s\n" "$divider_line"
          else
            printf "  ${CYAN}▸${RESET} ${BOLD}%s${RESET}\n" "$item_text"
          fi
        else
          if [[ "$item_text" == ──* ]]; then
            local div_width=$((inside_width - 4))
            local divider_line=$(repeat_char "─" "$div_width")
            printf "  %s\n" "$divider_line"
          else
            printf "    %s\n" "$item_text"
          fi
        fi
        lines_printed=$((lines_printed + 1))
      done
      ;;

    build)
      echo -e "  ${BOLD}Select an image to build/rebuild:${RESET}"
      echo ""
      lines_printed=$((lines_printed + 2))

      for i in "${!build_items[@]}"; do
        if [ "$i" -eq "$selected" ]; then
          printf "  ${CYAN}▸${RESET} ${BOLD}%s${RESET}\n" "${build_items[$i]}"
        else
          printf "    %s\n" "${build_items[$i]}"
        fi
        lines_printed=$((lines_printed + 1))
      done
      ;;

    config)
      echo -e "  ${BOLD}Select an environment config to edit:${RESET}"
      echo ""
      lines_printed=$((lines_printed + 2))

      for i in "${!config_items[@]}"; do
        if [ "$i" -eq "$selected" ]; then
          printf "  ${CYAN}▸${RESET} ${BOLD}%s${RESET}\n" "${config_items[$i]}"
        else
          printf "    %s\n" "${config_items[$i]}"
        fi
        lines_printed=$((lines_printed + 1))
      done
      ;;

    cleanup)
      echo -e "  ${BOLD}Select a cleanup action:${RESET}"
      echo ""
      lines_printed=$((lines_printed + 2))

      for i in "${!cleanup_items[@]}"; do
        if [ "$i" -eq "$selected" ]; then
          printf "  ${CYAN}▸${RESET} ${BOLD}%s${RESET}\n" "${cleanup_items[$i]}"
        else
          printf "    %s\n" "${cleanup_items[$i]}"
        fi
        lines_printed=$((lines_printed + 1))
      done
      ;;

    workspace)
      echo -e "  ${BOLD}Select or change the active workspace directory:${RESET}"
      echo ""
      lines_printed=$((lines_printed + 2))

      load_workspace_menu

      for i in "${!workspace_items[@]}"; do
        local item_text="${workspace_items[$i]}"
        if [ "$i" -eq "$selected" ]; then
          if [[ "$item_text" == ──* ]]; then
            local div_width=$((inside_width - 4))
            local divider_line=$(repeat_char "─" "$div_width")
            printf "  %s\n" "$divider_line"
          else
            printf "  ${CYAN}▸${RESET} ${BOLD}%s${RESET}\n" "$item_text"
          fi
        else
          if [[ "$item_text" == ──* ]]; then
            local div_width=$((inside_width - 4))
            local divider_line=$(repeat_char "─" "$div_width")
            printf "  %s\n" "$divider_line"
          else
            printf "    %s\n" "$item_text"
          fi
        fi
        lines_printed=$((lines_printed + 1))
      done
      ;;

    recents)
      echo -e "  ${BOLD}Select a recent project to set as active workspace:${RESET}"
      echo ""
      lines_printed=$((lines_printed + 2))

      load_recents_menu

      for i in "${!recents_items[@]}"; do
        local item_text="${recents_items[$i]}"
        if [ "$i" -eq "$selected" ]; then
          if [[ "$item_text" == ──* ]]; then
            local div_width=$((inside_width - 4))
            local divider_line=$(repeat_char "─" "$div_width")
            printf "  %s\n" "$divider_line"
          else
            printf "  ${CYAN}▸${RESET} ${BOLD}%s${RESET}\n" "$item_text"
          fi
        else
          if [[ "$item_text" == ──* ]]; then
            local div_width=$((inside_width - 4))
            local divider_line=$(repeat_char "─" "$div_width")
            printf "  %s\n" "$divider_line"
          else
            printf "    %s\n" "$item_text"
          fi
        fi
        lines_printed=$((lines_printed + 1))
      done
      ;;

    profile_actions)
      echo -e "  ${BOLD}Profile Actions for: ${GREEN}${selected_profile_name}${RESET}"
      echo ""
      lines_printed=$((lines_printed + 2))

      for i in "${!profile_action_items[@]}"; do
        if [ "$i" -eq "$selected" ]; then
          printf "  ${CYAN}▸${RESET} ${BOLD}%s${RESET}\n" "${profile_action_items[$i]}"
        else
          printf "    %s\n" "${profile_action_items[$i]}"
        fi
        lines_printed=$((lines_printed + 1))
      done
      ;;
  esac

  # Footer block
  echo ""
  local footer_width=$((inside_width + 2))
  local footer_line=$(repeat_char "─" "$footer_width")
  echo -e "${BOLD}${footer_line}${RESET}"
  echo -e " [Use ↑/↓ or j/k to navigate, Enter to select, Q/Esc to go back/exit]\033[J"
  lines_printed=$((lines_printed + 3))

  menu_lines="$lines_printed"
}

# Navigate through menu indices (skips visual dividers)
move_selection() {
  local dir="$1"
  local len=$(get_menu_length)

  if [ "$dir" = "UP" ]; then
    selected_index=$(( (selected_index - 1 + len) % len ))
    # Skip dividers
    if [ "$current_menu" = "main" ] && [[ "${main_items[$selected_index]}" == ──* ]]; then
      selected_index=$(( (selected_index - 1 + len) % len ))
    elif [ "$current_menu" = "workspace" ] && [[ "${workspace_items[$selected_index]}" == ──* ]]; then
      selected_index=$(( (selected_index - 1 + len) % len ))
    elif [ "$current_menu" = "recents" ] && [[ "${recents_items[$selected_index]}" == ──* ]]; then
      selected_index=$(( (selected_index - 1 + len) % len ))
    elif [ "$current_menu" = "profile" ] && [[ "${profile_items[$selected_index]}" == ──* ]]; then
      selected_index=$(( (selected_index - 1 + len) % len ))
    fi
  else
    selected_index=$(( (selected_index + 1) % len ))
    # Skip dividers
    if [ "$current_menu" = "main" ] && [[ "${main_items[$selected_index]}" == ──* ]]; then
      selected_index=$(( (selected_index + 1) % len ))
    elif [ "$current_menu" = "workspace" ] && [[ "${workspace_items[$selected_index]}" == ──* ]]; then
      selected_index=$(( (selected_index + 1) % len ))
    elif [ "$current_menu" = "recents" ] && [[ "${recents_items[$selected_index]}" == ──* ]]; then
      selected_index=$(( (selected_index + 1) % len ))
    elif [ "$current_menu" = "profile" ] && [[ "${profile_items[$selected_index]}" == ──* ]]; then
      selected_index=$(( (selected_index + 1) % len ))
    fi
  fi
}

# Launch container or build first if not available
launch_tool() {
  local image_name="$1"
  local build_func="$2"
  local shell_func="$3"

  # Detect image existence
  if ! docker images -q "$image_name" >/dev/null 2>&1 || [ -z "$(docker images -q "$image_name" 2>&1)" ]; then
    tput cnorm
    clear
    echo -e "${YELLOW}Warning: Image '$image_name' is not built yet.${RESET}"
    read -rp "Would you like to build it now? [Y/n] " choice
    case "$choice" in
      [nN]|[nN][oO])
        tput civis
        force_clear=1
        return
        ;;
      *)
        echo "Building image..."
        if ! $build_func; then
          echo -e "${RED}Build failed.${RESET}"
          read -rp "Press [Enter] to return to menu..."
          tput civis
          force_clear=1
          return
        fi
        ;;
    esac
  fi

  # Launch Docker shell script
  tput cnorm
  clear
  echo "Launching container session..."
  echo "Close tmux session or type 'exit' inside the tmux window to return to command line."
  echo ""
  
  # Run function
  local exit_code=0
  $shell_func "$active_mount_path" || exit_code=$?

  exit "$exit_code"
}

# Run build command helper
run_build() {
  tput cnorm
  clear
  echo "Running build command: $*..."
  echo ""
  if "$@"; then
    echo ""
    echo -e "${GREEN}Build completed successfully!${RESET}"
  else
    echo ""
    echo -e "${RED}Build process failed.${RESET}"
  fi
  # Update cached image statuses
  update_image_statuses
  echo ""
  read -rp "Press [Enter] to return to build menu..."
  tput civis
  force_clear=1
}

# Edit environment variables file using host terminal editor
edit_env_file() {
  local file_path="$1"
  local editor="${EDITOR:-nano}"
  
  # Create directory and file if it does not exist
  mkdir -p "$(dirname "$file_path")"
  touch "$file_path"

  tput cnorm
  clear
  "$editor" "$file_path"
  tput civis
  force_clear=1
}

# Perform selected Docker cleanup activity
run_cleanup() {
  local action="$1"
  tput cnorm
  clear
  case "$action" in
    prune_containers)
      echo "Pruning stopped containers..."
      docker container prune -f
      ;;
    prune_images)
      echo "Pruning dangling images..."
      docker image prune -f
      ;;
    remove_all_images)
      echo "Removing all project images..."
      docker rmi -f "$CLAUDE_IMAGE_NAME" "$ANTIGRAVITY_IMAGE_NAME" "$CODEX_IMAGE_NAME" "$OPENCODE_IMAGE_NAME" 2>/dev/null || true
      ;;
  esac
  # Update cached image statuses
  update_image_statuses
  echo ""
  read -rp "Press [Enter] to return to cleanup menu..."
  tput civis
  force_clear=1
}

# Navigate back out of sub-menus
handle_back() {
  if [ "$current_menu" = "profile_actions" ]; then
    current_menu="profile"
    selected_index=0
    force_clear=1
  elif [ "$current_menu" != "main" ]; then
    current_menu="main"
    selected_index=0
    force_clear=1
  else
    exit 0
  fi
}

# Trigger appropriate action based on current state selection
handle_select() {
  case "$current_menu" in
    main)
      case "$selected_index" in
        0) AI_COMMAND="claude --continue || claude" launch_tool "$CLAUDE_IMAGE_NAME" claude-docker-build claude-docker-shell ;;
        1) AI_COMMAND="claude --permission-mode auto --continue || claude --permission-mode auto" launch_tool "$CLAUDE_IMAGE_NAME" claude-docker-build claude-docker-shell ;;
        2) AI_COMMAND="claude --dangerously-skip-permissions --continue || claude --dangerously-skip-permissions" launch_tool "$CLAUDE_IMAGE_NAME" claude-docker-build claude-docker-shell ;;
        3) launch_tool "$ANTIGRAVITY_IMAGE_NAME" antigravity-docker-build antigravity-docker-shell ;;
        4) launch_tool "$CODEX_IMAGE_NAME" codex-docker-build codex-docker-shell ;;
        5) launch_tool "$OPENCODE_IMAGE_NAME" opencode-docker-build opencode-docker-shell ;;
        6) ;; # divider
        7) current_menu="workspace"; selected_index=0; force_clear=1 ;;
        8) current_menu="recents"; selected_index=0; force_clear=1 ;;
        9) current_menu="profile"; selected_index=0; force_clear=1 ;;
        10)
          local cur_ssh
          cur_ssh=$(_ai_docker_get_project_ssh_agent "$active_mount_path")
          if [ "$cur_ssh" = "1" ]; then
            _ai_docker_set_project_ssh_agent "$active_mount_path" 0
          else
            _ai_docker_set_project_ssh_agent "$active_mount_path" 1
          fi
          load_main_menu
          force_clear=1
          ;;
        11) ;; # divider
        12) current_menu="build"; selected_index=0; force_clear=1 ;;
        13) current_menu="config"; selected_index=0; force_clear=1 ;;
        14) current_menu="cleanup"; selected_index=0; force_clear=1 ;;
        15) exit 0 ;;
      esac
      ;;
    profile)
      local name="${profile_names[$selected_index]}"
      case "$name" in
        CREATE)
          tput cnorm
          clear
          echo -e "${BOLD}Create New Profile${RESET}"
          echo "Type a name for the new profile (alphanumeric, dashes, underscores)."
          echo ""
          read -rp "Profile Name: " new_profile_name
          if [ -n "$new_profile_name" ]; then
            new_profile_name=$(echo "$new_profile_name" | tr -cd 'a-zA-Z0-9_-')
            if [ -n "$new_profile_name" ]; then
              echo "$new_profile_name" > "$HOME/.ai-docker-active-profile"
              _ai_docker_load_profile "$new_profile_name"
              RECENTS_FILE="${AI_DOCKER_RECENTS_FILE:-$HOME/.ai-docker-recents}"
              echo -e "${GREEN}Profile '$new_profile_name' created and activated.${RESET}"
            else
              echo -e "${RED}Error: Invalid profile name.${RESET}"
            fi
          else
            echo "Cancelled."
          fi
          sleep 1.5
          tput civis
          force_clear=1
          current_menu="main"
          selected_index=5
          ;;
        DIVIDER)
          ;;
        BACK)
          handle_back
          ;;
        *)
          if [ "$name" = "default" ]; then
            echo "$name" > "$HOME/.ai-docker-active-profile"
            _ai_docker_load_profile "$name" "$active_mount_path"
            if [ "$active_mount_path" != "$HOME" ]; then
              _ai_docker_set_project_profile "$active_mount_path" "$name"
              _ai_docker_update_recents "$active_mount_path"
            fi
            current_menu="main"
            selected_index=5
            force_clear=1
          else
            selected_profile_name="$name"
            current_menu="profile_actions"
            selected_index=0
            force_clear=1
          fi
          ;;
      esac
      ;;
    profile_actions)
      case "$selected_index" in
        0) # Activate
          echo "$selected_profile_name" > "$HOME/.ai-docker-active-profile"
          _ai_docker_load_profile "$selected_profile_name" "$active_mount_path"
          if [ "$active_mount_path" != "$HOME" ]; then
            _ai_docker_set_project_profile "$active_mount_path" "$selected_profile_name"
            _ai_docker_update_recents "$active_mount_path"
          fi
          current_menu="main"
          selected_index=9
          force_clear=1
          ;;
        1) # Rename
          tput cnorm
          clear
          echo -e "${BOLD}Rename Profile: $selected_profile_name${RESET}"
          echo "Type a new name for the profile (alphanumeric, dashes, underscores)."
          echo ""
          read -rp "New Name: " new_name
          if [ -n "$new_name" ]; then
            new_name=$(echo "$new_name" | tr -cd 'a-zA-Z0-9_-')
            if [ -n "$new_name" ] && [ "$new_name" != "default" ]; then
              local old_dir="$HOME/.ai-docker-profiles/$selected_profile_name"
              local new_dir="$HOME/.ai-docker-profiles/$new_name"
              if [ -d "$old_dir" ]; then
                if [ -d "$new_dir" ]; then
                  echo -e "${RED}Error: Profile '$new_name' already exists.${RESET}"
                  sleep 1.5
                else
                  mv "$old_dir" "$new_dir"
                  if [ "${AI_DOCKER_PROFILE:-default}" = "$selected_profile_name" ]; then
                    echo "$new_name" > "$HOME/.ai-docker-active-profile"
                  fi
                  # Update mapping file
                  local map_file="$HOME/.ai-docker-profiles/project-profiles"
                  if [ -f "$map_file" ]; then
                    local tmp_map="${map_file}.tmp"
                    while IFS= read -r line || [ -n "$line" ]; do
                      if [ -n "$line" ]; then
                        local p_path="${line%:*}"
                        local p_profile="${line##*:}"
                        if [ "$p_profile" = "$selected_profile_name" ]; then
                          echo "${p_path}:${new_name}" >> "$tmp_map"
                        else
                          echo "$line" >> "$tmp_map"
                        fi
                      fi
                    done < "$map_file"
                    if [ -f "$tmp_map" ]; then
                      mv "$tmp_map" "$map_file"
                    else
                      > "$map_file"
                    fi
                  fi
                  _ai_docker_load_profile "" "$active_mount_path"
                  echo -e "${GREEN}Profile renamed to '$new_name'.${RESET}"
                  sleep 1.5
                fi
              else
                if [ "${AI_DOCKER_PROFILE:-default}" = "$selected_profile_name" ]; then
                  echo "$new_name" > "$HOME/.ai-docker-active-profile"
                fi
                # Update mapping file
                local map_file="$HOME/.ai-docker-profiles/project-profiles"
                if [ -f "$map_file" ]; then
                  local tmp_map="${map_file}.tmp"
                  while IFS= read -r line || [ -n "$line" ]; do
                    if [ -n "$line" ]; then
                      local p_path="${line%:*}"
                      local p_profile="${line##*:}"
                      if [ "$p_profile" = "$selected_profile_name" ]; then
                        echo "${p_path}:${new_name}" >> "$tmp_map"
                      else
                        echo "$line" >> "$tmp_map"
                      fi
                    fi
                  done < "$map_file"
                  if [ -f "$tmp_map" ]; then
                    mv "$tmp_map" "$map_file"
                  else
                    > "$map_file"
                  fi
                fi
                _ai_docker_load_profile "" "$active_mount_path"
                echo -e "${GREEN}Profile name updated to '$new_name'.${RESET}"
                sleep 1.5
              fi
            else
              echo -e "${RED}Error: Invalid profile name.${RESET}"
              sleep 1.5
            fi
          else
            echo "Cancelled."
            sleep 1
          fi
          tput civis
          current_menu="profile"
          selected_index=0
          force_clear=1
          ;;
        2) # Delete
          tput cnorm
          clear
          echo -e "${RED}${BOLD}Delete Profile: $selected_profile_name${RESET}"
          echo "Are you sure you want to delete this profile? All settings will be lost."
          echo ""
          read -rp "Type 'yes' to confirm: " confirm
          if [ "$confirm" = "yes" ]; then
            local old_dir="$HOME/.ai-docker-profiles/$selected_profile_name"
            if [ -d "$old_dir" ]; then
              rm -rf "$old_dir"
            fi
            if [ "${AI_DOCKER_PROFILE:-default}" = "$selected_profile_name" ]; then
              echo "default" > "$HOME/.ai-docker-active-profile"
            fi
            local map_file="$HOME/.ai-docker-profiles/project-profiles"
            if [ -f "$map_file" ]; then
              local tmp_map="${map_file}.tmp"
              while IFS= read -r line || [ -n "$line" ]; do
                if [ -n "$line" ]; then
                  local p_path="${line%:*}"
                  local p_profile="${line##*:}"
                  if [ "$p_profile" != "$selected_profile_name" ]; then
                    echo "$line" >> "$tmp_map"
                  fi
                fi
              done < "$map_file"
              if [ -f "$tmp_map" ]; then
                mv "$tmp_map" "$map_file"
              else
                > "$map_file"
              fi
            fi
            _ai_docker_load_profile "" "$active_mount_path"
            echo -e "${GREEN}Profile deleted.${RESET}"
            sleep 1.5
          else
            echo "Cancelled."
            sleep 1
          fi
          tput civis
          current_menu="profile"
          selected_index=0
          force_clear=1
          ;;
        3) # Back
          current_menu="profile"
          selected_index=0
          force_clear=1
          ;;
      esac
      ;;
    build)
      case "$selected_index" in
        0) run_build claude-docker-build --no-cache ;;
        1) run_build antigravity-docker-build --no-cache ;;
        2) run_build codex-docker-build --no-cache ;;
        3) run_build opencode-docker-build --no-cache ;;
        4) run_build docker-ai-build-all ;;
        5) handle_back ;;
      esac
      ;;
    config)
      case "$selected_index" in
        0) edit_env_file "$CLAUDE_CONFIG_PATH/docker-env.env" ;;
        1) edit_env_file "$ANTIGRAVITY_CONFIG_PATH/docker-env.env" ;;
        2) edit_env_file "$CODEX_CONFIG_PATH/docker-env.env" ;;
        3) edit_env_file "$OPENCODE_DOCKER_DIR/docker-env.env" ;;
        4) handle_back ;;
      esac
      ;;
    cleanup)
      case "$selected_index" in
        0) run_cleanup prune_containers ;;
        1) run_cleanup prune_images ;;
        2) run_cleanup remove_all_images ;;
        3) handle_back ;;
      esac
      ;;
    workspace)
      local path="${workspace_paths[$selected_index]}"
      case "$path" in
        CUSTOM)
          tput cnorm
          clear
          echo -e "${BOLD}Enter Custom Workspace Path${RESET}"
          echo "You can type an absolute or relative path to a directory."
          echo ""
          read -rp "Path: " custom_input
          if [ -n "$custom_input" ]; then
            # Expand ~ if present
            custom_input="${custom_input/#\~/$HOME}"
            if [ -d "$custom_input" ]; then
              activate_workspace "$custom_input"
              _ai_docker_update_recents "$active_mount_path"
              echo -e "${GREEN}Active workspace directory set to: $active_mount_path${RESET}"
            else
              echo -e "${RED}Error: Directory '$custom_input' does not exist.${RESET}"
            fi
          else
            echo "Cancelled."
          fi
          sleep 1.5
          tput civis
          force_clear=1
          ;;
        DIVIDER)
          ;;
        BACK)
          handle_back
          ;;
        *)
          if [ -d "$path" ]; then
            activate_workspace "$path"
            _ai_docker_update_recents "$active_mount_path"
            current_menu="main"
            selected_index=0
            force_clear=1
          else
            tput cnorm
            clear
            echo -e "${RED}Error: Directory '$path' no longer exists.${RESET}"
            sleep 1.5
            tput civis
            force_clear=1
          fi
          ;;
      esac
      ;;
    recents)
      local path="${recents_paths[$selected_index]}"
      case "$path" in
        DIVIDER)
          ;;
        BACK)
          handle_back
          ;;
        *)
          if [ -d "$path" ]; then
            activate_workspace "$path"
            _ai_docker_update_recents "$active_mount_path"
            current_menu="main"
            selected_index=0
            force_clear=1
          else
            tput cnorm
            clear
            echo -e "${RED}Error: Directory '$path' no longer exists.${RESET}"
            sleep 1.5
            tput civis
            force_clear=1
          fi
          ;;
      esac
      ;;
  esac
}

# Process raw character inputs (supports arrow keys, Vim motion keys, Esc, and Q)
read_key() {
  local key
  local next_key=""
  # Read single character. Set IFS to empty to preserve spaces/newlines
  IFS= read -rsn1 key
  if [[ "$key" == $'\e' ]]; then
    # Read next two characters if an escape sequence is coming (arrow keys)
    # Using 1-second timeout as macOS default bash (3.2) does not support fractional timeouts
    read -rsn2 -t 1 next_key || true
    key+="$next_key"
  fi
  
  case "$key" in
    $'\e[A'|[kK]) echo "UP" ;;
    $'\e[B'|[jJ]) echo "DOWN" ;;
    "") echo "ENTER" ;;
    $'\e'|[qQ]) echo "QUIT" ;;
    *) echo "NONE" ;;
  esac
}

# Reset cursor state upon script termination
cleanup() {
  tput cnorm
}
trap cleanup EXIT INT TERM

# Start application loop
activate_workspace "$(pwd)"
_ai_docker_update_recents "$(pwd)"
update_image_statuses
tput civis
clear

while true; do
  if [ "$current_menu" = "workspace" ]; then
    load_workspace_menu
  elif [ "$current_menu" = "recents" ]; then
    load_recents_menu
  fi

  # Use the overridden echo/printf buffering (0 subshells, 0 forks)
  FRAME_BUF=""
  CAPTURE_OUTPUT=1
  render_menu "$selected_index"
  CAPTURE_OUTPUT=0

  # Buffer the clear/move and render operations to write them in a single frame
  ESC=$'\e'
  frame_buf=""
  if [ "$force_clear" -eq 1 ]; then
    clear
    force_clear=0
  else
    frame_buf+="${ESC}[H${ESC}[J"
  fi
  frame_buf+="$FRAME_BUF"

  # Print the entire frame in a single stdout write to eliminate terminal flicker
  printf "%s" "$frame_buf"
  
  key=$(read_key)
  case "$key" in
    UP)
      move_selection "UP"
      ;;
    DOWN)
      move_selection "DOWN"
      ;;
    ENTER)
      handle_select
      ;;
    QUIT)
      handle_back
      ;;
    *)
      ;;
  esac
done
