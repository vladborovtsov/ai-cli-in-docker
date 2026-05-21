## AI CLI in Docker

Run AI CLI tools (OpenAI Codex, Google Gemini, Claude, OpenCode) inside Docker to keep your host clean while persisting CLI auth and config on your machine.

### Contents
- [Why AI CLI in Docker?](WHY.md): Rationale behind this project.
- `Dockerfile.codex`: Based on `ghcr.io/openai/codex-universal` with `@openai/codex` preinstalled.
- `Dockerfile.gemini`: Based on `node:20` with `@google/gemini-cli` preinstalled.
- `Dockerfile.claude`: Based on `ubuntu:24.04` with `@anthropic-ai/claude-code` preinstalled.
- `Dockerfile.opencode`: Based on `ubuntu:24.04` with `opencode-ai` preinstalled.
- `activate.sh`: Bash/Zsh helper functions.
- `ai-docker.sh`: Interactive Bash TUI.
- `activate.ps1`: PowerShell helper functions for Windows.
- `ai-docker.ps1`: Interactive PowerShell menu for Windows.

### Prerequisites
- Docker installed and running.
- One of:
  - Bash or Zsh (Linux/macOS).
  - PowerShell 5.1+ or PowerShell 7+ (Windows).

### Quick Start (Bash/Zsh)
1) Clone this repo and enter the directory.

2) Source the activation script:
```bash
source ./activate.sh
```

3) Launch the interactive TUI:
```bash
ai-docker
```

4) Or run helpers directly:
- `claude-docker-shell`
- `gemini-docker-shell`
- `codex-docker-shell`
- `opencode-docker-shell`

### Quick Start (Windows PowerShell)
1) Clone this repo and enter the directory in PowerShell.

2) Load helper functions into your current session:
```powershell
. .\activate.ps1
```

If script execution is blocked, run this first in the same terminal:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

3) Launch the interactive menu:
```powershell
ai-docker
```

4) Or run helpers directly:
- `claude-docker-shell`
- `gemini-docker-shell`
- `codex-docker-shell`
- `opencode-docker-shell`

### Available helper commands
- `ai-docker`: Launch interactive menu (Bash TUI or PowerShell menu).
- `codex-docker-build` / `codex-docker-shell`
- `gemini-docker-build` / `gemini-docker-shell`
- `claude-docker-build` / `claude-docker-shell`
- `opencode-docker-build` / `opencode-docker-shell`
- `docker-ai-build-all`: Build all images with no cache.
- `codex-auth-docker-run`: Run Codex auth flow inside container.
- `ai-docker-deactivate`: Remove helper functions from current shell.

### What you get when the container starts
- A tmux session named after your current folder (overridable with `TMUX_SESSION`).
- Windows:
  1) AI CLI (active by default): runs `codex`, `gemini`, `claude`, or `opencode`, then keeps shell open.
  2) Shell
  3) Shell
  4) `htop`

### tmux basics in this setup
- Switch windows:
  - `Ctrl-b` then `n` (next) / `p` (previous)
  - `Ctrl-b` then `1/2/3/4` to jump directly
  - `Ctrl-b` then `w` to choose from a list
- Create a new window: `Ctrl-b` then `c`
- Rename current window: `Ctrl-b` then `,`
- Close current window: type `exit`, or `Ctrl-b` then `&`
- Detach from tmux: `Ctrl-b` then `d`
- Re-attach inside container: `tmux attach`
- Extra binding: `Ctrl-b` then `Q` prompts then kills all tmux sessions.

More tmux docs:
- https://github.com/tmux/tmux/wiki
- `man tmux`

### Make more room for the session name in tmux status bar
By default, tmux truncates the left status text. This setup increases it to 32 characters.
- One-off run: `TMUX_STATUS_LEFT_LENGTH=50 gemini-docker-shell`
- Persist for current shell session: `export TMUX_STATUS_LEFT_LENGTH=50`

### Persist activation in shell profile
Add activation to your shell profile so helpers are available in new terminals.

Bash (`~/.bashrc` or `~/.bash_profile`):
```bash
if [ -f "/absolute/path/to/ai-cli-in-docker/activate.sh" ]; then
  . "/absolute/path/to/ai-cli-in-docker/activate.sh"
fi
```

Zsh (`~/.zshrc`):
```bash
if [ -f "/absolute/path/to/ai-cli-in-docker/activate.sh" ]; then
  source "/absolute/path/to/ai-cli-in-docker/activate.sh"
fi
```

PowerShell (`$PROFILE`):
```powershell
if (!(Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
Add-Content -Path $PROFILE -Value '. "C:\absolute\path\to\ai-cli-in-docker\activate.ps1"'
```

Reload profile:
- Bash: `source ~/.bashrc`
- Zsh: `source ~/.zshrc`
- PowerShell: `. $PROFILE`

### Profiles and Configuration Storage
The CLI supports multiple isolated profiles. Only `default` is pre-defined, but you can create additional profiles (e.g., `personal`, `work`). Each profile isolates auth, configs, recent workspace paths, and environment files under:
`~/.ai-docker-profiles/<profile-name>/`

Specifically, for the active profile:
- **Codex**:
  - Host: `~/.ai-docker-profiles/<profile>/codex-docker-config`
  - Container: `/root/.codex`
- **Gemini**:
  - Host: `~/.ai-docker-profiles/<profile>/gemini-cli-docker-config`
  - Container: `/root/.gemini`
- **Claude**:
  - Host: `~/.ai-docker-profiles/<profile>/claude-docker-config`
  - Container: `/root/.claude`
  - `/root/.claude.json` is symlinked to `/root/.claude/claude.json`
- **OpenCode**:
  - Host: `~/.ai-docker-profiles/<profile>/opencode-docker/local` -> Container: `/root/.local`
  - Host: `~/.ai-docker-profiles/<profile>/opencode-docker/config` -> Container: `/root/.config/opencode`
  - Host: `~/.ai-docker-profiles/<profile>/opencode-docker/docker-env.env` -> Container environment variables

Each host config directory includes a `docker-env.env` file that is passed to the container.

#### Managing Profiles
- **Switching Profiles via TUI**: Select `👤 Switch Active Profile` on the main screen to change profiles or create a new one.
- **Environment Override**: Set the `AI_DOCKER_PROFILE` environment variable in your terminal session to override the active profile:
  ```bash
  export AI_DOCKER_PROFILE=work
  ```
- **Active Profile File**: If `AI_DOCKER_PROFILE` is not set, the active profile defaults to the name stored in `~/.ai-docker-active-profile`, and falls back to `default` if the file doesn't exist.

### Passing environment variables
Add environment variables to the tool's `docker-env.env` file.

Example for Claude (`~/.ai-docker-profiles/<profile>/claude-docker-config/docker-env.env`):
```env
ANTHROPIC_BASE_URL=http://host.docker.internal:1234
ANTHROPIC_AUTH_TOKEN=lm
ANTHROPIC_MODEL=mlx-community/qwen3.5-9b
```

### Known quirk with Codex auth link
`codex-auth-docker-run` may print a wrapped sign-in URL.
If your terminal cannot open it directly:
- Copy the full URL carefully.
- Remove line breaks/spaces in a text editor.
- Open the cleaned URL in your browser.

### Known quirk with Gemini CLI
On first login, Gemini CLI may become unresponsive. Restart it and try again.

## Tips and Tricks

### How do I insert line breaks in messages?
Use `Ctrl+J` to insert a line break.

Verified in:
- `gemini cli`
- `codex cli`
- `opencode`

### Additional tips
- Rebuild after changing a Dockerfile: `codex-docker-build`, `gemini-docker-build`, etc.
- Remove helper functions from current shell: `ai-docker-deactivate`

### Notes
- On Linux hosts, `codex-auth-docker-run` uses `--network=host` by default.
- On Windows/macOS with Docker Desktop, host networking is disabled by default in `activate.ps1`.
- To force host networking in PowerShell helpers (only if your Docker setup supports it), set `AI_DOCKER_USE_HOST_NETWORK=1`.
