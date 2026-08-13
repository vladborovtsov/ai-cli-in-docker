# Dot-source this file to add AI Docker helpers to your PowerShell session.
# Usage:
#   . .\activate.ps1
#   codex-docker-build
#   codex-docker-shell
#   antigravity-docker-build
#   antigravity-docker-shell
#   opencode-docker-build
#   opencode-docker-shell
#   claude-docker-build
#   claude-docker-shell
#   docker-ai-build-all

$script:CODEX_IMAGE_NAME = "my-codex-image"
$script:ANTIGRAVITY_IMAGE_NAME = "my-antigravity-image"
$script:CLAUDE_IMAGE_NAME = "my-claude-image"
$script:OPENCODE_IMAGE_NAME = "my-opencode-image"

if ($env:AI_DOCKER_TERM_TITLE_ENABLE) {
  $script:AI_DOCKER_TERM_TITLE_ENABLE = $env:AI_DOCKER_TERM_TITLE_ENABLE
} elseif ($env:CODEX_ITERM_TITLE_ENABLE) {
  $script:AI_DOCKER_TERM_TITLE_ENABLE = $env:CODEX_ITERM_TITLE_ENABLE
} else {
  $script:AI_DOCKER_TERM_TITLE_ENABLE = "1"
}

if ($env:AI_DOCKER_PROFILE -and -not $script:AI_DOCKER_PROFILE_ENV_OVERRIDE) {
  $script:AI_DOCKER_PROFILE_ENV_OVERRIDE = $env:AI_DOCKER_PROFILE
}

$scriptPath = $PSCommandPath
if (-not $scriptPath) {
  $scriptPath = $MyInvocation.MyCommand.Path
}
$script:AI_DOCKER_REPO_DIR = Split-Path -Parent $scriptPath
if (-not $script:AI_DOCKER_REPO_DIR) {
  $script:AI_DOCKER_REPO_DIR = (Get-Location).Path
}

$script:AI_DOCKER_ACTIVE_WORKSPACE = (Get-Location).Path

function _ai_docker_ensure_dir {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    try {
      New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
    } catch {
      Write-Warning "Could not create directory '$Path': $($_.Exception.Message)"
    }
  }
}

function _ai_docker_ensure_file {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    try {
      New-Item -ItemType File -Path $Path -Force -ErrorAction Stop | Out-Null
    } catch {
      Write-Warning "Could not create file '$Path': $($_.Exception.Message)"
    }
  }
}

function _ai_docker_migrate_legacy {
  $oldIgnoreDir = Join-Path $HOME ".ai-docker-ignore"
  $newProfilesDir = Join-Path $HOME ".ai-docker-profiles"
  if (Test-Path -LiteralPath $oldIgnoreDir -PathType Container) {
    if (-not (Test-Path -LiteralPath $newProfilesDir -PathType Container)) {
      Move-Item -LiteralPath $oldIgnoreDir -Destination $newProfilesDir -Force -ErrorAction SilentlyContinue
    }
  }

  $legacyCodex = Join-Path $HOME ".codex-docker-config"
  $legacyGemini = Join-Path $HOME ".gemini-cli-docker-config"
  $legacyClaude = Join-Path $HOME ".claude-docker-config"
  $legacyOpencode = Join-Path $HOME ".opencode-docker"
  $legacyRecents = Join-Path $HOME ".ai-docker-recents"

  $targetDir = Join-Path (Join-Path $HOME ".ai-docker-profiles") "default"

  # Helper to migrate directory
  function _ai_docker_migrate_dir {
    param([string]$Src, [string]$Dest)
    if (Test-Path -LiteralPath $Src -PathType Container) {
      _ai_docker_ensure_dir -Path (Split-Path -Parent $Dest)
      if (-not (Test-Path -LiteralPath $Dest -PathType Container)) {
        Move-Item -LiteralPath $Src -Destination $Dest -Force -ErrorAction SilentlyContinue
      } else {
        Get-ChildItem -LiteralPath $Src -Force -ErrorAction SilentlyContinue | ForEach-Object {
          $destPath = Join-Path $Dest $_.Name
          Move-Item -LiteralPath $_.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $Src -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
  }

  if (Test-Path -LiteralPath $legacyRecents -PathType Leaf) {
    _ai_docker_ensure_dir -Path $targetDir
    Move-Item -LiteralPath $legacyRecents -Destination (Join-Path $targetDir "ai-docker-recents") -Force -ErrorAction SilentlyContinue
  } elseif (Test-Path -LiteralPath $legacyRecents -PathType Container) {
    _ai_docker_ensure_dir -Path $targetDir
    $innerRecents = Join-Path $legacyRecents "recents"
    $innerAiRecents = Join-Path $legacyRecents "ai-docker-recents"
    if (Test-Path -LiteralPath $innerRecents -PathType Leaf) {
      Move-Item -LiteralPath $innerRecents -Destination (Join-Path $targetDir "ai-docker-recents") -Force -ErrorAction SilentlyContinue
    } elseif (Test-Path -LiteralPath $innerAiRecents -PathType Leaf) {
      Move-Item -LiteralPath $innerAiRecents -Destination (Join-Path $targetDir "ai-docker-recents") -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $legacyRecents -Recurse -Force -ErrorAction SilentlyContinue
  }

  _ai_docker_migrate_dir -Src $legacyCodex -Dest (Join-Path $targetDir "codex-docker-config")
  _ai_docker_migrate_dir -Src $legacyGemini -Dest (Join-Path $targetDir "antigravity-cli-docker-config")
  _ai_docker_migrate_dir -Src $legacyClaude -Dest (Join-Path $targetDir "claude-docker-config")
  _ai_docker_migrate_dir -Src $legacyOpencode -Dest (Join-Path $targetDir "opencode-docker")
}

function _ai_docker_get_project_profile {
  param([string]$TargetPath)
  $mapFile = Join-Path (Join-Path $HOME ".ai-docker-profiles") "project-profiles"
  if (Test-Path -LiteralPath $mapFile -PathType Leaf) {
    $resolvedTarget = _ai_docker_resolve_dir -Path $TargetPath
    $lines = Get-Content -LiteralPath $mapFile -ErrorAction SilentlyContinue
    if ($lines) {
      foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
          continue
        }
        $lastColon = $line.LastIndexOf(':')
        if ($lastColon -gt 0) {
          $pPath = $line.Substring(0, $lastColon)
          $pProfile = $line.Substring($lastColon + 1)
          if ($pPath -eq $resolvedTarget) {
            return $pProfile.Trim()
          }
        }
      }
    }
  }
  return $null
}

function _ai_docker_get_project_ssh_agent {
  param([string]$TargetPath)
  $mapFile = Join-Path (Join-Path $HOME ".ai-docker-profiles") "project-ssh-settings"
  if (Test-Path -LiteralPath $mapFile -PathType Leaf) {
    $resolvedTarget = _ai_docker_resolve_dir -Path $TargetPath
    $lines = Get-Content -LiteralPath $mapFile -ErrorAction SilentlyContinue
    if ($lines) {
      foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
          continue
        }
        if ($line.Contains(":ssh_mount:")) {
          $idx = $line.IndexOf(":ssh_mount:")
          $pPath = $line.Substring(0, $idx)
          $pVal = $line.Substring($idx + 11)
          if ($pPath -eq $resolvedTarget) {
            return $pVal.Trim()
          }
        }
      }
    }
  }
  return "0"
}

function _ai_docker_set_project_ssh_agent {
  param([string]$TargetPath, [string]$Value)
  $mapFile = Join-Path (Join-Path $HOME ".ai-docker-profiles") "project-ssh-settings"
  _ai_docker_ensure_dir -Path (Split-Path -Parent $mapFile)

  $resolvedTarget = _ai_docker_resolve_dir -Path $TargetPath
  $tmpFile = "$mapFile.tmp"
  $found = $false
  $newLines = [System.Collections.Generic.List[string]]::new()

  if (Test-Path -LiteralPath $mapFile -PathType Leaf) {
    $lines = Get-Content -LiteralPath $mapFile -ErrorAction SilentlyContinue
    if ($lines) {
      foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
          continue
        }
        $pPath = $line
        if ($line.Contains(":ssh_mount:")) {
          $pPath = $line.Substring(0, $line.IndexOf(":ssh_mount:"))
        }
        if ($pPath -eq $resolvedTarget) {
          $newLines.Add("${resolvedTarget}:ssh_mount:${Value}")
          $found = $true
        } else {
          $newLines.Add($line)
        }
      }
    }
  }

  if (-not $found) {
    $newLines.Add("${resolvedTarget}:ssh_mount:${Value}")
  }

  Set-Content -LiteralPath $tmpFile -Value $newLines -Encoding UTF8
  Move-Item -LiteralPath $tmpFile -Destination $mapFile -Force
}

function _ai_docker_migrate_project_ssh_settings {
  $mapFile = Join-Path (Join-Path $HOME ".ai-docker-profiles") "project-ssh-settings"
  _ai_docker_ensure_dir -Path (Split-Path -Parent $mapFile)
  if (-not (Test-Path -LiteralPath $mapFile -PathType Leaf)) {
    New-Item -ItemType File -Path $mapFile -Force | Out-Null
  }

  $profilesMap = Join-Path (Join-Path $HOME ".ai-docker-profiles") "project-profiles"
  if (Test-Path -LiteralPath $profilesMap -PathType Leaf) {
    $lines = Get-Content -LiteralPath $profilesMap -ErrorAction SilentlyContinue
    if ($lines) {
      foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
          continue
        }
        $lastColon = $line.LastIndexOf(':')
        if ($lastColon -gt 0) {
          $pPath = $line.Substring(0, $lastColon)
          if ($pPath -and (Test-Path -LiteralPath $pPath)) {
            $resolved = _ai_docker_resolve_dir -Path $pPath
            $currentSettings = Get-Content -LiteralPath $mapFile -ErrorAction SilentlyContinue
            $exists = $false
            if ($currentSettings) {
              foreach ($s in $currentSettings) {
                if ($s.StartsWith("${resolved}:")) {
                  $exists = $true
                  break
                }
              }
            }
            if (-not $exists) {
              Add-Content -LiteralPath $mapFile -Value "${resolved}:ssh_mount:0" -Encoding UTF8
            }
          }
        }
      }
    }
  }
}

function _ai_docker_get_ssh_auth_sock {
  return "/run/host-services/ssh-auth.sock"
}

function _ai_docker_should_mount_ssh_agent {
  param([string]$TargetPath)
  $override = $env:AI_DOCKER_ENABLE_SSH_AGENT
  if ($override -in @("1", "true", "TRUE", "yes", "YES")) {
    return $true
  }
  if ($override -in @("0", "false", "FALSE", "no", "NO")) {
    return $false
  }
  $projVal = _ai_docker_get_project_ssh_agent -TargetPath $TargetPath
  return ($projVal -eq "1")
}

function _ai_docker_set_project_profile {
  param([string]$TargetPath, [string]$ProfileName)
  $mapFile = Join-Path (Join-Path $HOME ".ai-docker-profiles") "project-profiles"
  _ai_docker_ensure_dir -Path (Split-Path -Parent $mapFile)

  $resolvedTarget = _ai_docker_resolve_dir -Path $TargetPath
  $tmpFile = "$mapFile.tmp"

  $found = $false
  $newLines = [System.Collections.Generic.List[string]]::new()

  if (Test-Path -LiteralPath $mapFile -PathType Leaf) {
    $lines = Get-Content -LiteralPath $mapFile -ErrorAction SilentlyContinue
    if ($lines) {
      foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
          continue
        }
        $lastColon = $line.LastIndexOf(':')
        if ($lastColon -gt 0) {
          $pPath = $line.Substring(0, $lastColon)
          if ($pPath -eq $resolvedTarget) {
            if (-not [string]::IsNullOrWhiteSpace($ProfileName)) {
              $newLines.Add("${resolvedTarget}:${ProfileName}")
            }
            $found = $true
          } else {
            $newLines.Add($line)
          }
        } else {
          $newLines.Add($line)
        }
      }
    }
  }

  if (-not $found -and -not [string]::IsNullOrWhiteSpace($ProfileName)) {
    $newLines.Add("${resolvedTarget}:${ProfileName}")
  }

  if ($newLines.Count -gt 0) {
    $newLines | Set-Content -LiteralPath $tmpFile -ErrorAction Stop
    Move-Item -LiteralPath $tmpFile -Destination $mapFile -Force -ErrorAction Stop
  } else {
    if (Test-Path -LiteralPath $mapFile -PathType Leaf) {
      Remove-Item -LiteralPath $mapFile -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType File -Path $mapFile -Force | Out-Null
  }
}

function _ai_docker_load_profile {
  param(
    [string]$TargetProfile,
    [string]$Directory
  )

  _ai_docker_migrate_legacy

  if (-not [string]::IsNullOrWhiteSpace($TargetProfile)) {
    $script:AI_DOCKER_PROFILE = $TargetProfile
  }

  if ([string]::IsNullOrWhiteSpace($script:AI_DOCKER_PROFILE)) {
    if ($script:AI_DOCKER_PROFILE_ENV_OVERRIDE) {
      $script:AI_DOCKER_PROFILE = $script:AI_DOCKER_PROFILE_ENV_OVERRIDE
    } else {
      $checkDir = if ([string]::IsNullOrWhiteSpace($Directory)) { (Get-Location).Path } else { $Directory }
      $resolvedDir = _ai_docker_resolve_dir -Path $checkDir

      $mappedProfile = $null
      if (-not [string]::IsNullOrWhiteSpace($resolvedDir)) {
        $mappedProfile = _ai_docker_get_project_profile -TargetPath $resolvedDir
      }

      if (-not [string]::IsNullOrWhiteSpace($mappedProfile)) {
        $script:AI_DOCKER_PROFILE = $mappedProfile
      } else {
        $profileFile = Join-Path $HOME ".ai-docker-active-profile"
        if (Test-Path -LiteralPath $profileFile -PathType Leaf) {
          $script:AI_DOCKER_PROFILE = (Get-Content -LiteralPath $profileFile -Raw -ErrorAction SilentlyContinue).Trim()
        } else {
          $script:AI_DOCKER_PROFILE = "default"
        }
      }
    }
  }

  $script:AI_DOCKER_PROFILE = if ([string]::IsNullOrWhiteSpace($script:AI_DOCKER_PROFILE)) { "default" } else { $script:AI_DOCKER_PROFILE }

  $profileDir = Join-Path (Join-Path $HOME ".ai-docker-profiles") $script:AI_DOCKER_PROFILE
  $script:CODEX_CONFIG_PATH = Join-Path $profileDir "codex-docker-config"
  $script:ANTIGRAVITY_CONFIG_PATH = Join-Path $profileDir "antigravity-cli-docker-config"
  $script:CLAUDE_CONFIG_PATH = Join-Path $profileDir "claude-docker-config"
  $script:OPENCODE_DOCKER_DIR = Join-Path $profileDir "opencode-docker"
  $script:AI_DOCKER_RECENTS_FILE = Join-Path $profileDir "ai-docker-recents"

  # Migrate profile-level config folder if it exists
  $oldGeminiPath = Join-Path $profileDir "gemini-cli-docker-config"
  if ((Test-Path -LiteralPath $oldGeminiPath -PathType Container) -and -not (Test-Path -LiteralPath $script:ANTIGRAVITY_CONFIG_PATH -PathType Container)) {
    Move-Item -LiteralPath $oldGeminiPath -Destination $script:ANTIGRAVITY_CONFIG_PATH -Force -ErrorAction SilentlyContinue
  }

  foreach ($dir in @(
    $script:CODEX_CONFIG_PATH,
    $script:ANTIGRAVITY_CONFIG_PATH,
    $script:CLAUDE_CONFIG_PATH,
    $script:OPENCODE_DOCKER_DIR
  )) {
    _ai_docker_ensure_dir -Path $dir
    _ai_docker_ensure_file -Path (Join-Path $dir "docker-env.env")
    if ($dir -eq $script:CLAUDE_CONFIG_PATH) {
      _ai_docker_ensure_file -Path (Join-Path $dir "claude.json")
    }
  }
  _ai_docker_ensure_dir -Path (Join-Path $script:OPENCODE_DOCKER_DIR "local")
  _ai_docker_ensure_dir -Path (Join-Path $script:OPENCODE_DOCKER_DIR "config")
}

function ai-docker-profile {
  param([string]$Target)

  if ([string]::IsNullOrWhiteSpace($Target)) {
    Write-Host "Current profile: $($script:AI_DOCKER_PROFILE)"
    Write-Host "Available profiles:"
    Write-Host "  default"
    $ignoreDir = Join-Path $HOME ".ai-docker-profiles"
    if (Test-Path -LiteralPath $ignoreDir -PathType Container) {
      Get-ChildItem -LiteralPath $ignoreDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.Name
        if ($name -ne "default" -and $name -ne "project-profiles") {
          Write-Host "  $name"
        }
      }
    }
    return
  }

  $sanitized = $Target -replace '[^a-zA-Z0-9_-]', ''
  if ($sanitized -ne $Target -or [string]::IsNullOrWhiteSpace($Target)) {
    Write-Error "Error: Invalid profile name. Only alphanumeric, dashes, and underscores are allowed."
    return
  }

  $profileFile = Join-Path $HOME ".ai-docker-active-profile"
  $Target | Set-Content -LiteralPath $profileFile -ErrorAction Stop
  _ai_docker_load_profile -TargetProfile $Target

  $currentPwd = (Get-Location).Path
  if (-not (_ai_docker_is_home_path -Path $currentPwd)) {
    _ai_docker_set_project_profile -TargetPath $currentPwd -ProfileName $Target
    _ai_docker_update_recents -PathToAdd $currentPwd
    Write-Host "Profile '$Target' activated and mapped to current directory."
  } else {
    Write-Host "Profile '$Target' activated globally."
  }
}

function _ai_docker_resolve_dir {
  param([Parameter(Mandatory = $true)][string]$Path)
  try {
    return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
  } catch {
    return $Path
  }
}

function _ai_docker_update_recents {
  param([string]$PathToAdd)

  if ([string]::IsNullOrWhiteSpace($PathToAdd)) {
    return
  }
  if (-not (Test-Path -LiteralPath $PathToAdd -PathType Container)) {
    return
  }

  $resolvedAdd = _ai_docker_resolve_dir -Path $PathToAdd
  $candidates = @($resolvedAdd)

  if (Test-Path -LiteralPath $script:AI_DOCKER_RECENTS_FILE -PathType Leaf) {
    $candidates += Get-Content -LiteralPath $script:AI_DOCKER_RECENTS_FILE -ErrorAction SilentlyContinue
  }

  $mapFile = Join-Path (Join-Path $HOME ".ai-docker-profiles") "project-profiles"
  if (Test-Path -LiteralPath $mapFile -PathType Leaf) {
    $lines = Get-Content -LiteralPath $mapFile -ErrorAction SilentlyContinue
    if ($lines) {
      foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
        $lastColon = $line.LastIndexOf(':')
        if ($lastColon -gt 0) {
          $pPath = $line.Substring(0, $lastColon)
          if (-not [string]::IsNullOrWhiteSpace($pPath) -and (Test-Path -LiteralPath $pPath -PathType Container)) {
            $candidates += $pPath
          }
        }
      }
    }
  }

  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  $unique = New-Object 'System.Collections.Generic.List[string]'

  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      continue
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
      continue
    }

    $resolved = _ai_docker_resolve_dir -Path $candidate
    $maxRecents = if ($env:AI_DOCKER_MAX_RECENTS) { [int]$env:AI_DOCKER_MAX_RECENTS } else { 30 }
    if ($seen.Add($resolved)) {
      [void]$unique.Add($resolved)
      if ($unique.Count -ge $maxRecents) {
        break
      }
    }
  }

  if ($unique.Count -gt 0) {
    $unique | Set-Content -LiteralPath $script:AI_DOCKER_RECENTS_FILE
  } else {
    Set-Content -LiteralPath $script:AI_DOCKER_RECENTS_FILE -Value @()
  }
}

function _ai_docker_get_workspace {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return (Get-Location).Path
  }

  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Directory '$Path' does not exist."
  }

  return _ai_docker_resolve_dir -Path $Path
}

function _ai_docker_get_unique_workspace_name {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return "workspace"
  }
  $resolved = _ai_docker_resolve_dir -Path $Path

  $resolvedHome = [System.IO.Path]::GetFullPath($HOME).TrimEnd('\').TrimEnd('/')
  $resolvedPath = [System.IO.Path]::GetFullPath($resolved).TrimEnd('\').TrimEnd('/')

  $relPath = ""
  if ($resolvedPath.StartsWith($resolvedHome, [System.StringComparison]::OrdinalIgnoreCase)) {
    if ($resolvedPath -eq $resolvedHome) {
      $relPath = "home"
    } else {
      $relPath = $resolvedPath.Substring($resolvedHome.Length).TrimStart('\').TrimStart('/')
    }
  } else {
    if ($resolvedPath.Length -gt 1 -and $resolvedPath[1] -eq ':') {
      $relPath = $resolvedPath.Substring(2).TrimStart('\').TrimStart('/')
    } else {
      $relPath = $resolvedPath.TrimStart('\').TrimStart('/')
    }
  }

  $safeName = $relPath.Replace("\", "-").Replace("/", "-")
  return $safeName
}

function _ai_docker_is_home_path {
  param([Parameter(Mandatory = $true)][string]$Path)

  $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\\')
  $resolvedHome = [System.IO.Path]::GetFullPath($HOME).TrimEnd('\\')
  return $resolvedPath -ieq $resolvedHome
}

function _ai_docker_confirm_home_mount {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$CommandName
  )

  if (-not (_ai_docker_is_home_path -Path $Path)) {
    return $true
  }

  Write-Warning "You are running $CommandName from your HOME directory."
  Write-Warning "This will mount your entire HOME into the container workspace."
  $choice = Read-Host "Proceed with mounting HOME? [y/N]"
  return $choice -match '^(y|yes)$'
}

function _ai_docker_get_tz {
  if ($env:TZ) {
    return $env:TZ
  }

  try {
    $windowsId = (Get-TimeZone).Id
    if (-not [string]::IsNullOrWhiteSpace($windowsId)) {
      $iana = ""
      $ok = [System.TimeZoneInfo]::TryConvertWindowsIdToIanaId($windowsId, [ref]$iana)
      if ($ok -and -not [string]::IsNullOrWhiteSpace($iana)) {
        return $iana
      }
    }
  } catch {
    # Fall through to UTC on older runtimes where conversion API is unavailable.
  }

  return "UTC"
}

function _ai_docker_should_use_host_network {
  $raw = $env:AI_DOCKER_USE_HOST_NETWORK
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return $false
  }

  switch -Regex ($raw) {
    '^(1|true|yes)$' { return $true }
    '^(0|false|no)$' { return $false }
    default { return $false }
  }
}

function _ai_docker_set_title {
  param(
    [Parameter(Mandatory = $true)][string]$ToolName,
    [Parameter(Mandatory = $true)][string]$WorkspacePath
  )

  if ($script:AI_DOCKER_TERM_TITLE_ENABLE -ne "1") {
    return
  }

  $workspaceLeaf = _ai_docker_get_unique_workspace_name -Path $WorkspacePath
  if ([string]::IsNullOrWhiteSpace($workspaceLeaf)) {
    $workspaceLeaf = "workspace"
  }

  try {
    $host.UI.RawUI.WindowTitle = "$ToolName+$workspaceLeaf"
  } catch {
    # Ignore title update issues in non-interactive hosts.
  }
}

function _ai_docker_sync_gitconfig {
  param([string]$TargetDir)
  if ([string]::IsNullOrWhiteSpace($TargetDir)) { return }
  if (-not (Test-Path -LiteralPath $TargetDir -PathType Container)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
  }
  $gitConfig = Join-Path $HOME ".gitconfig"
  if (Test-Path -LiteralPath $gitConfig -PathType Leaf) {
    Copy-Item -LiteralPath $gitConfig -Destination (Join-Path $TargetDir ".gitconfig") -Force -ErrorAction SilentlyContinue
  }
  $xdgGit = Join-Path (Join-Path $HOME ".config") "git/config"
  if (Test-Path -LiteralPath $xdgGit -PathType Leaf) {
    Copy-Item -LiteralPath $xdgGit -Destination (Join-Path $TargetDir ".gitconfig_xdg") -Force -ErrorAction SilentlyContinue
  }
}

function _ai_docker_gitconfig_link_cmd {
  param(
    [string]$ContainerConfigDir,
    [string]$OrigCmd = 'start-tmux-layout'
  )
  return "if [ -f `"${ContainerConfigDir}/.gitconfig`" ]; then ln -sf `"${ContainerConfigDir}/.gitconfig`" /root/.gitconfig; fi; if [ -f `"${ContainerConfigDir}/.gitconfig_xdg`" ]; then mkdir -p /root/.config/git && ln -sf `"${ContainerConfigDir}/.gitconfig_xdg`" /root/.config/git/config; fi; ${OrigCmd}"
}

function _ai_docker_run_container {
  param(
    [Parameter(Mandatory = $true)][string]$ImageName,
    [Parameter(Mandatory = $true)][string]$EnvFile,
    [Parameter(Mandatory = $true)][string[]]$VolumeMounts,
    [Parameter(Mandatory = $true)][string]$WorkspacePath,
    [Parameter(Mandatory = $true)][hashtable]$EnvironmentVariables,
    [Parameter(Mandatory = $true)][string[]]$CommandArgs,
    [switch]$UseHostNetwork
  )

  $workspaceLeaf = _ai_docker_get_unique_workspace_name -Path $WorkspacePath
  if ([string]::IsNullOrWhiteSpace($workspaceLeaf)) {
    $workspaceLeaf = "workspace"
  }

  $tzValue = _ai_docker_get_tz

  $dockerArgs = @(
    'run', '--rm', '-it',
    '--env-file', $EnvFile,
    '--entrypoint', '/bin/bash'
  )

  if ($UseHostNetwork) {
    $dockerArgs += '--network=host'
  }

  foreach ($mount in $VolumeMounts) {
    $dockerArgs += '-v'
    $dockerArgs += $mount
  }

  if (_ai_docker_should_mount_ssh_agent -TargetPath $WorkspacePath) {
    $sshSockPath = _ai_docker_get_ssh_auth_sock
    if ($sshSockPath) {
      $dockerArgs += '-v'
      $dockerArgs += "${sshSockPath}:${sshSockPath}"
      $dockerArgs += '-e'
      $dockerArgs += "SSH_AUTH_SOCK=${sshSockPath}"
    }
  }

  $dockerArgs += '-v'
  $dockerArgs += "${WorkspacePath}:/workspace/$workspaceLeaf"
  $dockerArgs += '-w'
  $dockerArgs += "/workspace/$workspaceLeaf"
  $dockerArgs += '-e'
  $dockerArgs += "TZ=$tzValue"

  foreach ($key in $EnvironmentVariables.Keys) {
    $dockerArgs += '-e'
    $dockerArgs += "$key=$($EnvironmentVariables[$key])"
  }

  $dockerArgs += $ImageName
  $dockerArgs += $CommandArgs

  & docker @dockerArgs
  return $LASTEXITCODE
}

function _ai_docker_build_image {
  param(
    [Parameter(Mandatory = $true)][string]$ImageName,
    [Parameter(Mandatory = $true)][string]$DockerfileName,
    [switch]$NoCache
  )

  if (-not (Test-Path -LiteralPath $script:AI_DOCKER_REPO_DIR -PathType Container)) {
    throw "Failed to locate repository directory for docker build."
  }

  $dockerfilePath = Join-Path $script:AI_DOCKER_REPO_DIR $DockerfileName
  if (-not (Test-Path -LiteralPath $dockerfilePath -PathType Leaf)) {
    throw "Dockerfile not found: $dockerfilePath"
  }

  Write-Host "Building Docker image '$ImageName' from: $script:AI_DOCKER_REPO_DIR ($DockerfileName)"

  $oldImageId = ((& docker images -q $ImageName 2>$null) | Select-Object -First 1)

  $buildArgs = @('build', '--pull')
  if ($NoCache) {
    $buildArgs += '--no-cache'
  }
  $buildArgs += @('-f', $dockerfilePath, '-t', $ImageName, $script:AI_DOCKER_REPO_DIR)

  & docker @buildArgs
  if ($LASTEXITCODE -ne 0) {
    return $LASTEXITCODE
  }

  if (-not [string]::IsNullOrWhiteSpace($oldImageId)) {
    $newImageId = ((& docker images -q $ImageName 2>$null) | Select-Object -First 1)
    if ($oldImageId -and $newImageId -and $oldImageId -ne $newImageId) {
      Write-Host "Cleaning up previous image version ($oldImageId)..."
      & docker rmi $oldImageId 2>$null | Out-Null
    }
  }

  return 0
}

function _ai_docker_resolve_no_cache {
  param(
    [string[]]$RemainingArgs,
    [Parameter(Mandatory = $true)][string]$Usage
  )

  if (-not $RemainingArgs -or $RemainingArgs.Count -eq 0) {
    return $false
  }

  if ($RemainingArgs.Count -eq 1 -and $RemainingArgs[0] -eq '--no-cache') {
    return $true
  }

  throw "Usage: $Usage"
}

function codex-docker-build {
  param(
    [switch]$NoCache,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$RemainingArgs
  )

  try {
    if (_ai_docker_resolve_no_cache -RemainingArgs $RemainingArgs -Usage 'codex-docker-build [--no-cache]') {
      $NoCache = $true
    }
    return _ai_docker_build_image -ImageName $script:CODEX_IMAGE_NAME -DockerfileName 'Dockerfile.codex' -NoCache:$NoCache
  } catch {
    Write-Error $_
    return 2
  }
}

function antigravity-docker-build {
  param(
    [switch]$NoCache,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$RemainingArgs
  )

  try {
    if (_ai_docker_resolve_no_cache -RemainingArgs $RemainingArgs -Usage 'antigravity-docker-build [--no-cache]') {
      $NoCache = $true
    }
    return _ai_docker_build_image -ImageName $script:ANTIGRAVITY_IMAGE_NAME -DockerfileName 'Dockerfile.antigravity' -NoCache:$NoCache
  } catch {
    Write-Error $_
    return 2
  }
}

function claude-docker-build {
  param(
    [switch]$NoCache,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$RemainingArgs
  )

  try {
    if (_ai_docker_resolve_no_cache -RemainingArgs $RemainingArgs -Usage 'claude-docker-build [--no-cache]') {
      $NoCache = $true
    }
    return _ai_docker_build_image -ImageName $script:CLAUDE_IMAGE_NAME -DockerfileName 'Dockerfile.claude' -NoCache:$NoCache
  } catch {
    Write-Error $_
    return 2
  }
}

function opencode-docker-build {
  param(
    [switch]$NoCache,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$RemainingArgs
  )

  try {
    if (_ai_docker_resolve_no_cache -RemainingArgs $RemainingArgs -Usage 'opencode-docker-build [--no-cache]') {
      $NoCache = $true
    }
    return _ai_docker_build_image -ImageName $script:OPENCODE_IMAGE_NAME -DockerfileName 'Dockerfile.opencode' -NoCache:$NoCache
  } catch {
    Write-Error $_
    return 2
  }
}

function codex-docker-shell {
  param([string]$Path)

  try {
    $cwd = _ai_docker_get_workspace -Path $Path
  } catch {
    Write-Error $_
    return 1
  }

  _ai_docker_load_profile -TargetProfile "" -Directory $cwd
  _ai_docker_update_recents -PathToAdd $cwd
  if (-not (_ai_docker_confirm_home_mount -Path $cwd -CommandName 'codex-docker-shell')) {
    Write-Host "Canceled."
    return 1
  }

  _ai_docker_set_title -ToolName 'codex' -WorkspacePath $cwd
  _ai_docker_sync_gitconfig -TargetDir $script:CODEX_CONFIG_PATH
  $workspaceLeaf = _ai_docker_get_unique_workspace_name -Path $cwd
  $envVars = @{
    TERM = $(if ($env:TERM) { $env:TERM } else { 'xterm-256color' })
    TMUX_SESSION = $workspaceLeaf
    AI_DOCKER_PROFILE = $script:AI_DOCKER_PROFILE
    AI_NAME = 'codex'
    AI_COMMAND = 'codex'
  }

  $runParams = @{
    ImageName = $script:CODEX_IMAGE_NAME
    EnvFile = (Join-Path $script:CODEX_CONFIG_PATH 'docker-env.env')
    VolumeMounts = @("${script:CODEX_CONFIG_PATH}:/root/.codex")
    WorkspacePath = $cwd
    EnvironmentVariables = $envVars
    CommandArgs = @('-lc', (_ai_docker_gitconfig_link_cmd -ContainerConfigDir '/root/.codex' -OrigCmd 'start-tmux-layout'))
  }
  return _ai_docker_run_container @runParams
}

function codex-auth-docker-run {
  param([string]$Path)

  try {
    $cwd = _ai_docker_get_workspace -Path $Path
  } catch {
    Write-Error $_
    return 1
  }

  _ai_docker_load_profile -TargetProfile "" -Directory $cwd
  _ai_docker_update_recents -PathToAdd $cwd
  if (-not (_ai_docker_confirm_home_mount -Path $cwd -CommandName 'codex-auth-docker-run')) {
    Write-Host "Canceled."
    return 1
  }

  $useHostNetwork = _ai_docker_should_use_host_network
  if (-not $useHostNetwork) {
    Write-Host "Info: running codex auth without --network=host."
    Write-Host "Set AI_DOCKER_USE_HOST_NETWORK=1 to force host networking if your Docker setup supports it."
  }

  $runParams = @{
    ImageName = $script:CODEX_IMAGE_NAME
    EnvFile = (Join-Path $script:CODEX_CONFIG_PATH 'docker-env.env')
    VolumeMounts = @("${script:CODEX_CONFIG_PATH}:/root/.codex")
    WorkspacePath = $cwd
    EnvironmentVariables = @{}
    UseHostNetwork = $useHostNetwork
    CommandArgs = @('-c', '. /root/.nvm/nvm.sh && screen codex auth')
  }
  return _ai_docker_run_container @runParams
}

function antigravity-docker-shell {
  param([string]$Path)

  try {
    $cwd = _ai_docker_get_workspace -Path $Path
  } catch {
    Write-Error $_
    return 1
  }

  _ai_docker_load_profile -TargetProfile "" -Directory $cwd
  _ai_docker_update_recents -PathToAdd $cwd
  if (-not (_ai_docker_confirm_home_mount -Path $cwd -CommandName 'antigravity-docker-shell')) {
    Write-Host "Canceled."
    return 1
  }

  _ai_docker_set_title -ToolName 'antigravity' -WorkspacePath $cwd
  _ai_docker_sync_gitconfig -TargetDir $script:ANTIGRAVITY_CONFIG_PATH
  $workspaceLeaf = _ai_docker_get_unique_workspace_name -Path $cwd
  $envVars = @{
    TERM = $(if ($env:TERM) { $env:TERM } else { 'xterm-256color' })
    TMUX_SESSION = $workspaceLeaf
    AI_DOCKER_PROFILE = $script:AI_DOCKER_PROFILE
    AI_NAME = 'antigravity'
    AI_COMMAND = 'agy'
  }

  $runParams = @{
    ImageName = $script:ANTIGRAVITY_IMAGE_NAME
    EnvFile = (Join-Path $script:ANTIGRAVITY_CONFIG_PATH 'docker-env.env')
    VolumeMounts = @("${script:ANTIGRAVITY_CONFIG_PATH}:/root/.gemini")
    WorkspacePath = $cwd
    EnvironmentVariables = $envVars
    CommandArgs = @('-lc', (_ai_docker_gitconfig_link_cmd -ContainerConfigDir '/root/.gemini' -OrigCmd 'start-tmux-layout'))
  }
  return _ai_docker_run_container @runParams
}

function claude-docker-shell {
  param([string]$Path)

  try {
    $cwd = _ai_docker_get_workspace -Path $Path
  } catch {
    Write-Error $_
    return 1
  }

  _ai_docker_load_profile -TargetProfile "" -Directory $cwd
  _ai_docker_update_recents -PathToAdd $cwd
  if (-not (_ai_docker_confirm_home_mount -Path $cwd -CommandName 'claude-docker-shell')) {
    Write-Host "Canceled."
    return 1
  }

  _ai_docker_set_title -ToolName 'claude' -WorkspacePath $cwd
  _ai_docker_sync_gitconfig -TargetDir $script:CLAUDE_CONFIG_PATH
  $workspaceLeaf = _ai_docker_get_unique_workspace_name -Path $cwd
  $envVars = @{
    TERM = $(if ($env:TERM) { $env:TERM } else { 'xterm-256color' })
    TMUX_SESSION = $workspaceLeaf
    AI_DOCKER_PROFILE = $script:AI_DOCKER_PROFILE
    AI_NAME = 'claude'
    AI_COMMAND = $(if ($env:AI_COMMAND) { $env:AI_COMMAND } else { 'claude --continue || claude' })
  }

  $runParams = @{
    ImageName = $script:CLAUDE_IMAGE_NAME
    EnvFile = (Join-Path $script:CLAUDE_CONFIG_PATH 'docker-env.env')
    VolumeMounts = @("${script:CLAUDE_CONFIG_PATH}:/root/.claude")
    WorkspacePath = $cwd
    EnvironmentVariables = $envVars
    CommandArgs = @('-lc', (_ai_docker_gitconfig_link_cmd -ContainerConfigDir '/root/.claude' -OrigCmd 'ln -sf /root/.claude/claude.json /root/.claude.json; start-tmux-layout'))
  }
  return _ai_docker_run_container @runParams
}

function opencode-docker-shell {
  param([string]$Path)

  try {
    $cwd = _ai_docker_get_workspace -Path $Path
  } catch {
    Write-Error $_
    return 1
  }

  _ai_docker_load_profile -TargetProfile "" -Directory $cwd
  _ai_docker_update_recents -PathToAdd $cwd
  if (-not (_ai_docker_confirm_home_mount -Path $cwd -CommandName 'opencode-docker-shell')) {
    Write-Host "Canceled."
    return 1
  }

  _ai_docker_set_title -ToolName 'opencode' -WorkspacePath $cwd
  _ai_docker_sync_gitconfig -TargetDir (Join-Path $script:OPENCODE_DOCKER_DIR 'config')
  $workspaceLeaf = _ai_docker_get_unique_workspace_name -Path $cwd
  $envVars = @{
    TERM = $(if ($env:TERM) { $env:TERM } else { 'xterm-256color' })
    TMUX_SESSION = $workspaceLeaf
    AI_DOCKER_PROFILE = $script:AI_DOCKER_PROFILE
    AI_NAME = 'opencode'
    AI_COMMAND = 'opencode'
    PATH = '/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin'
  }

  $runParams = @{
    ImageName = $script:OPENCODE_IMAGE_NAME
    EnvFile = (Join-Path $script:OPENCODE_DOCKER_DIR 'docker-env.env')
    VolumeMounts = @(
      "${script:OPENCODE_DOCKER_DIR}/local:/root/.local",
      "${script:OPENCODE_DOCKER_DIR}/config:/root/.config/opencode"
    )
    WorkspacePath = $cwd
    EnvironmentVariables = $envVars
    CommandArgs = @('-lc', (_ai_docker_gitconfig_link_cmd -ContainerConfigDir '/root/.config/opencode' -OrigCmd 'start-tmux-layout'))
  }
  return _ai_docker_run_container @runParams
}

function docker-ai-build-all {
  $steps = @(
    { codex-docker-build -NoCache },
    { antigravity-docker-build -NoCache },
    { opencode-docker-build -NoCache },
    { claude-docker-build -NoCache }
  )

  foreach ($step in $steps) {
    $result = & $step
    if ($result -ne 0) {
      return [int]$result
    }
  }

  return 0
}

function ai-docker {
  param([string]$Workspace)

  $menuPath = Join-Path $script:AI_DOCKER_REPO_DIR 'ai-docker.ps1'
  if (-not (Test-Path -LiteralPath $menuPath -PathType Leaf)) {
    Write-Error "ai-docker.ps1 not found in $script:AI_DOCKER_REPO_DIR"
    return 1
  }

  _ai_docker_load_profile -TargetProfile "" -Directory (Get-Location).Path

  if ([string]::IsNullOrWhiteSpace($Workspace)) {
    & $menuPath
  } else {
    & $menuPath -Workspace $Workspace
  }

  $exitCode = $LASTEXITCODE
  _ai_docker_load_profile -TargetProfile "" -Directory (Get-Location).Path
  return $exitCode
}

function ai-docker-deactivate {
  foreach ($name in @(
    '_ai_docker_ensure_dir', '_ai_docker_ensure_file', '_ai_docker_resolve_dir',
    '_ai_docker_update_recents', '_ai_docker_get_workspace', '_ai_docker_is_home_path',
    '_ai_docker_get_unique_workspace_name',
    '_ai_docker_confirm_home_mount', '_ai_docker_get_tz', '_ai_docker_should_use_host_network',
    '_ai_docker_set_title', '_ai_docker_run_container', '_ai_docker_build_image',
    '_ai_docker_sync_gitconfig', '_ai_docker_gitconfig_link_cmd',
    '_ai_docker_resolve_no_cache', '_ai_docker_load_profile',
    '_ai_docker_migrate_legacy', '_ai_docker_migrate_dir', '_ai_docker_get_project_profile', '_ai_docker_set_project_profile', 'ai-docker-profile',
    'codex-docker-build', 'codex-docker-shell', 'codex-auth-docker-run',
    'antigravity-docker-build', 'antigravity-docker-shell',
    'claude-docker-build', 'claude-docker-shell',
    'opencode-docker-build', 'opencode-docker-shell',
    'docker-ai-build-all', 'ai-docker', 'ai-docker-deactivate'
  )) {
    if (Get-Command $name -ErrorAction SilentlyContinue) {
      Remove-Item "Function:$name" -ErrorAction SilentlyContinue
    }
  }
}

_ai_docker_load_profile -TargetProfile "" -Directory (Get-Location).Path
