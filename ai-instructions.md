# AI Agent Guidelines for ai-cli-in-docker

This repository provides wrapper scripts (`ai-docker.sh` / `activate.sh` for Unix/Mac, and `ai-docker.ps1` / `activate.ps1` for Windows/PowerShell) to run CLI-based AI tools inside Docker containers.

## 1. Agent Command Execution Restrictions (Container-Only Execution)
- **Run Commands Inside Containers**: When the user asks the agent to run, test, or verify code changes, the agent must never execute execution/verification commands directly on the host machine. Instead, any execution must be run inside a Docker container (e.g., via `docker run` or using the repository's containerized test scripts like `./run-tests.sh`) to avoid bloating the host system and potential damage.
- **Exceptions (Host Allowed)**: The agent does NOT need to use containers for non-executing tasks such as reading/writing code files, git operations (e.g., `git status`, `git diff`), or navigating the workspace directory.

## 2. PowerShell Script Requirements (ai-docker.ps1 / activate.ps1)
- **UTF-8 with BOM**: Always write and save `.ps1` files using UTF-8 with BOM encoding (or UTF-16 LE). Without the BOM, Windows PowerShell (v5.1) will fail to parse Unicode characters (like borders `─` or emojis) and throw fatal parser/syntax errors.
- **Interactive Menus**:
  - The menu must dynamically scale its layout boundaries based on the terminal width, clamped between **40 and 76 columns** (`$cols = [Math]::Max(40, [Math]::Min(76, $Host.UI.RawUI.WindowSize.Width))`).
  - Active workspace paths printed in the header must be dynamically truncated (using standard `...` truncation) to prevent wrapping onto the next line and breaking the TUI box layout.
  - Interactive selection loops must exit cleanly on `0`, `q`, or `Q`. Never allow an infinite loop on unexpected keys or missing TTY inputs.

## 3. Docker & Platform Testing Constraints
- **Apple Silicon macOS Warning**: Running PowerShell images (`mcr.microsoft.com/powershell`) or .NET images (`mcr.microsoft.com/dotnet/sdk`) under Docker on Apple Silicon Mac hosts triggers QEMU emulation (due to 32-bit ARM or x86_64 image formats) and causes a fatal crash: `qemu: uncaught target signal 6 (Aborted) - core dumped`.
- **PowerShell Verification on Mac**: To verify PowerShell scripts natively on macOS, use native PowerShell Core (`brew install --cask powershell`) rather than Docker container emulation.

## 4. Shell / PowerShell Feature Parity
- Keep Unix/macOS helper scripts (`ai-docker.sh`) and Windows PowerShell helper scripts (`ai-docker.ps1`) functionally aligned.
- Any change to workspace directory tracking, config management, or container configuration should be implemented across both platforms.
