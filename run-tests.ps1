# Local Docker Test Runner for Windows / PowerShell
$ErrorActionPreference = "Stop"

# Ensure we are in the repository root
$scriptPath = $MyInvocation.MyCommand.Path
if ($scriptPath) {
    $repoDir = Split-Path -Parent $scriptPath
    Set-Location $repoDir
}

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "   Running Local Docker Test Runner (pwsh)   " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

Write-Host "`n1. Running Bash Helper & TUI Tests..." -ForegroundColor Yellow
docker run --rm -v "${pwd}:/workspace" -w /workspace python:3.12-slim python3 -m unittest discover -s tests -p "test_bash_*.py"

Write-Host "`n2. Running PowerShell Pester Tests..." -ForegroundColor Yellow
docker run --rm -v "${pwd}:/workspace" -w /workspace mcr.microsoft.com/powershell:latest pwsh -Command '
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

Write-Host "`n3. Building & Verifying Docker Images..." -ForegroundColor Yellow
# Dot-source the PowerShell helper functions
. .\activate.ps1

$tools = @('claude', 'gemini', 'codex', 'opencode')
foreach ($tool in $tools) {
    Write-Host "`n   -> Building image for: $tool..." -ForegroundColor Cyan
    & "${tool}-docker-build"
    
    Write-Host "   -> Running container verify script..." -ForegroundColor Cyan
    docker run --rm -v "${pwd}:/workspace" -w /workspace "my-${tool}-image" /workspace/tests/verify_container.sh $tool
}

Write-Host "`n==============================================" -ForegroundColor Green
Write-Host "✔ All local tests built and verified successfully!" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
