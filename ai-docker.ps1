param(
  [string]$Workspace
)

$scriptPath = $PSCommandPath
if (-not $scriptPath) {
  $scriptPath = $MyInvocation.MyCommand.Path
}
$repoDir = Split-Path -Parent $scriptPath
$activatePath = Join-Path $repoDir 'activate.ps1'

if (-not (Test-Path -LiteralPath $activatePath -PathType Leaf)) {
  Write-Error "activate.ps1 not found in $repoDir"
  exit 1
}

. $activatePath

$launchDir = (Get-Location).Path
if (-not [string]::IsNullOrWhiteSpace($Workspace)) {
  try {
    $script:AI_DOCKER_ACTIVE_WORKSPACE = _ai_docker_get_workspace -Path $Workspace
  } catch {
    Write-Error $_
    exit 1
  }
} elseif ([string]::IsNullOrWhiteSpace($script:AI_DOCKER_ACTIVE_WORKSPACE)) {
  $script:AI_DOCKER_ACTIVE_WORKSPACE = $launchDir
}

_ai_docker_update_recents -PathToAdd $script:AI_DOCKER_ACTIVE_WORKSPACE

function Pause-AiDocker {
  Read-Host "Press Enter to continue" | Out-Null
}

function Get-ImageState {
  param([Parameter(Mandatory = $true)][string]$ImageName)

  $imageId = ((& docker images -q $ImageName 2>$null) | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($imageId)) {
    return "Not Built"
  }
  return "Built"
}

function Edit-EnvFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    New-Item -ItemType File -Path $Path -Force | Out-Null
  }

  $editor = if ($env:EDITOR) {
    $env:EDITOR
  } elseif (Get-Command notepad.exe -ErrorAction SilentlyContinue) {
    'notepad.exe'
  } else {
    'notepad'
  }

  & $editor $Path
}

function Select-Workspace {
  while ($true) {
    Clear-Host
    Write-Host "Change Workspace Directory"
    Write-Host ""
    Write-Host "Current active: $script:AI_DOCKER_ACTIVE_WORKSPACE"
    Write-Host ""
    Write-Host "1) Current directory: $launchDir"
    Write-Host "2) Enter custom path"

    $recentDirs = @()
    if (Test-Path -LiteralPath $script:AI_DOCKER_RECENTS_FILE -PathType Leaf) {
      $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
      foreach ($line in (Get-Content -LiteralPath $script:AI_DOCKER_RECENTS_FILE -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
          continue
        }
        if (-not (Test-Path -LiteralPath $line -PathType Container)) {
          continue
        }
        $resolved = _ai_docker_resolve_dir -Path $line
        if ($seen.Add($resolved) -and $resolved -ne $launchDir) {
          $recentDirs += $resolved
        }
      }
    }

    $map = @{}
    $index = 3
    foreach ($dir in $recentDirs) {
      Write-Host "$index) Recent: $dir"
      $map[$index.ToString()] = $dir
      $index++
    }

    Write-Host "0) Back"
    $choice = Read-Host "Select option"

    switch ($choice) {
      '0' { return }
      '1' {
        $script:AI_DOCKER_ACTIVE_WORKSPACE = _ai_docker_resolve_dir -Path $launchDir
        _ai_docker_update_recents -PathToAdd $script:AI_DOCKER_ACTIVE_WORKSPACE
        return
      }
      '2' {
        $custom = Read-Host "Path"
        if ([string]::IsNullOrWhiteSpace($custom)) {
          continue
        }
        try {
          $resolved = _ai_docker_get_workspace -Path $custom
          $script:AI_DOCKER_ACTIVE_WORKSPACE = $resolved
          _ai_docker_update_recents -PathToAdd $resolved
          return
        } catch {
          Write-Error $_
          Pause-AiDocker
        }
      }
      default {
        if ($map.ContainsKey($choice)) {
          $script:AI_DOCKER_ACTIVE_WORKSPACE = $map[$choice]
          _ai_docker_update_recents -PathToAdd $script:AI_DOCKER_ACTIVE_WORKSPACE
          return
        }
      }
    }
  }
}

function Show-BuildMenu {
  while ($true) {
    Clear-Host
    Write-Host "Rebuild/Update Images"
    Write-Host ""
    Write-Host "1) Claude Code  (Dockerfile.claude)"
    Write-Host "2) Gemini CLI   (Dockerfile.gemini)"
    Write-Host "3) OpenAI Codex (Dockerfile.codex)"
    Write-Host "4) OpenCode     (Dockerfile.opencode)"
    Write-Host "5) Rebuild ALL  (No Cache)"
    Write-Host "0) Back"

    switch (Read-Host "Select option") {
      '0' { return }
      '1' { claude-docker-build; Pause-AiDocker }
      '2' { gemini-docker-build; Pause-AiDocker }
      '3' { codex-docker-build; Pause-AiDocker }
      '4' { opencode-docker-build; Pause-AiDocker }
      '5' { docker-ai-build-all; Pause-AiDocker }
      default { }
    }
  }
}

function Show-ConfigMenu {
  while ($true) {
    Clear-Host
    Write-Host "Edit Environment Files"
    Write-Host ""
    Write-Host "1) Claude Env   (docker-env.env)"
    Write-Host "2) Gemini Env   (docker-env.env)"
    Write-Host "3) Codex Env    (docker-env.env)"
    Write-Host "4) OpenCode Env (docker-env.env)"
    Write-Host "0) Back"

    switch (Read-Host "Select option") {
      '0' { return }
      '1' { Edit-EnvFile -Path (Join-Path $script:CLAUDE_CONFIG_PATH 'docker-env.env') }
      '2' { Edit-EnvFile -Path (Join-Path $script:GEMINI_CONFIG_PATH 'docker-env.env') }
      '3' { Edit-EnvFile -Path (Join-Path $script:CODEX_CONFIG_PATH 'docker-env.env') }
      '4' { Edit-EnvFile -Path (Join-Path $script:OPENCODE_DOCKER_DIR 'docker-env.env') }
      default { }
    }
  }
}

function Show-CleanupMenu {
  while ($true) {
    Clear-Host
    Write-Host "Clean Up Docker Space"
    Write-Host ""
    Write-Host "1) Prune stopped containers"
    Write-Host "2) Remove dangling images"
    Write-Host "3) Remove ALL project images"
    Write-Host "0) Back"

    switch (Read-Host "Select option") {
      '0' { return }
      '1' {
        & docker container prune -f
        Pause-AiDocker
      }
      '2' {
        & docker image prune -f
        Pause-AiDocker
      }
      '3' {
        & docker rmi -f $script:CLAUDE_IMAGE_NAME $script:GEMINI_IMAGE_NAME $script:CODEX_IMAGE_NAME $script:OPENCODE_IMAGE_NAME 2>$null
        Pause-AiDocker
      }
      default { }
    }
  }
}

while ($true) {
  Clear-Host

  $claudeStatus = Get-ImageState -ImageName $script:CLAUDE_IMAGE_NAME
  $geminiStatus = Get-ImageState -ImageName $script:GEMINI_IMAGE_NAME
  $codexStatus = Get-ImageState -ImageName $script:CODEX_IMAGE_NAME
  $opencodeStatus = Get-ImageState -ImageName $script:OPENCODE_IMAGE_NAME

  Write-Host "AI CLI IN DOCKER - CONTROL MENU (PowerShell)"
  Write-Host ""
  Write-Host "Active workspace: $script:AI_DOCKER_ACTIVE_WORKSPACE"
  Write-Host ""
  Write-Host "1) Launch Claude Code   [$claudeStatus]"
  Write-Host "2) Launch Gemini CLI    [$geminiStatus]"
  Write-Host "3) Launch OpenAI Codex  [$codexStatus]"
  Write-Host "4) Launch OpenCode      [$opencodeStatus]"
  Write-Host "5) Change Workspace Directory"
  Write-Host "6) Rebuild/Update Images"
  Write-Host "7) Edit Environment Files"
  Write-Host "8) Clean up Docker Space"
  Write-Host "0) Exit"

  switch (Read-Host "Select option") {
    '0' { break }
    '1' { claude-docker-shell $script:AI_DOCKER_ACTIVE_WORKSPACE; Pause-AiDocker }
    '2' { gemini-docker-shell $script:AI_DOCKER_ACTIVE_WORKSPACE; Pause-AiDocker }
    '3' { codex-docker-shell $script:AI_DOCKER_ACTIVE_WORKSPACE; Pause-AiDocker }
    '4' { opencode-docker-shell $script:AI_DOCKER_ACTIVE_WORKSPACE; Pause-AiDocker }
    '5' { Select-Workspace }
    '6' { Show-BuildMenu }
    '7' { Show-ConfigMenu }
    '8' { Show-CleanupMenu }
    default { }
  }
}
