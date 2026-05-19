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
current_menu="main"
selected_index=0
menu_lines=0
force_clear=1

# Menu definition lists
main_items=(
  "💬 Launch Claude Code"
  "💬 Launch Gemini CLI"
  "💬 Launch OpenAI Codex"
  "💬 Launch OpenCode"
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
  esac
}

# Clear lines previously drawn for flicker-free rendering
clear_lines() {
  local num_lines="$1"
  if [ "$num_lines" -gt 0 ]; then
    # Move cursor up N lines
    echo -ne "\033[${num_lines}A"
    # Clear from cursor to end of screen
    echo -ne "\033[J"
  fi
}

# Render the active menu
render_menu() {
  local selected="$1"
  local lines_printed=0

  # Header block
  echo -e "${BOLD}┌────────────────────────────────────────────────────────┐${RESET}"
  echo -e "${BOLD}│             🤖 AI CLI IN DOCKER - CONTROL TUI          │${RESET}"
  echo -e "${BOLD}└────────────────────────────────────────────────────────┘${RESET}"
  echo ""
  lines_printed=4

  case "$current_menu" in
    main)
      echo -e "  ${BOLD}Select an action to launch or manage:${RESET}"
      echo ""
      lines_printed=$((lines_printed + 2))

      local claude_status=$(check_image_built "$CLAUDE_IMAGE_NAME")
      local gemini_status=$(check_image_built "$GEMINI_IMAGE_NAME")
      local codex_status=$(check_image_built "$CODEX_IMAGE_NAME")
      local opencode_status=$(check_image_built "$OPENCODE_IMAGE_NAME")

      local statuses=(
        "[$claude_status]"
        "[$gemini_status]"
        "[$codex_status]"
        "[$opencode_status]"
        ""
        ""
        ""
        ""
        ""
      )

      for i in "${!main_items[@]}"; do
        if [ "$i" -eq "$selected" ]; then
          printf "  ${CYAN}▸${RESET} ${BOLD}%-32s${RESET} %s\n" "${main_items[$i]}" "${statuses[$i]}"
        else
          if [[ "${main_items[$i]}" == ──* ]]; then
            printf "    %s\n" "${main_items[$i]}"
          else
            printf "    %-32s %s\n" "${main_items[$i]}" "${statuses[$i]}"
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
  esac

  # Footer block
  echo ""
  echo -e "${BOLD}────────────────────────────────────────────────────────${RESET}"
  echo -e " [Use ↑/↓ or j/k to navigate, Enter to select, Q/Esc to go back/exit]"
  lines_printed=$((lines_printed + 3))

  menu_lines="$lines_printed"
}

# Navigate through menu indices (skips visual dividers)
move_selection() {
  local dir="$1"
  local len=$(get_menu_length)

  if [ "$dir" = "UP" ]; then
    selected_index=$(( (selected_index - 1 + len) % len ))
    # Skip divider in main menu
    if [ "$current_menu" = "main" ] && [ "$selected_index" -eq 4 ]; then
      selected_index=$(( (selected_index - 1 + len) % len ))
    fi
  else
    selected_index=$(( (selected_index + 1) % len ))
    # Skip divider in main menu
    if [ "$current_menu" = "main" ] && [ "$selected_index" -eq 4 ]; then
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
  $shell_func || true

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
        4) ;; # divider
        5) current_menu="build"; selected_index=0; force_clear=1 ;;
        6) current_menu="config"; selected_index=0; force_clear=1 ;;
        7) current_menu="cleanup"; selected_index=0; force_clear=1 ;;
        8) exit 0 ;;
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
tput civis
clear

while true; do
  if [ "$force_clear" -eq 1 ]; then
    clear
    force_clear=0
  fi
  
  render_menu "$selected_index"
  
  key=$(read_key)
  case "$key" in
    UP)
      move_selection "UP"
      clear_lines "$menu_lines"
      ;;
    DOWN)
      move_selection "DOWN"
      clear_lines "$menu_lines"
      ;;
    ENTER)
      handle_select
      ;;
    QUIT)
      handle_back
      ;;
    *)
      clear_lines "$menu_lines"
      ;;
  esac
done
