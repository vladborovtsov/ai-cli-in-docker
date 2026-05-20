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

# Helper to repeat a character N times
repeat_char() {
  local char="$1"
  local count="$2"
  local val
  builtin printf -v val "%${count}s" ""
  builtin echo -n "${val// /$char}"
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
RECENTS_FILE="$HOME/.ai-docker-recents"
active_mount_path=$(cd "$LAUNCH_DIR" 2>/dev/null && pwd || echo "$LAUNCH_DIR")

current_menu="main"
selected_index=0
menu_lines=0
force_clear=1

# Image status caching variables
claude_built=""
gemini_built=""
codex_built=""
opencode_built=""

update_image_statuses() {
  claude_built=$(check_image_built "$CLAUDE_IMAGE_NAME")
  gemini_built=$(check_image_built "$GEMINI_IMAGE_NAME")
  codex_built=$(check_image_built "$CODEX_IMAGE_NAME")
  opencode_built=$(check_image_built "$OPENCODE_IMAGE_NAME")
}

# Rendering frame buffering override to eliminate subshells and forks
CAPTURE_OUTPUT=0
FRAME_BUF=""

echo() {
  if [ "${CAPTURE_OUTPUT-0}" -eq 1 ]; then
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
  if [ "${CAPTURE_OUTPUT-0}" -eq 1 ]; then
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
  workspace_items=()
  workspace_paths=()

  # 1. Current directory
  local launch_dir
  launch_dir=$(cd "$LAUNCH_DIR" 2>/dev/null && pwd || builtin echo "$LAUNCH_DIR")
  workspace_items+=("📍 Current Directory: $launch_dir")
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
        # Don't add current directory to recents list in the menu (it's already option 1)
        if [ "$resolved" != "$launch_dir" ]; then
          workspace_items+=("🕒 Recent: $resolved")
          workspace_paths+=("$resolved")
        fi
      fi
    done < "$RECENTS_FILE"
  fi

  workspace_items+=("⬅️  Back to Main Menu")
  workspace_paths+=("BACK")
}

# Menu definition lists
main_items=(
  "💬 Launch Claude Code"
  "💬 Launch Gemini CLI"
  "💬 Launch OpenAI Codex"
  "💬 Launch OpenCode"
  "📁 Change Workspace Directory..."
  "──────────────────────────────────────────────────"
  "🛠️  Rebuild/Update Images..."
  "⚙️  Edit Environment Files..."
  "🧹 Clean up Docker Space..."
  "🚪 Exit"
)

build_items=(
  "📦 Claude Code (Dockerfile.claude)"
  "📦 Gemini CLI   (Dockerfile.gemini)"
  "📦 OpenAI Codex (Dockerfile.codex)"
  "📦 OpenCode     (Dockerfile.opencode)"
  "🔄 Rebuild ALL  (No Cache)"
  "⬅️ Back to Main Menu"
)

config_items=(
  "📝 Claude Env   (docker-env.env)"
  "📝 Gemini Env   (docker-env.env)"
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
    main) echo "${#main_items[@]}" ;;
    build) echo "${#build_items[@]}" ;;
    config) echo "${#config_items[@]}" ;;
    cleanup) echo "${#cleanup_items[@]}" ;;
    workspace) load_workspace_menu; echo "${#workspace_items[@]}" ;;
  esac
}



# Render the active menu
render_menu() {
  local selected="$1"
  local lines_printed=0

  # Calculate layout widths dynamically based on mount mapping length
  local mount_path="${active_mount_path}"
  local base_dir="${mount_path##*/}"
  if [ -z "$base_dir" ] || [ "$base_dir" = "." ] || [ "$base_dir" = "/" ]; then
    base_dir="project"
  fi
  local mount_mapping="(mounts: ${mount_path} -> /workspace/${base_dir})"
  
  local inside_width=$((48 + ${#mount_mapping}))
  if [ "$inside_width" -lt 80 ]; then
    inside_width=80
  fi

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
  echo ""
  lines_printed=4

  case "$current_menu" in
    main)
      echo -e "  ${BOLD}Select an action to launch or manage:${RESET}"
      echo ""
      lines_printed=$((lines_printed + 2))

      local statuses=(
        "[$claude_built]"
        "[$gemini_built]"
        "[$codex_built]"
        "[$opencode_built]"
        ""
        ""
        ""
        ""
        ""
        ""
      )

      for i in "${!main_items[@]}"; do
        local item_text="${main_items[$i]}"
        if [ "$i" -lt 4 ]; then
          if [ "$i" -eq "$selected" ]; then
            printf "  ${CYAN}▸${RESET} ${BOLD}%-32s${RESET} %-12s %s\n" "$item_text" "${statuses[$i]}" "$mount_mapping"
          else
            printf "    %-32s %-12s %s\n" "$item_text" "${statuses[$i]}" "$mount_mapping"
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
      echo -e "  Current active: ${GREEN}${active_mount_path}${RESET}"
      echo ""
      lines_printed=$((lines_printed + 3))

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
    if [ "$current_menu" = "main" ] && [ "$selected_index" -eq 5 ]; then
      selected_index=$(( (selected_index - 1 + len) % len ))
    elif [ "$current_menu" = "workspace" ] && [[ "${workspace_items[$selected_index]}" == ──* ]]; then
      selected_index=$(( (selected_index - 1 + len) % len ))
    fi
  else
    selected_index=$(( (selected_index + 1) % len ))
    # Skip dividers
    if [ "$current_menu" = "main" ] && [ "$selected_index" -eq 5 ]; then
      selected_index=$(( (selected_index + 1) % len ))
    elif [ "$current_menu" = "workspace" ] && [[ "${workspace_items[$selected_index]}" == ──* ]]; then
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
  echo "Close tmux session or type 'exit' inside the tmux window to return to TUI."
  echo ""
  
  # Run function
  $shell_func "$active_mount_path" || true

  # Update cached image statuses
  update_image_statuses

  tput civis
  force_clear=1
}

# Run build command helper
run_build() {
  local build_func="$1"
  tput cnorm
  clear
  echo "Running build command: $build_func..."
  echo ""
  if $build_func; then
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
      docker rmi -f "$CLAUDE_IMAGE_NAME" "$GEMINI_IMAGE_NAME" "$CODEX_IMAGE_NAME" "$OPENCODE_IMAGE_NAME" 2>/dev/null || true
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
  if [ "$current_menu" != "main" ]; then
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
        0) launch_tool "$CLAUDE_IMAGE_NAME" claude-docker-build claude-docker-shell ;;
        1) launch_tool "$GEMINI_IMAGE_NAME" gemini-docker-build gemini-docker-shell ;;
        2) launch_tool "$CODEX_IMAGE_NAME" codex-docker-build codex-docker-shell ;;
        3) launch_tool "$OPENCODE_IMAGE_NAME" opencode-docker-build opencode-docker-shell ;;
        4) current_menu="workspace"; selected_index=0; force_clear=1 ;;
        5) ;; # divider
        6) current_menu="build"; selected_index=0; force_clear=1 ;;
        7) current_menu="config"; selected_index=0; force_clear=1 ;;
        8) current_menu="cleanup"; selected_index=0; force_clear=1 ;;
        9) exit 0 ;;
      esac
      ;;
    build)
      case "$selected_index" in
        0) run_build claude-docker-build ;;
        1) run_build gemini-docker-build ;;
        2) run_build codex-docker-build ;;
        3) run_build opencode-docker-build ;;
        4) run_build docker-ai-build-all ;;
        5) handle_back ;;
      esac
      ;;
    config)
      case "$selected_index" in
        0) edit_env_file "$CLAUDE_CONFIG_PATH/docker-env.env" ;;
        1) edit_env_file "$GEMINI_CONFIG_PATH/docker-env.env" ;;
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
              active_mount_path=$(cd "$custom_input" 2>/dev/null && pwd)
              # Also add to recents list
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
          # A directory path was selected
          if [ -d "$path" ]; then
            active_mount_path="$path"
            # Update recents order
            _ai_docker_update_recents "$active_mount_path"
            # Return to main menu
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
_ai_docker_update_recents "$(pwd)"
update_image_statuses
tput civis
clear

while true; do
  if [ "$current_menu" = "workspace" ]; then
    load_workspace_menu
  fi

  # Use the overridden echo/printf buffering (0 subshells, 0 forks)
  FRAME_BUF=""
  CAPTURE_OUTPUT=1
  render_menu "$selected_index"
  CAPTURE_OUTPUT=0

  # Calculate menu_lines from the output structure
  newlines="${FRAME_BUF//[^$'\n']/}"
  menu_lines="${#newlines}"

  # Buffer the clear/move and render operations to write them in a single frame
  ESC=$'\e'
  frame_buf=""
  if [ "$force_clear" -eq 1 ]; then
    clear
    force_clear=0
  else
    if [ "$menu_lines" -gt 0 ]; then
      frame_buf+="${ESC}[${menu_lines}A${ESC}[J"
    fi
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
