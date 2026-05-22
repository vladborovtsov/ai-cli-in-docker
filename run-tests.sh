#!/usr/bin/env bash
set -euo pipefail

# Ensure we are in the repository root
cd "$(dirname "$0")"

echo "=============================================="
echo "   Running Local Docker Test Runner (Bash)   "
echo "=============================================="

echo -e "\n1. Running Bash Helper & TUI Tests..."
docker run --rm -v "$(pwd):/workspace" -w /workspace python:3.12-slim python3 -m unittest discover -s tests -p "test_bash_*.py"

echo -e "\n2. Running PowerShell Pester Tests..."
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
  echo "Skipping PowerShell Pester tests on arm64/aarch64 architecture."
else
  docker run --rm -v "$(pwd):/workspace" -w /workspace mcr.microsoft.com/powershell:latest pwsh -Command '
    Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser -Repository PSGallery -ErrorAction SilentlyContinue | Out-Null
    $tmpHome = "/tmp/pester_home"
    New-Item -ItemType Directory -Path $tmpHome -Force | Out-Null
    $env:HOME = $tmpHome
    $env:USERPROFILE = $tmpHome
    $result = Invoke-Pester -Path tests/PesterTests.Tests.ps1 -Output Detailed -PassThru
    if ($result.FailedCount -gt 0) {
      Write-Error "PowerShell Pester tests failed!"
      exit 1
    }
  '
fi

echo -e "\n3. Building & Verifying Docker Images..."
# Source helper functions
source ./activate.sh

for tool in claude gemini codex opencode; do
  echo -e "\n   -> Building image for: $tool..."
  "${tool}-docker-build"
  
  echo "   -> Running container verify script..."
  docker run --rm -v "$(pwd):/workspace" -w /workspace "my-${tool}-image" /workspace/tests/verify_container.sh "$tool"
done

echo -e "\n=============================================="
echo "✔ All local tests built and verified successfully!"
echo "=============================================="
