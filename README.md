## AI CLI in Docker

Run AI CLI tools (OpenAI Codex, Google Gemini) inside Docker to keep your host clean while persisting CLI auth/config on your machine.

### Contents
- `Dockerfile.codex`: Based on ghcr.io/openai/codex-universal with @openai/codex preinstalled.
- `Dockerfile.gemini`: Based on node:20 with @google/gemini-cli preinstalled.
- `activate.sh` adds helper shell functions:
  - `codex-docker-build` — build the Codex image.
  - `codex-docker-shell` — open an interactive shell in the Codex container.
  - `gemini-docker-build` — build the Gemini image.
  - `gemini-docker-shell` — open an interactive shell in the Gemini container.
  - `codex-auth-docker-run` — run Codex auth flow inside the container.
  - `codex-deactivate` — remove the helper functions from the current shell.

### Prerequisites
- Docker installed and running.
- Bash or Zsh shell.

### Quick Start
1) Clone this repo and enter the directory.

2) Build the images:
   - `source ./activate.sh`
   - `codex-docker-build` (for Codex)
   - `gemini-docker-build` (for Gemini)

3) Authenticate Codex CLI inside Docker (one-time):
   - `codex-auth-docker-run`
   - This uses host networking and persists Codex CLI config under:
     - Host: `~/.codex-docker-config`
     - Container: `/root/.codex` (mounted)

4) Start a shell with your current project mounted:
   - `codex-docker-shell` (for Codex)
   - `gemini-docker-shell` (for Gemini)

What you get when the container starts:
- A tmux session named after your current folder (overridable with TMUX_SESSION).
- Windows:
  1) AI CLI (active by default) — runs `codex` or `gemini`, then keeps the shell open.
  2) Shell
  3) Shell
  4) htop

### tmux basics in this setup
- Switch windows (iterate):
  - Ctrl-b then n (next) / p (previous)
  - Ctrl-b then 1/2/3/4 to jump directly
  - Ctrl-b then w to choose from a list
- Create a new window: Ctrl-b then c
- Rename current window: Ctrl-b then ,
- Close current window: type `exit` in the window, or Ctrl-b then & (confirm)
- Detach from tmux (leave it running): Ctrl-b then d
- Re-attach later inside the container: tmux attach
- Extra binding in this image: Ctrl-b then Q shows a confirmation prompt and then kills the entire tmux server (all sessions).

More tmux docs:
- https://github.com/tmux/tmux/wiki
- man tmux

### Make more room for the session name in the tmux status bar
By default, tmux truncates the left status (where the session name appears) to ~10 characters. This setup increases it to 32 automatically. Customize it if needed:
- One-off run: TMUX_STATUS_LEFT_LENGTH=50 codex-docker-shell
- Persist for your shell session: export TMUX_STATUS_LEFT_LENGTH=50 before running codex-docker-shell

### Persist activation in your shell (bashrc/zshrc)
To have the helper functions available in every new shell, add a line to your shell init file that sources activate.sh from this repo. Replace /absolute/path/to/OpenAICodexInDocker with your actual path.

- Bash (e.g., ~/.bashrc or ~/.bash_profile on macOS):
  ```bash
  if [ -f "/absolute/path/to/OpenAICodexInDocker/activate.sh" ]; then
    . "/absolute/path/to/OpenAICodexInDocker/activate.sh"
  fi
  ```

- Zsh (e.g., ~/.zshrc):
  ```shell
  if [ -f "/absolute/path/to/OpenAICodexInDocker/activate.sh" ]; then
    source "/absolute/path/to/OpenAICodexInDocker/activate.sh"
  fi
  ```

After editing your rc file, reload it or open a new terminal:
- For Bash: source ~/.bashrc
- For Zsh: source ~/.zshrc

### Where Codex stores auth/config
- On your host: ~/.codex-docker-config
- In the container (mounted): /root/.codex
- You can back up or remove ~/.codex-docker-config to reset auth.

### Known quirk with codex auth link
When you run codex-auth-docker-run, Codex may print the sign-in URL with line breaks due to TTY wrapping in Docker. If your terminal doesn’t let you open the link directly:
- Carefully select and copy the full URL from the output.
- Paste it into a text editor and remove line breaks/spaces so it’s a single continuous URL.
- Paste the cleaned URL into your browser to complete the login.

### Known quirk with gemini cli
On first login, gemini cli may become unresponsive. Kill it and launch again. should work.

### Tips
- Rebuild the image after changing Dockerfile: codex-docker-build
- Temporarily remove functions from your current shell: codex-deactivate

### Notes
- --network=host is used for the auth flow to simplify opening the local browser and callbacks.

