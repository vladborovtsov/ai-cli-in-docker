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

    def test_claude_command_default(self):
        res = self.run_bash("type claude-docker-shell")
        self.assertEqual(res.returncode, 0)
        self.assertIn("claude --continue || claude", res.stdout)

if __name__ == "__main__":
    unittest.main()
