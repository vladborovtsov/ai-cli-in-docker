import os
import pty
import re
import select
import shutil
import subprocess
import tempfile
import time
import unittest

def strip_ansi(text):
    # Standard ANSI escape sequence remover
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    return ansi_escape.sub('', text)

class TestBashTui(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()
        self.old_home = os.environ.get("HOME")
        os.environ["HOME"] = self.tmp_dir
        self.old_profile = os.environ.get("AI_DOCKER_PROFILE")
        if "AI_DOCKER_PROFILE" in os.environ:
            del os.environ["AI_DOCKER_PROFILE"]
        self.repo_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

    def tearDown(self):
        shutil.rmtree(self.tmp_dir)
        if self.old_home:
            os.environ["HOME"] = self.old_home
        else:
            del os.environ["HOME"]
        if self.old_profile:
            os.environ["AI_DOCKER_PROFILE"] = self.old_profile

    def read_until(self, fd, expected_texts, timeout=3.0):
        """Read from file descriptor until all expected texts are found or timeout."""
        start_time = time.time()
        buffer = ""
        while time.time() - start_time < timeout:
            r, _, _ = select.select([fd], [], [], 0.05)
            if fd in r:
                try:
                    chunk = os.read(fd, 8192).decode("utf-8", errors="ignore")
                    if not chunk:
                        break
                    buffer += chunk
                except OSError:
                    break
                
                clean_buf = strip_ansi(buffer)
                if all(exp in clean_buf for exp in expected_texts):
                    return True, clean_buf
        return False, strip_ansi(buffer)

    def test_main_menu_render_and_exit(self):
        master_fd, slave_fd = pty.openpty()
        p = subprocess.Popen(
            ["./ai-docker.sh"],
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            close_fds=True,
            text=True,
            cwd=self.repo_dir,
            env=dict(os.environ, TERM="xterm-256color")
        )
        os.close(slave_fd)

        try:
            # Check for header titles and main choices
            success, clean_output = self.read_until(
                master_fd, 
                ["AI CLI IN DOCKER - CONTROL TUI", "Launch Claude Code", "Exit"],
                timeout=4.0
            )
            self.assertTrue(success, f"TUI did not display main menu items. Buffer: {repr(clean_output)}")
            
            # Verify basic TUI boundaries
            self.assertIn("Workspace:", clean_output)
            self.assertIn("Profile:", clean_output)
            
            # Initial selection should be on Claude Code (represented by indicator ▸)
            self.assertTrue(any("▸" in line and "Claude" in line for line in clean_output.splitlines()),
                            f"Claude Code was not selected by default. Output: {clean_output}")

            # Send 'q' to quit
            os.write(master_fd, b"q")
            
            # Drain output to avoid deadlock
            start_wait = time.time()
            while p.poll() is None and (time.time() - start_wait < 2.0):
                r, _, _ = select.select([master_fd], [], [], 0.05)
                if master_fd in r:
                    try:
                        os.read(master_fd, 1024)
                    except OSError:
                        break
            
            p.wait(timeout=1.0)
            self.assertEqual(p.returncode, 0)
        finally:
            try:
                os.close(master_fd)
            except OSError:
                pass
            p.kill()

    def test_navigation_down_up(self):
        master_fd, slave_fd = pty.openpty()
        p = subprocess.Popen(
            ["./ai-docker.sh"],
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            close_fds=True,
            text=True,
            cwd=self.repo_dir,
            env=dict(os.environ, TERM="xterm-256color")
        )
        os.close(slave_fd)

        try:
            # Wait for main menu to render
            success, _ = self.read_until(master_fd, ["[Use ↑/↓ or j/k to navigate", "▸ 💬 Launch Claude Code"], timeout=3.0)
            self.assertTrue(success)

            # Send 'j' to navigate down to Gemini CLI
            os.write(master_fd, b"j")
            success, clean_output = self.read_until(master_fd, ["▸ 💬 Launch Gemini CLI"], timeout=2.0)
            self.assertTrue(success, f"Gemini was not selected. Output: {clean_output}")

            # Send Down arrow sequence to navigate down to OpenAI Codex
            os.write(master_fd, b"\x1b[B")
            success, clean_output = self.read_until(master_fd, ["▸ 💬 Launch OpenAI Codex"], timeout=2.0)
            self.assertTrue(success, f"Codex was not selected. Output: {clean_output}")

            # Send 'k' to move back up to Gemini CLI
            os.write(master_fd, b"k")
            success, clean_output = self.read_until(master_fd, ["▸ 💬 Launch Gemini CLI"], timeout=2.0)
            self.assertTrue(success, f"Gemini was not re-selected. Output: {clean_output}")

            # Quit
            os.write(master_fd, b"q")
            
            # Drain output to avoid deadlock
            start_wait = time.time()
            while p.poll() is None and (time.time() - start_wait < 2.0):
                r, _, _ = select.select([master_fd], [], [], 0.05)
                if master_fd in r:
                    try:
                        os.read(master_fd, 1024)
                    except OSError:
                        break
                        
            p.wait(timeout=1.0)
            self.assertEqual(p.returncode, 0)
        finally:
            try:
                os.close(master_fd)
            except OSError:
                pass
            p.kill()

    def test_submenu_navigation(self):
        master_fd, slave_fd = pty.openpty()
        p = subprocess.Popen(
            ["./ai-docker.sh"],
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            close_fds=True,
            text=True,
            cwd=self.repo_dir,
            env=dict(os.environ, TERM="xterm-256color")
        )
        os.close(slave_fd)

        try:
            # Wait for main menu to render
            success, _ = self.read_until(master_fd, ["[Use ↑/↓ or j/k to navigate", "▸ 💬 Launch Claude Code"], timeout=3.0)
            self.assertTrue(success)

            # Move down index-by-index with verification
            # Move to Gemini
            os.write(master_fd, b"j")
            self.assertTrue(self.read_until(master_fd, ["▸ 💬 Launch Gemini CLI"], timeout=1.0)[0])

            # Move to Codex
            os.write(master_fd, b"j")
            self.assertTrue(self.read_until(master_fd, ["▸ 💬 Launch OpenAI Codex"], timeout=1.0)[0])

            # Move to OpenCode
            os.write(master_fd, b"j")
            self.assertTrue(self.read_until(master_fd, ["▸ 💬 Launch OpenCode"], timeout=1.0)[0])

            # Move to Change Workspace Directory
            os.write(master_fd, b"j")
            success, clean_output = self.read_until(master_fd, ["▸ 📁 Change Workspace Directory"], timeout=1.0)
            self.assertTrue(success, f"Change Workspace was not selected. Output: {clean_output}")

            # Hit Enter to open Workspace Submenu
            os.write(master_fd, b"\r")
            
            # Verify Workspace Submenu options
            success, clean_output = self.read_until(
                master_fd, 
                ["Select or change the active workspace directory", "Back to Main Menu"],
                timeout=3.0
            )
            self.assertTrue(success, f"Did not open Workspace Submenu. Output: {clean_output}")

            # Hit 'q' to go back to main menu
            os.write(master_fd, b"q")
            success, clean_output = self.read_until(master_fd, ["AI CLI IN DOCKER - CONTROL TUI"], timeout=2.0)
            self.assertTrue(success, f"Did not return to main menu. Output: {clean_output}")

            # Exit
            os.write(master_fd, b"q")
            
            # Drain output to avoid deadlock
            start_wait = time.time()
            while p.poll() is None and (time.time() - start_wait < 2.0):
                r, _, _ = select.select([master_fd], [], [], 0.05)
                if master_fd in r:
                    try:
                        os.read(master_fd, 1024)
                    except OSError:
                        break
                        
            p.wait(timeout=1.0)
            self.assertEqual(p.returncode, 0)
        finally:
            try:
                os.close(master_fd)
            except OSError:
                pass
            p.kill()

if __name__ == "__main__":
    unittest.main()
