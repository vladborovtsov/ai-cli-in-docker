import os
import shutil
import subprocess
import tempfile
import unittest

class TestBashHelpers(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()
        self.old_home = os.environ.get("HOME")
        os.environ["HOME"] = self.tmp_dir
        
        # Unset profile overrides for isolation
        self.old_profile = os.environ.get("AI_DOCKER_PROFILE")
        if "AI_DOCKER_PROFILE" in os.environ:
            del os.environ["AI_DOCKER_PROFILE"]
        self.old_profile_override = os.environ.get("AI_DOCKER_PROFILE_ENV_OVERRIDE")
        if "AI_DOCKER_PROFILE_ENV_OVERRIDE" in os.environ:
            del os.environ["AI_DOCKER_PROFILE_ENV_OVERRIDE"]
            
        self.repo_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

    def tearDown(self):
        shutil.rmtree(self.tmp_dir)
        if self.old_home:
            os.environ["HOME"] = self.old_home
        else:
            del os.environ["HOME"]
            
        if self.old_profile:
            os.environ["AI_DOCKER_PROFILE"] = self.old_profile
        if self.old_profile_override:
            os.environ["AI_DOCKER_PROFILE_ENV_OVERRIDE"] = self.old_profile_override

    def run_bash(self, cmd):
        # We source activate.sh and run the cmd
        full_cmd = f"source ./activate.sh && {cmd}"
        res = subprocess.run(
            ["bash", "-c", full_cmd],
            capture_output=True,
            text=True,
            cwd=self.repo_dir
        )
        return res

    def test_detect_tz(self):
        res = self.run_bash("_ai_docker_detect_tz")
        self.assertEqual(res.returncode, 0)
        self.assertTrue(len(res.stdout.strip()) > 0)

    def test_should_use_host_network(self):
        # Default auto behaviour (true on Linux, false on Mac)
        res = self.run_bash("_ai_docker_should_use_host_network")
        is_linux = (os.uname().sysname == "Linux")
        if is_linux:
            self.assertEqual(res.returncode, 0)
        else:
            self.assertEqual(res.returncode, 1)

        # Explicit overrides
        res = self.run_bash("AI_DOCKER_USE_HOST_NETWORK=1 _ai_docker_should_use_host_network")
        self.assertEqual(res.returncode, 0)
        res = self.run_bash("AI_DOCKER_USE_HOST_NETWORK=0 _ai_docker_should_use_host_network")
        self.assertEqual(res.returncode, 1)

    def test_project_profile_mapping(self):
        # Test setting and getting profile mappings for project paths
        test_path = os.path.join(self.tmp_dir, "my_project")
        os.makedirs(test_path)
        
        # Initial check (should be empty/default)
        res = self.run_bash(f'_ai_docker_get_project_profile "{test_path}"')
        self.assertEqual(res.stdout.strip(), "")
        
        # Map profile
        res = self.run_bash(f'_ai_docker_set_project_profile "{test_path}" "custom-profile"')
        self.assertEqual(res.returncode, 0)
        
        # Get mapped profile
        res = self.run_bash(f'_ai_docker_get_project_profile "{test_path}"')
        self.assertEqual(res.stdout.strip(), "custom-profile")
        
        # Clear mapping (set to empty)
        res = self.run_bash(f'_ai_docker_set_project_profile "{test_path}" ""')
        self.assertEqual(res.returncode, 0)
        res = self.run_bash(f'_ai_docker_get_project_profile "{test_path}"')
        self.assertEqual(res.stdout.strip(), "")

    def test_recents_history(self):
        # Test update recents list
        dir1 = os.path.join(self.tmp_dir, "dir1")
        dir2 = os.path.join(self.tmp_dir, "dir2")
        os.makedirs(dir1)
        os.makedirs(dir2)
        
        res = self.run_bash(f'_ai_docker_update_recents "{dir1}" && _ai_docker_update_recents "{dir2}"')
        self.assertEqual(res.returncode, 0)
        
        # Read recents file
        recents_file = os.path.join(self.tmp_dir, ".ai-docker-profiles", "default", "ai-docker-recents")
        self.assertTrue(os.path.exists(recents_file))
        with open(recents_file, "r") as f:
            lines = [line.strip() for line in f.readlines()]
            
        # The most recent should be at the top
        self.assertEqual(lines[0], dir2)
        self.assertEqual(lines[1], dir1)

        # Reopening/reusing dir1 moves it back to the top
        res = self.run_bash(f'_ai_docker_update_recents "{dir1}"')
        self.assertEqual(res.returncode, 0)
        with open(recents_file, "r") as f:
            lines = [line.strip() for line in f.readlines()]
        self.assertEqual(lines[0], dir1)
        self.assertEqual(lines[1], dir2)

    def test_profile_command(self):
        # List profiles
        res = self.run_bash("ai-docker-profile")
        self.assertEqual(res.returncode, 0)
        self.assertIn("Current profile: default", res.stdout)
        
        # Activate custom profile
        res = self.run_bash("ai-docker-profile test-profile")
        self.assertEqual(res.returncode, 0)
        self.assertIn("Profile 'test-profile' activated", res.stdout)
        
        # Check active profile file
        active_file = os.path.join(self.tmp_dir, ".ai-docker-active-profile")
        self.assertTrue(os.path.exists(active_file))
        with open(active_file, "r") as f:
            self.assertEqual(f.read().strip(), "test-profile")

    def test_unique_workspace_name(self):
        # Under HOME
        test_path1 = os.path.join(self.tmp_dir, "projects", "projA", "_utils")
        os.makedirs(test_path1)
        res1 = self.run_bash(f'_ai_docker_get_unique_workspace_name "{test_path1}"')
        self.assertEqual(res1.stdout.strip(), "projects-projA-_utils")

        # HOME itself
        res_home = self.run_bash(f'_ai_docker_get_unique_workspace_name "{self.tmp_dir}"')
        self.assertEqual(res_home.stdout.strip(), "home")

        # Outside HOME
        res_outside = self.run_bash('_ai_docker_get_unique_workspace_name "/opt/tools/helper"')
        self.assertEqual(res_outside.stdout.strip(), "opt-tools-helper")

    def test_project_ssh_agent_settings(self):
        test_path = os.path.join(self.tmp_dir, "ssh_project")
        os.makedirs(test_path)

        # Default should be 0 (Disabled)
        res = self.run_bash(f'_ai_docker_get_project_ssh_agent "{test_path}"')
        self.assertEqual(res.stdout.strip(), "0")

        res_should = self.run_bash(f'_ai_docker_should_mount_ssh_agent "{test_path}"')
        self.assertEqual(res_should.returncode, 1) # False/Disabled

        # Enable SSH Agent
        res = self.run_bash(f'_ai_docker_set_project_ssh_agent "{test_path}" "1"')
        self.assertEqual(res.returncode, 0)

        res = self.run_bash(f'_ai_docker_get_project_ssh_agent "{test_path}"')
        self.assertEqual(res.stdout.strip(), "1")

        res_should = self.run_bash(f'_ai_docker_should_mount_ssh_agent "{test_path}"')
        self.assertEqual(res_should.returncode, 0) # True/Enabled

        # Disable SSH Agent again
        res = self.run_bash(f'_ai_docker_set_project_ssh_agent "{test_path}" "0"')
        self.assertEqual(res.returncode, 0)

        res = self.run_bash(f'_ai_docker_get_project_ssh_agent "{test_path}"')
        self.assertEqual(res.stdout.strip(), "0")

        # Explicit environment variable override
        res_env = self.run_bash(f'AI_DOCKER_ENABLE_SSH_AGENT=1 _ai_docker_should_mount_ssh_agent "{test_path}"')
        self.assertEqual(res_env.returncode, 0) # Overridden to True

        # Test migration
        proj_map = os.path.join(self.tmp_dir, ".ai-docker-profiles", "project-profiles")
        os.makedirs(os.path.dirname(proj_map), exist_ok=True)
        with open(proj_map, "w") as f:
            f.write(f"{test_path}:default\n")

        res_mig = self.run_bash("_ai_docker_migrate_project_ssh_settings")
        self.assertEqual(res_mig.returncode, 0)

        ssh_map = os.path.join(self.tmp_dir, ".ai-docker-profiles", "project-ssh-settings")
        self.assertTrue(os.path.exists(ssh_map))
        with open(ssh_map, "r") as f:
            content = f.read()
            self.assertIn("ssh_mount:", content)

    def test_all_runners_mount_ssh_agent(self):
        test_dir = os.path.join(self.tmp_dir, "runner_test_proj")
        os.makedirs(test_dir)

        runners = [
            "codex-docker-shell",
            "antigravity-docker-shell",
            "claude-docker-shell",
            "opencode-docker-shell"
        ]

        for runner in runners:
            # 1. Test when SSH Agent is DISABLED (ssh_mount:0)
            self.run_bash(f'_ai_docker_set_project_ssh_agent "{test_dir}" "0"')
            cmd_disabled = f'''
            docker() {{
              for arg in "$@"; do echo "ARG:$arg"; done
            }}
            export -f docker
            {runner} "{test_dir}"
            '''
            res_dis = self.run_bash(cmd_disabled)
            self.assertEqual(res_dis.returncode, 0, f"Failed executing {runner} when disabled")
            self.assertNotIn("ARG:SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock", res_dis.stdout, f"{runner} mounted SSH socket when disabled")

            # 2. Test when SSH Agent is ENABLED (ssh_mount:1)
            self.run_bash(f'_ai_docker_set_project_ssh_agent "{test_dir}" "1"')
            cmd_enabled = f'''
            docker() {{
              for arg in "$@"; do echo "ARG:$arg"; done
            }}
            export -f docker
            {runner} "{test_dir}"
            '''
            res_ena = self.run_bash(cmd_enabled)
            self.assertEqual(res_ena.returncode, 0, f"Failed executing {runner} when enabled")
            self.assertIn("ARG:SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock", res_ena.stdout, f"{runner} did not export SSH_AUTH_SOCK when enabled")
            self.assertIn("ARG:/run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock", res_ena.stdout, f"{runner} did not volume mount SSH socket when enabled")

    def test_all_runners_mount_gh_config(self):
        test_dir = os.path.join(self.tmp_dir, "runner_gh_proj")
        os.makedirs(test_dir)

        runners = [
            "codex-docker-shell",
            "antigravity-docker-shell",
            "claude-docker-shell",
            "opencode-docker-shell"
        ]

        expected_mount_suffix = ":/root/.config/gh"
        for runner in runners:
            cmd = f'''
            docker() {{
              for arg in "$@"; do echo "ARG:$arg"; done
            }}
            export -f docker
            {runner} "{test_dir}"
            '''
            res = self.run_bash(cmd)
            self.assertEqual(res.returncode, 0, f"Failed executing {runner}")
            matched = any(line.startswith("ARG:") and line.endswith(expected_mount_suffix) for line in res.stdout.splitlines())
            self.assertTrue(matched, f"{runner} did not mount /root/.config/gh: {res.stdout}")

    def test_sync_ghconfig(self):
        # Create host gh config
        host_gh = os.path.join(self.tmp_dir, ".config", "gh")
        os.makedirs(host_gh, exist_ok=True)
        with open(os.path.join(host_gh, "hosts.yml"), "w") as f:
            f.write("github.com:\n  user: testuser\n  oauth_token: gho_test123\n")

        target_gh = os.path.join(self.tmp_dir, ".ai-docker-profiles", "default", "gh-docker-config")
        res = self.run_bash(f'_ai_docker_sync_ghconfig "{target_gh}"')
        self.assertEqual(res.returncode, 0)
        self.assertTrue(os.path.exists(os.path.join(target_gh, "hosts.yml")))
        with open(os.path.join(target_gh, "hosts.yml"), "r") as f:
            self.assertIn("oauth_token: gho_test123", f.read())

    def test_codex_default_ai_command(self):
        test_dir = os.path.join(self.tmp_dir, "codex_cmd_proj")
        os.makedirs(test_dir)
        cmd = f'''
        docker() {{
          for arg in "$@"; do echo "ARG:$arg"; done
        }}
        export -f docker
        codex-docker-shell "{test_dir}"
        '''
        res = self.run_bash(cmd)
        self.assertEqual(res.returncode, 0)
        self.assertIn("ARG:AI_COMMAND=codex resume --last", res.stdout)

    def test_opencode_default_ai_command(self):
        test_dir = os.path.join(self.tmp_dir, "opencode_cmd_proj")
        os.makedirs(test_dir)
        cmd = f'''
        docker() {{
          for arg in "$@"; do echo "ARG:$arg"; done
        }}
        export -f docker
        opencode-docker-shell "{test_dir}"
        '''
        res = self.run_bash(cmd)
        self.assertEqual(res.returncode, 0)
        self.assertIn("ARG:AI_COMMAND=opencode -c || opencode", res.stdout)

    def test_start_tmux_layout_syntax_and_autoexec(self):
        layout_script = os.path.join(self.repo_dir, "scripts", "start-tmux-layout")
        # 1. Syntax check
        syntax_res = subprocess.run(["bash", "-n", layout_script], capture_output=True, text=True)
        self.assertEqual(syntax_res.returncode, 0, f"Syntax error in start-tmux-layout: {syntax_res.stderr}")

        # 2. Test autoexec execution behavior when .ai-docker/autoexec.sh is present
        test_proj = os.path.join(self.tmp_dir, "autoexec_proj")
        ai_docker_dir = os.path.join(test_proj, ".ai-docker")
        os.makedirs(ai_docker_dir, exist_ok=True)
        autoexec_path = os.path.join(ai_docker_dir, "autoexec.sh")
        marker_file = os.path.join(test_proj, "autoexec_ran.marker")

        with open(autoexec_path, "w") as f:
            f.write(f"#!/usr/bin/env bash\necho 'hello-from-autoexec' > '{marker_file}'\n")

        # Mock tmux binary in PATH to inspect command passed to first window
        mock_bin_dir = os.path.join(self.tmp_dir, "mock_bin")
        os.makedirs(mock_bin_dir, exist_ok=True)
        cmd_file = os.path.join(test_proj, "tmux_cmd.txt")
        mock_tmux_path = os.path.join(mock_bin_dir, "tmux")
        with open(mock_tmux_path, "w") as f:
            f.write(f'''#!/usr/bin/env bash
if [ "$1" = "has-session" ]; then
  exit 1
elif [ "$1" = "new-session" ]; then
  echo "${{@: -1}}" > "{cmd_file}"
  exit 0
fi
exit 0
''')
        os.chmod(mock_tmux_path, 0o755)

        test_env = dict(os.environ, PATH=f"{mock_bin_dir}:{os.environ.get('PATH', '')}", AI_COMMAND="echo tool_started")
        res = subprocess.run(["bash", layout_script], capture_output=True, text=True, cwd=test_proj, env=test_env)
        self.assertEqual(res.returncode, 0, f"layout script failed: {res.stderr}\n{res.stdout}")
        self.assertTrue(os.path.exists(cmd_file), "tmux new-session was not invoked")
        with open(cmd_file, "r") as f:
            captured_cmd = f.read()

        self.assertIn(".ai-docker/autoexec.sh", captured_cmd)
        self.assertIn("tool_started", captured_cmd)

        # Now execute the captured command without exec bash -l to test execution
        test_run_cmd = captured_cmd.replace("exec bash -l", "echo shell_done")
        exec_res = subprocess.run(["bash", "-c", test_run_cmd], capture_output=True, text=True, cwd=test_proj)
        self.assertTrue(os.path.exists(marker_file), "autoexec.sh did not execute marker creation")
        with open(marker_file, "r") as f:
            self.assertEqual(f.read().strip(), "hello-from-autoexec")
        self.assertIn("[ai-docker] Running .ai-docker/autoexec.sh...", exec_res.stdout)
        self.assertIn("tool_started", exec_res.stdout)

if __name__ == "__main__":
    unittest.main()



