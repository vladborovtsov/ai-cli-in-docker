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

function Activate-Workspace {
  param([string]$targetPath)
  if ([string]::IsNullOrWhiteSpace($targetPath) -or -not (Test-Path -LiteralPath $targetPath -PathType Container)) {
    return
  }
  $resolved = _ai_docker_resolve_dir -Path $targetPath
  $script:AI_DOCKER_ACTIVE_WORKSPACE = $resolved
  
  if ($resolved -ne $HOME) {
    $mapped = _ai_docker_get_project_profile -TargetPath $resolved
    if (-not [string]::IsNullOrWhiteSpace($mapped)) {
      $activeProfileFile = Join-Path $HOME ".ai-docker-active-profile"
      $mapped | Out-File -LiteralPath $activeProfileFile -Force -NoNewline -Encoding utf8
      _ai_docker_load_profile -TargetProfile $mapped -Directory $resolved
    } else {
      $active = if ($script:AI_DOCKER_PROFILE) { $script:AI_DOCKER_PROFILE } else { "default" }
      _ai_docker_set_project_profile -TargetPath $resolved -ProfileName $active
      _ai_docker_load_profile -TargetProfile $active -Directory $resolved
    }
  }
}

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

Activate-Workspace $script:AI_DOCKER_ACTIVE_WORKSPACE
_ai_docker_update_recents -PathToAdd $script:AI_DOCKER_ACTIVE_WORKSPACE

# Main interactive TUI state
$script:current_menu = "main"
$script:selected_index = 0
$script:selected_profile_name = ""
$script:profileActionItems = @(
  "👉 Activate Profile",
  "✏️  Rename Profile",
  "🗑️  Delete Profile",
  "⬅️  Back to Profile List"
)

function Get-MainItems {
  $profile = if ($script:AI_DOCKER_PROFILE) { $script:AI_DOCKER_PROFILE } else { "default" }
  return @(
    "💬 Launch Claude Code",
    "🤖 Launch Claude Code (Auto Mode)",
    "💀 Launch Claude Code (Dangerous Mode)",
    "💬 Launch Antigravity CLI",
    "💬 Launch OpenAI Codex",
    "💬 Launch OpenCode",
    "──────────────────────────────────────────────────",
    "📁 Change Workspace Directory...",
    "🕒 Recent Projects...",
    "👤 Switch Active Profile (Current: $profile)",
    "──────────────────────────────────────────────────",
    "🛠️  Rebuild/Update Images...",
    "⚙️  Edit Environment Files...",
    "🧹 Clean up Docker Space...",
    "🚪 Exit"
  )
}

function Get-ProfileItems {
  $names = New-Object System.Collections.Generic.List[string]
  [void]$names.Add("default")

  $ignoreDir = Join-Path $HOME ".ai-docker-profiles"
  if (Test-Path -LiteralPath $ignoreDir -PathType Container) {
    foreach ($d in Get-ChildItem -LiteralPath $ignoreDir -Directory -ErrorAction SilentlyContinue) {
      $name = $d.Name
      if (-not $names.Contains($name)) {
        [void]$names.Add($name)
      }
    }
  }

  $items = New-Object System.Collections.Generic.List[string]
  $activeProfile = if ($script:AI_DOCKER_PROFILE) { $script:AI_DOCKER_PROFILE } else { "default" }
  foreach ($name in $names) {
    if ($name -eq $activeProfile) {
      [void]$items.Add("👤 $name (Active)")
    } else {
      [void]$items.Add("👤 $name")
    }
  }

  [void]$items.Add("──────────────────────────────────────────────────")
  [void]$names.Add("DIVIDER")

  [void]$items.Add("➕ Create New Profile...")
  [void]$names.Add("CREATE")

  [void]$items.Add("⬅️ Back to Main Menu")
  [void]$names.Add("BACK")

  return [PSCustomObject]@{
    Items = $items.ToArray()
    Names = $names.ToArray()
  }
}

$buildItems = @(
  "📦 Claude Code (Dockerfile.claude - No Cache)",
  "📦 Antigravity CLI (Dockerfile.antigravity - No Cache)",
  "📦 OpenAI Codex (Dockerfile.codex - No Cache)",
  "📦 OpenCode     (Dockerfile.opencode - No Cache)",
  "🔄 Rebuild ALL  (No Cache)",
  "⬅️ Back to Main Menu"
)

$configItems = @(
  "📝 Claude Env   (docker-env.env)",
  "📝 Antigravity Env (docker-env.env)",
  "📝 Codex Env    (docker-env.env)",
  "📝 OpenCode Env (docker-env.env)",
  "⬅️ Back to Main Menu"
)

$cleanupItems = @(
  "🗑️  Prune Stopped Containers",
  "🗑️  Remove Dangling Images",
  "🗑️  Remove ALL Project Images",
  "⬅️ Back to Main Menu"
)

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

function Get-WorkspaceItems {
  param(
    [int]$Width = 80
  )
  $items = New-Object System.Collections.Generic.List[string]
  $paths = New-Object System.Collections.Generic.List[string]

  $maxPathLen = $Width - 25
  if ($maxPathLen -lt 15) { $maxPathLen = 15 }

  # 1. Current directory
  $launchDirResolved = _ai_docker_resolve_dir -Path $launchDir
  $launchProfile = ""
  if ($launchDirResolved -ne $HOME) {
    $pProf = _ai_docker_get_project_profile -TargetPath $launchDirResolved
    $launchProfile = " (profile: " + (if ($pProf) { $pProf } else { "default" }) + ")"
  }
  $truncatedLaunchDir = Get-TruncatedPath -Path $launchDirResolved -MaxLength $maxPathLen
  [void]$items.Add("📍 Current Directory: ${truncatedLaunchDir}${launchProfile}")
  [void]$paths.Add($launchDirResolved)

  # 2. Custom path option
  [void]$items.Add("✏️  Enter Custom Path...")
  [void]$paths.Add("CUSTOM")

  [void]$items.Add("──────────────────────────────────────────────────")
  [void]$paths.Add("DIVIDER")

  # 3. Recent directories from file
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
      if ($seen.Add($resolved) -and $resolved -ne $launchDirResolved) {
        $recentProfile = ""
        if ($resolved -ne $HOME) {
          $pProf = _ai_docker_get_project_profile -TargetPath $resolved
          $recentProfile = " (profile: " + (if ($pProf) { $pProf } else { "default" }) + ")"
        }
        $truncatedRecent = Get-TruncatedPath -Path $resolved -MaxLength $maxPathLen
        [void]$items.Add("🕒 Recent: ${truncatedRecent}${recentProfile}")
        [void]$paths.Add($resolved)
      }
    }
  }

  [void]$items.Add("⬅️  Back to Main Menu")
  [void]$paths.Add("BACK")

  return [PSCustomObject]@{
    Items = $items.ToArray()
    Paths = $paths.ToArray()
  }
}

function Get-RecentsItems {
  param(
    [int]$Width = 80
  )
  $items = New-Object System.Collections.Generic.List[string]
  $paths = New-Object System.Collections.Generic.List[string]

  $maxPathLen = $Width - 25
  if ($maxPathLen -lt 15) { $maxPathLen = 15 }

  $candidates = New-Object System.Collections.Generic.List[string]

  if (Test-Path -LiteralPath $script:AI_DOCKER_RECENTS_FILE -PathType Leaf) {
    foreach ($line in (Get-Content -LiteralPath $script:AI_DOCKER_RECENTS_FILE -ErrorAction SilentlyContinue)) {
      if (-not [string]::IsNullOrWhiteSpace($line) -and (Test-Path -LiteralPath $line -PathType Container)) {
        [void]$candidates.Add($line)
      }
    }
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
            [void]$candidates.Add($pPath)
          }
        }
      }
    }
  }

  $maxRecents = if ($env:AI_DOCKER_MAX_RECENTS) { [int]$env:AI_DOCKER_MAX_RECENTS } else { 30 }
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

  foreach ($candidate in $candidates) {
    if ($items.Count -ge $maxRecents) {
      break
    }
    $resolved = _ai_docker_resolve_dir -Path $candidate
    if ($seen.Add($resolved)) {
      $recentProfile = ""
      if ($resolved -ne $HOME) {
        $pProf = _ai_docker_get_project_profile -TargetPath $resolved
        $recentProfile = " (profile: " + (if ($pProf) { $pProf } else { "default" }) + ")"
      }
      $truncatedRecent = Get-TruncatedPath -Path $resolved -MaxLength $maxPathLen
      $activeTag = if ($resolved -eq $script:AI_DOCKER_ACTIVE_WORKSPACE) { " (Active)" } else { "" }
      [void]$items.Add("🕒 ${truncatedRecent}${recentProfile}${activeTag}")
      [void]$paths.Add($resolved)
    }
  }

  if ($items.Count -gt 0) {
    [void]$items.Add("──────────────────────────────────────────────────")
    [void]$paths.Add("DIVIDER")
  }

  [void]$items.Add("⬅️  Back to Main Menu")
  [void]$paths.Add("BACK")

  return [PSCustomObject]@{
    Items = $items.ToArray()
    Paths = $paths.ToArray()
  }
}

function Get-TruncatedPath {
  param(
    [string]$Path,
    [int]$MaxLength = 30
  )
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }
  if ($Path.Length -le $MaxLength) {
    return $Path
  }
  $half = [Math]::Floor(($MaxLength - 5) / 2)
  if ($half -lt 5) { $half = 5 }
  $start = $Path.Substring(0, $half)
  $end = $Path.Substring($Path.Length - $half)
  return "$start...$end"
}

function Render-Menu {
  param(
    [int]$selected
  )

  [Console]::Clear()

  $cols = 80
  try {
    if ($Host.UI.RawUI -and $Host.UI.RawUI.WindowSize.Width -gt 10) {
      $cols = $Host.UI.RawUI.WindowSize.Width
    } elseif ([Console]::WindowWidth -gt 10) {
      $cols = [Console]::WindowWidth
    }
  } catch {}

  $insideWidth = 76
  if ($cols -gt 10) {
    $insideWidth = $cols - 4
    if ($insideWidth -gt 76) { $insideWidth = 76 }
    if ($insideWidth -lt 40) { $insideWidth = 40 }
  }

  $mountPath = $script:AI_DOCKER_ACTIVE_WORKSPACE
  $baseDir = _ai_docker_get_unique_workspace_name -Path $mountPath
  if ([string]::IsNullOrWhiteSpace($baseDir) -or $baseDir -eq "." -or $baseDir -eq "/") {
    $baseDir = "project"
  }

  $topBorder = "─" * $insideWidth
  $titleText = "AI CLI IN DOCKER - CONTROL TUI"
  $padding = $insideWidth - $titleText.Length
  if ($padding -lt 0) { $padding = 0 }
  $leftPad = [Math]::Floor($padding / 2)
  $rightPad = $padding - $leftPad

  $leftSpaces = " " * $leftPad
  $rightSpaces = " " * $rightPad

  Write-Host "┌$topBorder┐" -ForegroundColor Cyan
  Write-Host "│$leftSpaces$titleText$rightSpaces│" -ForegroundColor Cyan
  Write-Host "└$topBorder┘" -ForegroundColor Cyan
  Write-Host ""

  switch ($script:current_menu) {
    "main" {
      Write-Host "  Select an action to launch or manage:" -ForegroundColor Gray
      Write-Host ""

      $claudeStatus = Get-ImageState -ImageName $script:CLAUDE_IMAGE_NAME
      $antigravityStatus = Get-ImageState -ImageName $script:ANTIGRAVITY_IMAGE_NAME
      $codexStatus = Get-ImageState -ImageName $script:CODEX_IMAGE_NAME
      $opencodeStatus = Get-ImageState -ImageName $script:OPENCODE_IMAGE_NAME

      $statuses = @(
        $claudeStatus,
        $claudeStatus,
        $claudeStatus,
        $antigravityStatus,
        $codexStatus,
        $opencodeStatus,
        "", "", "", "", "", "", ""
      )

      $mainItems = Get-MainItems
      for ($i = 0; $i -lt $mainItems.Length; $i++) {
        $itemText = $mainItems[$i]
        $isSelected = ($i -eq $selected)

        if ($itemText.StartsWith("──")) {
          $divLine = "─" * ($insideWidth - 4)
          Write-Host "  $divLine" -ForegroundColor Gray
          continue
        }

        if ($isSelected) {
          Write-Host "  " -NoNewline
          Write-Host "▸ " -ForegroundColor Cyan -NoNewline
        } else {
          Write-Host "    " -NoNewline
        }

        if ($i -lt 6) {
          $status = $statuses[$i]
          $statusColor = if ($status -eq "Built") { "Green" } else { "Red" }

          if ($isSelected) {
            $prefixLen = 40 + $status.Length
            $maxMappingLen = $cols - $prefixLen - 2
            $truncatedBaseDir = if ($baseDir.Length -gt 15) { $baseDir.Substring(0, 12) + "..." } else { $baseDir }
            $constantLen = 26 + $truncatedBaseDir.Length
            $pathSpace = $maxMappingLen - $constantLen

            if ($pathSpace -ge 12) {
              $truncatedPath = Get-TruncatedPath -Path $mountPath -MaxLength $pathSpace
              $itemMapping = " (mounts: $truncatedPath -> /workspace/$truncatedBaseDir)"
            } else {
              $maxMinimalLen = $maxMappingLen - 3
              if ($maxMinimalLen -ge 10) {
                $truncatedPath = Get-TruncatedPath -Path $mountPath -MaxLength $maxMinimalLen
                $itemMapping = " [$truncatedPath]"
              } else {
                $itemMapping = ""
              }
            }

            Write-Host ("{0,-32}" -f $itemText) -ForegroundColor White -NoNewline
            Write-Host " [" -NoNewline
            Write-Host $status -ForegroundColor $statusColor -NoNewline
            Write-Host "]" -ForegroundColor Gray -NoNewline
            if ($itemMapping) {
              Write-Host $itemMapping -ForegroundColor Gray
            } else {
              Write-Host ""
            }
          } else {
            Write-Host ("{0,-32}" -f $itemText) -ForegroundColor Gray -NoNewline
            Write-Host " [" -NoNewline
            Write-Host $status -ForegroundColor $statusColor -NoNewline
            Write-Host "]" -ForegroundColor Gray
          }
        } else {
          if ($isSelected) {
            Write-Host $itemText -ForegroundColor White
          } else {
            Write-Host $itemText -ForegroundColor Gray
          }
        }
      }
    }

    "profile" {
      Write-Host "  Select or change the active profile:" -ForegroundColor Gray
      $activeProfile = if ($script:AI_DOCKER_PROFILE) { $script:AI_DOCKER_PROFILE } else { "default" }
      Write-Host "  Current active profile: " -NoNewline
      Write-Host $activeProfile -ForegroundColor Green
      Write-Host ""

      $profileMenu = Get-ProfileItems
      $items = $profileMenu.Items

      for ($i = 0; $i -lt $items.Length; $i++) {
        $itemText = $items[$i]
        $isSelected = ($i -eq $selected)

        if ($itemText.StartsWith("──")) {
          $divLine = "─" * ($insideWidth - 4)
          Write-Host "  $divLine" -ForegroundColor Gray
          continue
        }

        if ($isSelected) {
          Write-Host "  ▸ " -ForegroundColor Cyan -NoNewline
          Write-Host $itemText -ForegroundColor White
        } else {
          Write-Host "    $itemText" -ForegroundColor Gray
        }
      }
    }

    "build" {
      Write-Host "  Select an image to build/rebuild:" -ForegroundColor Gray
      Write-Host ""

      for ($i = 0; $i -lt $buildItems.Length; $i++) {
        $isSelected = ($i -eq $selected)
        if ($isSelected) {
          Write-Host "  ▸ " -ForegroundColor Cyan -NoNewline
          Write-Host $buildItems[$i] -ForegroundColor White
        } else {
          Write-Host "    $($buildItems[$i])" -ForegroundColor Gray
        }
      }
    }

    "config" {
      Write-Host "  Select an environment config to edit:" -ForegroundColor Gray
      Write-Host ""

      for ($i = 0; $i -lt $configItems.Length; $i++) {
        $isSelected = ($i -eq $selected)
        if ($isSelected) {
          Write-Host "  ▸ " -ForegroundColor Cyan -NoNewline
          Write-Host $configItems[$i] -ForegroundColor White
        } else {
          Write-Host "    $($configItems[$i])" -ForegroundColor Gray
        }
      }
    }

    "cleanup" {
      Write-Host "  Select a cleanup action:" -ForegroundColor Gray
      Write-Host ""

      for ($i = 0; $i -lt $cleanupItems.Length; $i++) {
        $isSelected = ($i -eq $selected)
        if ($isSelected) {
          Write-Host "  ▸ " -ForegroundColor Cyan -NoNewline
          Write-Host $cleanupItems[$i] -ForegroundColor White
        } else {
          Write-Host "    $($cleanupItems[$i])" -ForegroundColor Gray
        }
      }
    }

    "workspace" {
      Write-Host "  Select or change the active workspace directory:" -ForegroundColor Gray
      Write-Host "  Current active: " -NoNewline
      Write-Host $script:AI_DOCKER_ACTIVE_WORKSPACE -ForegroundColor Green
      Write-Host ""

      $workspaceMenu = Get-WorkspaceItems -Width $cols
      $items = $workspaceMenu.Items

      for ($i = 0; $i -lt $items.Length; $i++) {
        $itemText = $items[$i]
        $isSelected = ($i -eq $selected)

        if ($itemText.StartsWith("──")) {
          $divLine = "─" * ($insideWidth - 4)
          Write-Host "  $divLine" -ForegroundColor Gray
          continue
        }

        if ($isSelected) {
          Write-Host "  ▸ " -ForegroundColor Cyan -NoNewline
          Write-Host $itemText -ForegroundColor White
        } else {
          Write-Host "    $itemText" -ForegroundColor Gray
        }
      }
    }

    "recents" {
      Write-Host "  Select a recent project to set as active workspace:" -ForegroundColor Gray
      Write-Host ""

      $recentsMenu = Get-RecentsItems -Width $cols
      $items = $recentsMenu.Items

      for ($i = 0; $i -lt $items.Length; $i++) {
        $itemText = $items[$i]
        $isSelected = ($i -eq $selected)

        if ($itemText.StartsWith("──")) {
          $divLine = "─" * ($insideWidth - 4)
          Write-Host "  $divLine" -ForegroundColor Gray
          continue
        }

        if ($isSelected) {
          Write-Host "  ▸ " -ForegroundColor Cyan -NoNewline
          Write-Host $itemText -ForegroundColor White
        } else {
          Write-Host "    $itemText" -ForegroundColor Gray
        }
      }
    }

    "profile_actions" {
      Write-Host "  Profile Actions for: " -NoNewline
      Write-Host $script:selected_profile_name -ForegroundColor Green
      Write-Host ""

      for ($i = 0; $i -lt $script:profileActionItems.Length; $i++) {
        $isSelected = ($i -eq $selected)
        if ($isSelected) {
          Write-Host "  ▸ " -ForegroundColor Cyan -NoNewline
          Write-Host $script:profileActionItems[$i] -ForegroundColor White
        } else {
          Write-Host "    $($script:profileActionItems[$i])" -ForegroundColor Gray
        }
      }
    }
  }

  Write-Host ""
  $footerLine = "─" * ($insideWidth + 2)
  Write-Host $footerLine -ForegroundColor Cyan

  $helpText = " [Use Up/Down Arrows or J/K to navigate, Enter to select, Q/Esc to go back/exit]"
  if ($cols -lt 82) {
    $helpText = " [Arrows/Vim to navigate, Enter to select, Q/Esc to exit]"
    if ($cols -lt 60) {
      $helpText = " [Arrows/Enter/Q]"
    }
  }
  Write-Host $helpText -ForegroundColor Gray
}

function Move-Selection {
  param(
    [string]$direction,
    [int]$len
  )

  if ($direction -eq "UP") {
    $script:selected_index = ($script:selected_index - 1 + $len) % $len
    # Skip dividers
    if ($script:current_menu -eq "main") {
      $mainItems = Get-MainItems
      if ($mainItems[$script:selected_index].StartsWith("──")) {
        $script:selected_index = ($script:selected_index - 1 + $len) % $len
      }
    } elseif ($script:current_menu -eq "workspace") {
      $workspaceMenu = Get-WorkspaceItems
      if ($workspaceMenu.Items[$script:selected_index].StartsWith("──")) {
        $script:selected_index = ($script:selected_index - 1 + $len) % $len
      }
    } elseif ($script:current_menu -eq "recents") {
      $recentsMenu = Get-RecentsItems
      if ($recentsMenu.Items[$script:selected_index].StartsWith("──")) {
        $script:selected_index = ($script:selected_index - 1 + $len) % $len
      }
    } elseif ($script:current_menu -eq "profile") {
      $profileMenu = Get-ProfileItems
      if ($profileMenu.Items[$script:selected_index].StartsWith("──")) {
        $script:selected_index = ($script:selected_index - 1 + $len) % $len
      }
    }
  } else {
    $script:selected_index = ($script:selected_index + 1) % $len
    # Skip dividers
    if ($script:current_menu -eq "main") {
      $mainItems = Get-MainItems
      if ($mainItems[$script:selected_index].StartsWith("──")) {
        $script:selected_index = ($script:selected_index + 1) % $len
      }
    } elseif ($script:current_menu -eq "workspace") {
      $workspaceMenu = Get-WorkspaceItems
      if ($workspaceMenu.Items[$script:selected_index].StartsWith("──")) {
        $script:selected_index = ($script:selected_index + 1) % $len
      }
    } elseif ($script:current_menu -eq "recents") {
      $recentsMenu = Get-RecentsItems
      if ($recentsMenu.Items[$script:selected_index].StartsWith("──")) {
        $script:selected_index = ($script:selected_index + 1) % $len
      }
    } elseif ($script:current_menu -eq "profile") {
      $profileMenu = Get-ProfileItems
      if ($profileMenu.Items[$script:selected_index].StartsWith("──")) {
        $script:selected_index = ($script:selected_index + 1) % $len
      }
    }
  }
}

function Get-MenuLength {
  switch ($script:current_menu) {
    "main" { return (Get-MainItems).Length }
    "profile" {
      $profileMenu = Get-ProfileItems
      return $profileMenu.Items.Length
    }
    "profile_actions" { return $script:profileActionItems.Length }
    "build" { return $buildItems.Length }
    "config" { return $configItems.Length }
    "cleanup" { return $cleanupItems.Length }
    "workspace" {
      $workspaceMenu = Get-WorkspaceItems
      return $workspaceMenu.Items.Length
    }
    "recents" {
      $recentsMenu = Get-RecentsItems
      return $recentsMenu.Items.Length
    }
  }
}

function Handle-Back {
  if ($script:current_menu -eq "profile_actions") {
    $script:current_menu = "profile"
    $script:selected_index = 0
    return $false
  }
  if ($script:current_menu -ne "main") {
    $script:current_menu = "main"
    $script:selected_index = 0
    return $false
  }
  return $true
}

function Launch-Tool {
  param(
    [string]$ImageName,
    [scriptblock]$BuildFunc,
    [scriptblock]$ShellFunc
  )

  $status = Get-ImageState -ImageName $ImageName
  if ($status -ne "Built") {
    [Console]::Clear()
    Write-Host "Warning: Image '$ImageName' is not built yet." -ForegroundColor Yellow
    $choice = Read-Host "Would you like to build it now? [Y/n]"
    if ($choice -match '^(n|no)$') {
      return
    }
    Write-Host "Building image..."
    $res = & $BuildFunc
    if ($LASTEXITCODE -ne 0 -or ($null -ne $res -and $res -ne 0)) {
      Write-Host "Build failed." -ForegroundColor Red
      Read-Host "Press [Enter] to return to menu..."
      return
    }
  }

  [Console]::Clear()
  Write-Host "Launching container session..."
  Write-Host "Close tmux session or type 'exit' inside the tmux window to return to command line."
  Write-Host ""

  & $ShellFunc -Path $script:AI_DOCKER_ACTIVE_WORKSPACE
  $exitCode = $LASTEXITCODE

  while ([Console]::KeyAvailable) {
    [void][Console]::ReadKey($true)
  }

  if ($null -eq $exitCode) { $exitCode = 0 }
  exit $exitCode
}

function Run-Build {
  param(
    [scriptblock]$BuildFunc
  )

  [Console]::Clear()
  Write-Host "Running build command..." -ForegroundColor Cyan
  Write-Host ""
  
  $res = & $BuildFunc
  Write-Host ""
  if ($LASTEXITCODE -eq 0 -and ($null -eq $res -or $res -eq 0)) {
    Write-Host "Build completed successfully!" -ForegroundColor Green
  } else {
    Write-Host "Build process failed." -ForegroundColor Red
  }
  Write-Host ""
  Read-Host "Press [Enter] to return to build menu..."
}

function Run-Cleanup {
  param(
    [string]$Action
  )

  [Console]::Clear()
  switch ($Action) {
    "prune_containers" {
      Write-Host "Pruning stopped containers..." -ForegroundColor Cyan
      docker container prune -f
    }
    "prune_images" {
      Write-Host "Pruning dangling images..." -ForegroundColor Cyan
      docker image prune -f
    }
    "remove_all_images" {
      Write-Host "Removing all project images..." -ForegroundColor Cyan
      docker rmi -f $script:CLAUDE_IMAGE_NAME $script:ANTIGRAVITY_IMAGE_NAME $script:CODEX_IMAGE_NAME $script:OPENCODE_IMAGE_NAME 2>$null
    }
  }
  Write-Host ""
  Read-Host "Press [Enter] to return to cleanup menu..."
}

function Handle-Select {
  switch ($script:current_menu) {
    "main" {
      switch ($script:selected_index) {
        0 {
            $env:AI_COMMAND = 'claude --continue || claude'
            Launch-Tool -ImageName $script:CLAUDE_IMAGE_NAME -BuildFunc { claude-docker-build } -ShellFunc { param($Path) claude-docker-shell -Path $Path }
            Remove-Item Env:\AI_COMMAND -ErrorAction SilentlyContinue
        }
        1 {
            $env:AI_COMMAND = 'claude --permission-mode auto --continue || claude --permission-mode auto'
            Launch-Tool -ImageName $script:CLAUDE_IMAGE_NAME -BuildFunc { claude-docker-build } -ShellFunc { param($Path) claude-docker-shell -Path $Path }
            Remove-Item Env:\AI_COMMAND -ErrorAction SilentlyContinue
        }
        2 {
            $env:AI_COMMAND = 'claude --dangerously-skip-permissions --continue || claude --dangerously-skip-permissions'
            Launch-Tool -ImageName $script:CLAUDE_IMAGE_NAME -BuildFunc { claude-docker-build } -ShellFunc { param($Path) claude-docker-shell -Path $Path }
            Remove-Item Env:\AI_COMMAND -ErrorAction SilentlyContinue
        }
        3 { Launch-Tool -ImageName $script:ANTIGRAVITY_IMAGE_NAME -BuildFunc { antigravity-docker-build } -ShellFunc { param($Path) antigravity-docker-shell -Path $Path } }
        4 { Launch-Tool -ImageName $script:CODEX_IMAGE_NAME -BuildFunc { codex-docker-build } -ShellFunc { param($Path) codex-docker-shell -Path $Path } }
        5 { Launch-Tool -ImageName $script:OPENCODE_IMAGE_NAME -BuildFunc { opencode-docker-build } -ShellFunc { param($Path) opencode-docker-shell -Path $Path } }
        6 { } # Divider
        7 { $script:current_menu = "workspace"; $script:selected_index = 0 }
        8 { $script:current_menu = "recents"; $script:selected_index = 0 }
        9 { $script:current_menu = "profile"; $script:selected_index = 0 }
        10 { } # Divider
        11 { $script:current_menu = "build"; $script:selected_index = 0 }
        12 { $script:current_menu = "config"; $script:selected_index = 0 }
        13 { $script:current_menu = "cleanup"; $script:selected_index = 0 }
        14 { return $true } # Exit
      }
    }
    "profile" {
      $profileMenu = Get-ProfileItems
      $name = $profileMenu.Names[$script:selected_index]
      switch ($name) {
        "CREATE" {
          [Console]::Clear()
          Write-Host "Create New Profile" -ForegroundColor White
          Write-Host "Type a name for the new profile (alphanumeric, dashes, underscores)." -ForegroundColor Gray
          Write-Host ""
          $newProfileName = Read-Host "Profile Name"
          if (-not [string]::IsNullOrWhiteSpace($newProfileName)) {
            $newProfileName = $newProfileName -replace '[^a-zA-Z0-9_-]', ''
            if (-not [string]::IsNullOrWhiteSpace($newProfileName)) {
              $activeProfileFile = Join-Path $HOME ".ai-docker-active-profile"
              $newProfileName | Out-File -LiteralPath $activeProfileFile -Force -NoNewline -Encoding utf8
              _ai_docker_load_profile -TargetProfile $newProfileName
              Write-Host "Profile '$newProfileName' created and activated." -ForegroundColor Green
            } else {
              Write-Host "Error: Invalid profile name." -ForegroundColor Red
            }
          } else {
            Write-Host "Cancelled." -ForegroundColor Gray
          }
          Start-Sleep -Milliseconds 1500
          $script:current_menu = "main"
          $script:selected_index = 5
        }
        "DIVIDER" { }
        "BACK" { [void](Handle-Back) }
        default {
          if ($name -eq "default") {
            $activeProfileFile = Join-Path $HOME ".ai-docker-active-profile"
            $name | Out-File -LiteralPath $activeProfileFile -Force -NoNewline -Encoding utf8
            _ai_docker_load_profile -TargetProfile $name -Directory $script:AI_DOCKER_ACTIVE_WORKSPACE
            if ($script:AI_DOCKER_ACTIVE_WORKSPACE -ne $HOME) {
              _ai_docker_set_project_profile -TargetPath $script:AI_DOCKER_ACTIVE_WORKSPACE -ProfileName $name
            }
            $script:current_menu = "main"
            $script:selected_index = 5
          } else {
            $script:selected_profile_name = $name
            $script:current_menu = "profile_actions"
            $script:selected_index = 0
          }
        }
      }
    }
    "profile_actions" {
      switch ($script:selected_index) {
        0 { # Activate Profile
          $activeProfileFile = Join-Path $HOME ".ai-docker-active-profile"
          $script:selected_profile_name | Out-File -LiteralPath $activeProfileFile -Force -NoNewline -Encoding utf8
          _ai_docker_load_profile -TargetProfile $script:selected_profile_name -Directory $script:AI_DOCKER_ACTIVE_WORKSPACE
          if ($script:AI_DOCKER_ACTIVE_WORKSPACE -ne $HOME) {
            _ai_docker_set_project_profile -TargetPath $script:AI_DOCKER_ACTIVE_WORKSPACE -ProfileName $script:selected_profile_name
          }
          $script:current_menu = "main"
          $script:selected_index = 5
        }
        1 { # Rename Profile
          [Console]::Clear()
          Write-Host "Rename Profile: $script:selected_profile_name" -ForegroundColor White
          Write-Host "Type a new name for the profile (alphanumeric, dashes, underscores)." -ForegroundColor Gray
          Write-Host ""
          $newName = Read-Host "New Name"
          if (-not [string]::IsNullOrWhiteSpace($newName)) {
            $newName = $newName -replace '[^a-zA-Z0-9_-]', ''
            if (-not [string]::IsNullOrWhiteSpace($newName) -and $newName -ne "default") {
              $oldDir = Join-Path (Join-Path $HOME ".ai-docker-profiles") $script:selected_profile_name
              $newDir = Join-Path (Join-Path $HOME ".ai-docker-profiles") $newName
              if (Test-Path -LiteralPath $oldDir -PathType Container) {
                if (Test-Path -LiteralPath $newDir -PathType Container) {
                  Write-Host "Error: Profile '$newName' already exists." -ForegroundColor Red
                  Start-Sleep -Milliseconds 1500
                } else {
                  Rename-Item -LiteralPath $oldDir -NewName $newName -Force -ErrorAction Stop
                  $currentActive = if ($script:AI_DOCKER_PROFILE) { $script:AI_DOCKER_PROFILE } else { "default" }
                  if ($currentActive -eq $script:selected_profile_name) {
                    $activeProfileFile = Join-Path $HOME ".ai-docker-active-profile"
                    $newName | Out-File -LiteralPath $activeProfileFile -Force -NoNewline -Encoding utf8
                  }
                  # Update mapping file
                  $mapFile = Join-Path (Join-Path $HOME ".ai-docker-profiles") "project-profiles"
                  if (Test-Path -LiteralPath $mapFile -PathType Leaf) {
                    $tmpMap = "$mapFile.tmp"
                    $lines = Get-Content -LiteralPath $mapFile -ErrorAction SilentlyContinue
                    $newLines = [System.Collections.Generic.List[string]]::new()
                    if ($lines) {
                      foreach ($line in $lines) {
                        if ([string]::IsNullOrWhiteSpace($line)) { continue }
                        $lastColon = $line.LastIndexOf(':')
                        if ($lastColon -gt 0) {
                          $pPath = $line.Substring(0, $lastColon)
                          $pProfile = $line.Substring($lastColon + 1)
                          if ($pProfile -eq $script:selected_profile_name) {
                            $newLines.Add("${pPath}:${newName}")
                          } else {
                            $newLines.Add($line)
                          }
                        } else {
                          $newLines.Add($line)
                        }
                      }
                    }
                    if ($newLines.Count -gt 0) {
                      $newLines | Set-Content -LiteralPath $tmpMap -ErrorAction Stop
                      Move-Item -LiteralPath $tmpMap -Destination $mapFile -Force -ErrorAction Stop
                    } else {
                      if (Test-Path -LiteralPath $mapFile -PathType Leaf) {
                        Remove-Item -LiteralPath $mapFile -Force -ErrorAction SilentlyContinue
                      }
                      New-Item -ItemType File -Path $mapFile -Force | Out-Null
                    }
                  }
                  _ai_docker_load_profile -TargetProfile "" -Directory $script:AI_DOCKER_ACTIVE_WORKSPACE
                  Write-Host "Profile renamed to '$newName'." -ForegroundColor Green
                  Start-Sleep -Milliseconds 1500
                }
              } else {
                $currentActive = if ($script:AI_DOCKER_PROFILE) { $script:AI_DOCKER_PROFILE } else { "default" }
                if ($currentActive -eq $script:selected_profile_name) {
                  $activeProfileFile = Join-Path $HOME ".ai-docker-active-profile"
                  $newName | Out-File -LiteralPath $activeProfileFile -Force -NoNewline -Encoding utf8
                }
                # Update mapping file
                $mapFile = Join-Path (Join-Path $HOME ".ai-docker-profiles") "project-profiles"
                if (Test-Path -LiteralPath $mapFile -PathType Leaf) {
                  $tmpMap = "$mapFile.tmp"
                  $lines = Get-Content -LiteralPath $mapFile -ErrorAction SilentlyContinue
                  $newLines = [System.Collections.Generic.List[string]]::new()
                  if ($lines) {
                    foreach ($line in $lines) {
                      if ([string]::IsNullOrWhiteSpace($line)) { continue }
                      $lastColon = $line.LastIndexOf(':')
                      if ($lastColon -gt 0) {
                        $pPath = $line.Substring(0, $lastColon)
                        $pProfile = $line.Substring($lastColon + 1)
                        if ($pProfile -eq $script:selected_profile_name) {
                          $newLines.Add("${pPath}:${newName}")
                        } else {
                          $newLines.Add($line)
                        }
                      } else {
                        $newLines.Add($line)
                      }
                    }
                  }
                  if ($newLines.Count -gt 0) {
                    $newLines | Set-Content -LiteralPath $tmpMap -ErrorAction Stop
                    Move-Item -LiteralPath $tmpMap -Destination $mapFile -Force -ErrorAction Stop
                  } else {
                    if (Test-Path -LiteralPath $mapFile -PathType Leaf) {
                      Remove-Item -LiteralPath $mapFile -Force -ErrorAction SilentlyContinue
                    }
                    New-Item -ItemType File -Path $mapFile -Force | Out-Null
                  }
                }
                _ai_docker_load_profile -TargetProfile "" -Directory $script:AI_DOCKER_ACTIVE_WORKSPACE
                Write-Host "Profile name updated to '$newName'." -ForegroundColor Green
                Start-Sleep -Milliseconds 1500
              }
            } else {
              Write-Host "Error: Invalid profile name." -ForegroundColor Red
              Start-Sleep -Milliseconds 1500
            }
          } else {
            Write-Host "Cancelled." -ForegroundColor Gray
            Start-Sleep -Milliseconds 1000
          }
          $script:current_menu = "profile"
          $script:selected_index = 0
        }
        2 { # Delete Profile
          [Console]::Clear()
          Write-Host "Delete Profile: $script:selected_profile_name" -ForegroundColor Red
          Write-Host "Are you sure you want to delete this profile? All settings will be lost." -ForegroundColor Gray
          Write-Host ""
          $confirm = Read-Host "Type 'yes' to confirm"
          if ($confirm -eq "yes") {
            $oldDir = Join-Path (Join-Path $HOME ".ai-docker-profiles") $script:selected_profile_name
            if (Test-Path -LiteralPath $oldDir -PathType Container) {
              Remove-Item -Path $oldDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            $currentActive = if ($script:AI_DOCKER_PROFILE) { $script:AI_DOCKER_PROFILE } else { "default" }
            if ($currentActive -eq $script:selected_profile_name) {
              $activeProfileFile = Join-Path $HOME ".ai-docker-active-profile"
              "default" | Out-File -LiteralPath $activeProfileFile -Force -NoNewline -Encoding utf8
            }
            # Update mapping file
            $mapFile = Join-Path (Join-Path $HOME ".ai-docker-profiles") "project-profiles"
            if (Test-Path -LiteralPath $mapFile -PathType Leaf) {
              $tmpMap = "$mapFile.tmp"
              $lines = Get-Content -LiteralPath $mapFile -ErrorAction SilentlyContinue
              $newLines = [System.Collections.Generic.List[string]]::new()
              if ($lines) {
                foreach ($line in $lines) {
                  if ([string]::IsNullOrWhiteSpace($line)) { continue }
                  $lastColon = $line.LastIndexOf(':')
                  if ($lastColon -gt 0) {
                    $pPath = $line.Substring(0, $lastColon)
                    $pProfile = $line.Substring($lastColon + 1)
                    if ($pProfile -ne $script:selected_profile_name) {
                      $newLines.Add($line)
                    }
                  } else {
                    $newLines.Add($line)
                  }
                }
              }
              if ($newLines.Count -gt 0) {
                $newLines | Set-Content -LiteralPath $tmpMap -ErrorAction Stop
                Move-Item -LiteralPath $tmpMap -Destination $mapFile -Force -ErrorAction Stop
              } else {
                if (Test-Path -LiteralPath $mapFile -PathType Leaf) {
                  Remove-Item -LiteralPath $mapFile -Force -ErrorAction SilentlyContinue
                }
                New-Item -ItemType File -Path $mapFile -Force | Out-Null
              }
            }
            _ai_docker_load_profile -TargetProfile "" -Directory $script:AI_DOCKER_ACTIVE_WORKSPACE
            Write-Host "Profile deleted." -ForegroundColor Green
            Start-Sleep -Milliseconds 1500
          } else {
            Write-Host "Cancelled." -ForegroundColor Gray
            Start-Sleep -Milliseconds 1000
          }
          $script:current_menu = "profile"
          $script:selected_index = 0
        }
        3 { # Back
          $script:current_menu = "profile"
          $script:selected_index = 0
        }
      }
    }
    "build" {
      switch ($script:selected_index) {
        0 { Run-Build -BuildFunc { claude-docker-build -NoCache } }
        1 { Run-Build -BuildFunc { antigravity-docker-build -NoCache } }
        2 { Run-Build -BuildFunc { codex-docker-build -NoCache } }
        3 { Run-Build -BuildFunc { opencode-docker-build -NoCache } }
        4 { Run-Build -BuildFunc { docker-ai-build-all } }
        5 { [void](Handle-Back) }
      }
    }
    "config" {
      switch ($script:selected_index) {
        0 { Edit-EnvFile -Path (Join-Path $script:CLAUDE_CONFIG_PATH 'docker-env.env') }
        1 { Edit-EnvFile -Path (Join-Path $script:ANTIGRAVITY_CONFIG_PATH 'docker-env.env') }
        2 { Edit-EnvFile -Path (Join-Path $script:CODEX_CONFIG_PATH 'docker-env.env') }
        3 { Edit-EnvFile -Path (Join-Path $script:OPENCODE_DOCKER_DIR 'docker-env.env') }
        4 { [void](Handle-Back) }
      }
    }
    "cleanup" {
      switch ($script:selected_index) {
        0 { Run-Cleanup -Action "prune_containers" }
        1 { Run-Cleanup -Action "prune_images" }
        2 { Run-Cleanup -Action "remove_all_images" }
        3 { [void](Handle-Back) }
      }
    }
    "workspace" {
      $workspaceMenu = Get-WorkspaceItems
      $path = $workspaceMenu.Paths[$script:selected_index]
      switch ($path) {
        "CUSTOM" {
          [Console]::Clear()
          Write-Host "Enter Custom Workspace Path" -ForegroundColor White
          Write-Host "You can type an absolute or relative path to a directory." -ForegroundColor Gray
          Write-Host ""
          $customInput = Read-Host "Path"
          if (-not [string]::IsNullOrWhiteSpace($customInput)) {
            if ($customInput.StartsWith("~")) {
              $customInput = Join-Path $HOME $customInput.Substring(1).TrimStart('\','/')
            }
            if (Test-Path -LiteralPath $customInput -PathType Container) {
              Activate-Workspace $customInput
              _ai_docker_update_recents -PathToAdd $script:AI_DOCKER_ACTIVE_WORKSPACE
              Write-Host "Active workspace directory set to: $script:AI_DOCKER_ACTIVE_WORKSPACE" -ForegroundColor Green
            } else {
              Write-Host "Error: Directory '$customInput' does not exist." -ForegroundColor Red
            }
          } else {
            Write-Host "Cancelled." -ForegroundColor Gray
          }
          Start-Sleep -Milliseconds 1500
        }
        "DIVIDER" { }
        "BACK" { [void](Handle-Back) }
        default {
          if (Test-Path -LiteralPath $path -PathType Container) {
            Activate-Workspace $path
            _ai_docker_update_recents -PathToAdd $script:AI_DOCKER_ACTIVE_WORKSPACE
            $script:current_menu = "main"
            $script:selected_index = 0
          } else {
            Write-Host "Error: Directory '$path' no longer exists." -ForegroundColor Red
            Start-Sleep -Milliseconds 1500
          }
        }
      }
    }
    "recents" {
      $recentsMenu = Get-RecentsItems
      $path = $recentsMenu.Paths[$script:selected_index]
      switch ($path) {
        "DIVIDER" { }
        "BACK" { [void](Handle-Back) }
        default {
          if (Test-Path -LiteralPath $path -PathType Container) {
            Activate-Workspace $path
            _ai_docker_update_recents -PathToAdd $script:AI_DOCKER_ACTIVE_WORKSPACE
            $script:current_menu = "main"
            $script:selected_index = 0
          } else {
            Write-Host "Error: Directory '$path' no longer exists." -ForegroundColor Red
            Start-Sleep -Milliseconds 1500
          }
        }
      }
    }
  }
  return $false
}

function Read-Key {
  while ([Console]::KeyAvailable) {
    [void][Console]::ReadKey($true)
  }
  $keyInfo = [Console]::ReadKey($true)
  switch ($keyInfo.Key) {
    'UpArrow' { return "UP" }
    'DownArrow' { return "DOWN" }
    'Enter' { return "ENTER" }
    'Escape' { return "QUIT" }
  }
  switch ($keyInfo.KeyChar) {
    'k' { return "UP" }
    'j' { return "DOWN" }
    'q' { return "QUIT" }
    '0' { return "0" }
    '1' { return "1" }
    '2' { return "2" }
    '3' { return "3" }
    '4' { return "4" }
    '5' { return "5" }
    '6' { return "6" }
    '7' { return "7" }
    '8' { return "8" }
    '9' { return "9" }
  }
  return "NONE"
}

# Main loop
while ($true) {
  $len = Get-MenuLength
  Render-Menu -selected $script:selected_index
  
  $key = Read-Key
  if ($key -eq "UP") {
    Move-Selection -direction "UP" -len $len
  } elseif ($key -eq "DOWN") {
    Move-Selection -direction "DOWN" -len $len
  } elseif ($key -eq "ENTER") {
    if (Handle-Select) {
      break
    }
  } elseif ($key -eq "QUIT") {
    if (Handle-Back) {
      break
    }
  } elseif ($key -match '^[0-9]$') {
    $shouldBreak = $false
    if ($script:current_menu -eq "main") {
      switch ($key) {
        '1' { $script:selected_index = 0; if (Handle-Select) { $shouldBreak = $true } }
        '2' { $script:selected_index = 1; if (Handle-Select) { $shouldBreak = $true } }
        '3' { $script:selected_index = 2; if (Handle-Select) { $shouldBreak = $true } }
        '4' { $script:selected_index = 3; if (Handle-Select) { $shouldBreak = $true } }
        '5' { $script:selected_index = 4; if (Handle-Select) { $shouldBreak = $true } }
        '6' { $script:selected_index = 5; if (Handle-Select) { $shouldBreak = $true } }
        '7' { $script:selected_index = 7; if (Handle-Select) { $shouldBreak = $true } }
        '8' { $script:selected_index = 8; if (Handle-Select) { $shouldBreak = $true } }
        '9' { $script:selected_index = 9; if (Handle-Select) { $shouldBreak = $true } }
        '0' { $script:selected_index = 10; if (Handle-Select) { $shouldBreak = $true } }
      }
    } elseif ($script:current_menu -eq "profile") {
      $profileMenu = Get-ProfileItems
      $items = $profileMenu.Items
      if ($key -eq '1') {
        $script:selected_index = 0; if (Handle-Select) { $shouldBreak = $true }
      } elseif ($key -eq '2') {
        $script:selected_index = 1; if (Handle-Select) { $shouldBreak = $true }
      } elseif ($key -eq '3') {
        $script:selected_index = 2; if (Handle-Select) { $shouldBreak = $true }
      } elseif ($key -eq '0') {
        $script:selected_index = $items.Length - 1; if (Handle-Select) { $shouldBreak = $true }
      } else {
        $digitVal = [int][string]$key
        $idx = $digitVal - 1
        if ($idx -ge 0 -and $idx -lt $items.Length - 1 -and -not $items[$idx].StartsWith("──")) {
          $script:selected_index = $idx; if (Handle-Select) { $shouldBreak = $true }
        }
      }
    } elseif ($script:current_menu -eq "profile_actions") {
      switch ($key) {
        '1' { $script:selected_index = 0; if (Handle-Select) { $shouldBreak = $true } }
        '2' { $script:selected_index = 1; if (Handle-Select) { $shouldBreak = $true } }
        '3' { $script:selected_index = 2; if (Handle-Select) { $shouldBreak = $true } }
        '0' { $script:selected_index = 3; if (Handle-Select) { $shouldBreak = $true } }
      }
    } elseif ($script:current_menu -eq "build") {
      switch ($key) {
        '1' { $script:selected_index = 0; if (Handle-Select) { $shouldBreak = $true } }
        '2' { $script:selected_index = 1; if (Handle-Select) { $shouldBreak = $true } }
        '3' { $script:selected_index = 2; if (Handle-Select) { $shouldBreak = $true } }
        '4' { $script:selected_index = 3; if (Handle-Select) { $shouldBreak = $true } }
        '5' { $script:selected_index = 4; if (Handle-Select) { $shouldBreak = $true } }
        '0' { $script:selected_index = 5; if (Handle-Select) { $shouldBreak = $true } }
      }
    } elseif ($script:current_menu -eq "config") {
      switch ($key) {
        '1' { $script:selected_index = 0; if (Handle-Select) { $shouldBreak = $true } }
        '2' { $script:selected_index = 1; if (Handle-Select) { $shouldBreak = $true } }
        '3' { $script:selected_index = 2; if (Handle-Select) { $shouldBreak = $true } }
        '4' { $script:selected_index = 3; if (Handle-Select) { $shouldBreak = $true } }
        '0' { $script:selected_index = 4; if (Handle-Select) { $shouldBreak = $true } }
      }
    } elseif ($script:current_menu -eq "cleanup") {
      switch ($key) {
        '1' { $script:selected_index = 0; if (Handle-Select) { $shouldBreak = $true } }
        '2' { $script:selected_index = 1; if (Handle-Select) { $shouldBreak = $true } }
        '3' { $script:selected_index = 2; if (Handle-Select) { $shouldBreak = $true } }
        '0' { $script:selected_index = 3; if (Handle-Select) { $shouldBreak = $true } }
      }
    } elseif ($script:current_menu -eq "workspace") {
      $workspaceMenu = Get-WorkspaceItems
      $items = $workspaceMenu.Items
      if ($key -eq '1') {
        $script:selected_index = 0; if (Handle-Select) { $shouldBreak = $true }
      } elseif ($key -eq '2') {
        $script:selected_index = 1; if (Handle-Select) { $shouldBreak = $true }
      } elseif ($key -eq '0') {
        $script:selected_index = $items.Length - 1; if (Handle-Select) { $shouldBreak = $true }
      } else {
        $digitVal = [int][string]$key
        if ($digitVal -lt $items.Length - 1 -and $items[$digitVal] -notmatch '──') {
          $script:selected_index = $digitVal; if (Handle-Select) { $shouldBreak = $true }
        }
      }
    }
    if ($shouldBreak) {
      break
    }
  }
}
