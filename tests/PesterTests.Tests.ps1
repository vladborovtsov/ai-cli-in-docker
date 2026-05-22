BeforeAll {
    # Dot-source activate.ps1 relative to the test script location
    . "$PSScriptRoot/../activate.ps1"
}

Describe "PowerShell Helper Functions" {
    Context "TZ and Network Detection" {
        It "Detects TimeZone successfully" {
            $tz = _ai_docker_get_tz
            $tz.Should.Not.BeNullOrEmpty()
        }

        It "Parses AI_DOCKER_USE_HOST_NETWORK environment override" {
            # Save original value
            $origNet = $env:AI_DOCKER_USE_HOST_NETWORK

            try {
                # Test default / false
                $env:AI_DOCKER_USE_HOST_NETWORK = $null
                (_ai_docker_should_use_host_network) | Should -Be $false

                # Test true cases
                foreach ($val in @('1', 'true', 'yes')) {
                    $env:AI_DOCKER_USE_HOST_NETWORK = $val
                    (_ai_docker_should_use_host_network) | Should -Be $true
                }

                # Test false cases
                foreach ($val in @('0', 'false', 'no')) {
                    $env:AI_DOCKER_USE_HOST_NETWORK = $val
                    (_ai_docker_should_use_host_network) | Should -Be $false
                }
            } finally {
                # Restore original value
                if ($origNet) {
                    $env:AI_DOCKER_USE_HOST_NETWORK = $origNet
                } else {
                    Remove-Item env:AI_DOCKER_USE_HOST_NETWORK -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }
    }

    Context "Directory and Profile Mapping" {
        BeforeEach {
            # Ensure we start with a clean state by removing test files in HOME
            $profilesDir = Join-Path $HOME ".ai-docker-profiles"
            if (Test-Path -LiteralPath $profilesDir) {
                Remove-Item -LiteralPath $profilesDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
            }
            $activeProfileFile = Join-Path $HOME ".ai-docker-active-profile"
            if (Test-Path -LiteralPath $activeProfileFile) {
                Remove-Item -LiteralPath $activeProfileFile -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }

        It "Resolves directories correctly" {
            $resolved = _ai_docker_resolve_dir -Path "."
            $resolved.Should.Not.BeNullOrEmpty()
            
            $nonExistent = "non-existent-dir-12345"
            $resolvedNonExistent = _ai_docker_resolve_dir -Path $nonExistent
            $resolvedNonExistent | Should -Be $nonExistent
        }

        It "Identifies Home Path correctly" {
            (_ai_docker_is_home_path -Path $HOME) | Should -Be $true
            
            $otherPath = Join-Path $HOME "sub-folder"
            (_ai_docker_is_home_path -Path $otherPath) | Should -Be $false
        }

        It "Gets and sets project profile mapping" {
            $testProj = Join-Path $HOME "my-test-project"
            # Initial state should be null
            $profile = _ai_docker_get_project_profile -TargetPath $testProj
            $profile | Should -BeNullOrEmpty

            # Set a mapping
            _ai_docker_set_project_profile -TargetPath $testProj -ProfileName "my-custom-profile"
            $profile = _ai_docker_get_project_profile -TargetPath $testProj
            $profile | Should -Be "my-custom-profile"

            # Update mapping
            _ai_docker_set_project_profile -TargetPath $testProj -ProfileName "another-profile"
            $profile = _ai_docker_get_project_profile -TargetPath $testProj
            $profile | Should -Be "another-profile"

            # Remove mapping (set to empty)
            _ai_docker_set_project_profile -TargetPath $testProj -ProfileName ""
            $profile = _ai_docker_get_project_profile -TargetPath $testProj
            $profile | Should -BeNullOrEmpty
        }

        It "Manages recents history list" {
            $dir1 = Join-Path $HOME "dir1"
            $dir2 = Join-Path $HOME "dir2"
            New-Item -ItemType Directory -Path $dir1 -Force | Out-Null
            New-Item -ItemType Directory -Path $dir2 -Force | Out-Null

            # We need to reload profile to make sure $script:AI_DOCKER_RECENTS_FILE path is set correctly
            _ai_docker_load_profile -TargetProfile "default" -Directory $HOME

            # Update recents
            _ai_docker_update_recents -PathToAdd $dir1
            _ai_docker_update_recents -PathToAdd $dir2

            # Recents file should exist
            Test-Path -LiteralPath $script:AI_DOCKER_RECENTS_FILE | Should -Be $true

            $lines = Get-Content -LiteralPath $script:AI_DOCKER_RECENTS_FILE
            # The most recent should be at the top
            $lines[0] | Should -Be $dir2
            $lines[1] | Should -Be $dir1
        }

        It "Handles profile commands" {
            # Activate profile
            ai-docker-profile "test-profile-ps"
            $script:AI_DOCKER_PROFILE | Should -Be "test-profile-ps"

            $activeProfileFile = Join-Path $HOME ".ai-docker-active-profile"
            Test-Path -LiteralPath $activeProfileFile | Should -Be $true
            (Get-Content -LiteralPath $activeProfileFile -Raw).Trim() | Should -Be "test-profile-ps"
        }
    }
}
