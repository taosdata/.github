import os
import re
import shlex
import json
import platform
import threading
import subprocess
import sys
from pathlib import Path
from typing import List, Union, Optional, Dict, Any

class Utils:
    """This class provides utility functions for common operations in steps of workflow"""
    def __init__(self):
        self.platform = platform.system().lower()
        self.is_windows = self.platform == 'windows'
        self.is_linux = self.platform == 'linux'
        self.is_mac = self.platform == 'darwin'

        # Platform-specific configurations
        self.null_device = 'NUL' if self.is_windows else '/dev/null'
        self.shell = True  # Use shell for cross-platform compatibility
        self.shell_exec = 'cmd.exe' if self.is_windows else '/bin/bash'

    def read_dependencies(self):
        """Get the dependencies of specified platform from dependencies.txt file"""
        dependencies_file = os.path.join(os.path.dirname(__file__), "dependencies.txt")
        dependencies = {"linux": [], "macOS": []}

        with open(dependencies_file, "r") as file:
            current_os = None
            for line in file:
                line = line.strip()
                if line.startswith("# linux"):
                    current_os = "linux"
                elif line.startswith("# macOS"):
                    current_os = "macOS"
                elif line and current_os:
                    dependencies[current_os].append(line)

        return dependencies

    def install_dependencies(self, platform: str = None):
        """Install the dependencies based on the platform"""
        dependencies = self.read_dependencies()
        if platform == 'linux':
            cmds = [
                "sudo apt update -y",
                f"sudo apt install -y {' '.join(dependencies['linux'])}"
            ]
            self.run_commands(cmds)
        elif platform == 'macOS':
            cmds = [
                "brew update",
                f"brew install {' '.join(dependencies['macOS'])}"
            ]
            self.run_commands(cmds)
        elif self.is_windows:
            pass

    # --------------------------
    # File System Operations
    # --------------------------
    def path(self, *path_parts: Union[str, Path]) -> Path:
        """Create platform-appropriate Path object"""
        path = Path(*path_parts)
        if self.is_windows:
            return Path(str(path).replace('/', '\\'))
        return path

    def path_exists(self, path: Union[str, Path]) -> bool:
        """Check if path exists"""
        return self.path(path).exists()

    def read_file(self, file_path: Union[str, Path]) -> str:
        """Read file content with proper encoding handling"""
        file_path = self.path(file_path)
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                return f.read()
        except UnicodeDecodeError:
            with open(file_path, 'r', encoding='latin-1') as f:
                return f.read()

    def write_file(self, file_path: Union[str, Path], content: str, mode: str = 'w') -> None:
        """Write content to file with proper encoding"""
        file_path = self.path(file_path)
        with open(file_path, mode, encoding='utf-8') as f:
            f.write(content)

    def append_to_file(self, file_path: Union[str, Path], content: str) -> None:
        """Append content to file"""
        self.write_file(file_path, content, mode='a')

    def mkdir(self, dir_path: Union[str, Path], parents: bool = True, exist_ok: bool = True) -> None:
        """Create directory with platform-specific permissions"""
        dir_path = self.path(dir_path)
        dir_path.mkdir(parents=parents, exist_ok=exist_ok)

    def file_exists(self, file_path: Union[str, Path]) -> bool:
        """Check if file exists"""
        return self.path(file_path).exists()

    # --------------------------
    # Environment Handling
    # --------------------------
    def set_env_var(self, name: str, value: str, env_file: Optional[Union[str, Path]] = None) -> None:
        """Set environment variable in GitHub Actions format"""
        os.environ[name] = str(value)
        if env_file:
            self.append_to_file(env_file, f"{name}={value}\n")
        elif self.is_windows:
            os.system(f"set {name}={value}")
        else:
            os.system(f"export {name}={value}")

    def get_env_var(self, name: str, default: Any = None) -> str:
        """Get environment variable with fallback"""
        return os.getenv(name, default)

    # --------------------------
    # JSON Handling
    # --------------------------
    def read_json(self, file_path: Union[str, Path]) -> Dict[str, Any]:
        """Read JSON file with error handling"""
        file_path = self.path(file_path)
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            raise ValueError(f"Invalid JSON file {file_path}: {str(e)}")

    def write_json(self, file_path: Union[str, Path], data: Dict[str, Any]) -> None:
        """Write data to JSON file"""
        file_path = self.path(file_path)
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2)

    # --------------------------
    # Command Execution
    # --------------------------
    def _stream_reader(self, stream, stream_type, silent=False, log_file=None):
        """Thread function to read stream and print output or save to log."""
        try:
            for line in iter(stream.readline, b''):
                try:
                    decoded_line = line.decode('utf-8')  # Try decoding as UTF-8
                except UnicodeDecodeError:
                    decoded_line = line.decode('latin-1')  # Fallback to Latin-1

                if decoded_line:
                    if log_file:
                        with open(log_file, 'a', encoding='utf-8') as f:
                            f.write(decoded_line)
                    if not silent:
                        if stream_type == "stderr":
                            print(decoded_line, end="", file=sys.stderr)
                        else:
                            print(decoded_line, end="")
        except Exception as e:
            print(f"Error reading {stream_type}: {e}", file=sys.stderr)
        finally:
            stream.close()

    def run_command(
        self,
        command: Union[str, List[str]],
        cwd: Optional[Union[str, Path]] = None,
        env: Optional[Dict[str, str]] = None,
        check: bool = True,
        silent: bool = False
    ) -> subprocess.CompletedProcess:
        """
        Execute a command cross-platform with real-time output and handle encoding issues.
        - If `command` is a list -> run directly (shell=False).
        - If `command` is a str -> on Windows run via ['cmd','/c', cmd_str] (so "&&" works),
          on POSIX run with shell=True.
        - If cwd is None, use current working directory.
        """
        cwd = str(self.path(cwd)) if cwd else os.getcwd()
        env_out = env or os.environ

        if isinstance(command, list):
            proc_args = [str(x) for x in command]
            use_shell = False
        else:
            cmd_str = str(command)
            # Normalize forward/back slashes for Windows paths embedded in command
            if self.is_windows:
                cmd_str = cmd_str.replace('/', '\\')
                # use cmd.exe to support "&&" in older PowerShell/cmd contexts
                proc_args = ['cmd', '/c', cmd_str]
                use_shell = False
            else:
                proc_args = cmd_str
                use_shell = True  # allow shell features on POSIX

        executable = self.shell_exec if self.is_linux else None

        proc = subprocess.Popen(
            proc_args,
            cwd=cwd,
            env=env_out,
            shell=use_shell,
            executable=executable,  # Only set for Linux
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=False  # Disable text mode to handle raw bytes
        )

        stdout_thread = threading.Thread(target=self._stream_reader, args=(proc.stdout, "stdout", silent, "stdout.log"))
        stderr_thread = threading.Thread(target=self._stream_reader, args=(proc.stderr, "stderr", silent, "stderr.log"))

        stdout_thread.start()
        stderr_thread.start()
        stdout_thread.join()
        stderr_thread.join()

        proc.wait()

        if check and proc.returncode != 0:
            raise subprocess.CalledProcessError(proc.returncode, proc_args)

        return subprocess.CompletedProcess(args=proc_args, returncode=proc.returncode)

    def run_commands(self, commands: List[Union[str, List[str], tuple]], cwd: Optional[Union[str, Path]] = None) -> None:
        """
        Run multiple commands.
        Supports items:
          - "cd <path> && git reset --hard"         -> will extract path and run command in that cwd
          - ("git reset --hard", "/path/to/repo")   -> explicit (cmd, cwd)
          - ['git','reset','--hard']                -> list form
        """
        cd_pattern = re.compile(r'^\s*cd\s+("([^"]+)"|\'([^\']+)\'|([^&;]+))\s*&&\s*(.+)$', flags=re.I)
        for item in commands:
            item_cwd = cwd
            cmd = item
            if isinstance(item, (list, tuple)) and len(item) >= 2:
                cmd = item[0]
                item_cwd = item[1]
            elif isinstance(item, str):
                m = cd_pattern.match(item)
                if m:
                    path = m.group(2) or m.group(3) or m.group(4)
                    item_cwd = path.strip()
                    cmd = m.group(5).strip()
            print(f"Running command: {cmd} (cwd={item_cwd or os.getcwd()})")
            # If cmd is simple and can be split safely, prefer list form on Windows
            if self.is_windows and isinstance(cmd, str):
                # try simple split, fallback to string (cmd /c handled in run_command)
                try:
                    cmd_list = shlex.split(cmd, posix=False)
                except Exception:
                    cmd_list = cmd
                self.run_command(cmd_list, cwd=item_cwd)
            else:
                self.run_command(cmd, cwd=item_cwd)

    # --------------------------
    # Process Management
    # --------------------------
    def kill_process(self, process_name: str) -> None:
        """Kill processes by name (cross-platform)"""
        if self.is_windows:
            self.run_command(f"taskkill /F /IM {process_name}", check=False)
        else:
            self.run_command(f"pkill -f {process_name}", check=False)
            self.run_command(f"killall {process_name}", check=False)

    def process_exists(self, process_name: str) -> bool:
        if self.is_windows:
            result = self.run_command(f'tasklist /FI "IMAGENAME eq {process_name}"', check=False, silent=True)
            stdout = (result.stdout or "").lower()
            return process_name.lower() in stdout
        else:
            result = self.run_command(f'pgrep -f "{process_name}"', check=False, silent=True)
            return result.returncode == 0