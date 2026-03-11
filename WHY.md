### Why AI CLI in Docker?

This document explains the rationale behind running AI CLI tools within Docker containers and the specific problems this project aims to solve.

#### 1. Layered Security (Defense in Depth)
While many AI tools (such as `Claude Code`) implement their own internal sandboxing mechanisms for executing code, those sandboxes primarily focus on the code *generated* by the AI.
*   **Internal Sandbox**: Usually protects against malicious code outputs (e.g., preventing a generated script from escaping a runtime).
*   **Docker Sandbox**: Protects your host system from the **AI CLI tool itself**. Even if a tool is trusted, running it in Docker ensures that it only has access to the specific project directory mounted in `/workspace`. This prevents the AI from accidentally reading or modifying unrelated files, sensitive SSH keys, or environment variables on your host machine.

#### 2. Host System "Hygiene"
AI CLI tools often come with a heavy tail of dependencies and specific runtime requirements (Node.js, Python, etc.).
*   **Version Isolation**: Run multiple tools (Gemini, Claude, Codex) without worrying about conflicting Node.js versions or polluting your host's global `npm` or `pip` namespace.
*   **Consistent Environment**: Ensures that the tool behaves identically regardless of which machine you are working on, provided Docker is installed.

#### 3. Pre-configured "IDE-like" Terminal Environment
Rather than just providing a raw container, this project sets up a dedicated productivity environment:
*   **Automatic `tmux` layout**: Starting a container automatically launches a `tmux` session with a multi-tab layout, including the AI CLI, two extra shells for commands, and `htop` for monitoring.
*   **Productivity Tweaks**: Includes automatic terminal title updates and common utilities (`bat`, `jq`) pre-installed to assist in the AI-human workflow.

#### 4. Solving the Persistence and Auth Problem
One of the biggest hurdles of using CLI tools in Docker is losing authentication state when the container stops. This project addresses this by:
*   **Config Mapping**: Mapping host-side configuration directories (e.g., `~/.claude-docker-config`) to the appropriate paths inside the container.
*   **Auth Helpers**: Providing dedicated scripts like `codex-auth-docker-run` to handle complex OAuth flows that typically break in containerized environments.

#### Summary
Even when a CLI tool claims to be "sandboxed," it is often a **soft sandbox** (restricted execution) rather than **hard isolation** (OS-level containerization). This project provides the latter, while delivering a "portable workstation" experience for AI-assisted development.
