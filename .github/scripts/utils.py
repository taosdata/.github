import os
import select
import json
import platform
import subprocess
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
    def run_command(
        self,
        command: Union[str, List[str]],
        cwd: Optional[Union[str, Path]] = None,
        env: Optional[Dict[str, str]] = None,
        check: bool = True,
        silent: bool = False
    ) -> subprocess.CompletedProcess:
        """
        Execute a command with platform-specific handling
        Args:
            command: Command string or list of arguments
            cwd: Working directory
            env: Environment variables
            check: Raise exception on failure
            silent: Redirect output to null device
        """
        cwd = str(self.path(cwd)) if cwd else None
        
        # Prepare command
        if isinstance(command, str):
            if self.is_windows:
                command = command.replace('/', '\\')
        else:
            command = [str(arg) for arg in command]
        
        # Prepare output redirection
        stdout = subprocess.DEVNULL if silent else subprocess.PIPE
        stderr = subprocess.DEVNULL if silent else subprocess.PIPE
        
        try:
            process = subprocess.Popen(
                command,
                cwd=cwd,
                env=env or os.environ,
                shell=self.shell,
                executable=self.shell_exec,
                stdout=stdout,
                stderr=stderr,
                text=True,
                bufsize=256
            )
            if not silent:
                # print output in real-time with select
                outputs = [process.stdout, process.stderr]
                while outputs:
                    readable, _, _ = select.select(outputs, [], [])
                    for stream in readable:
                        line = stream.readline()
                        if line:
                            print(line, end="")
                        else:
                            outputs.remove(stream)
            process.wait()
            if check and process.returncode != 0:
                raise subprocess.CalledProcessError(process.returncode, command)
            return subprocess.CompletedProcess(
                args=command,
                returncode=process.returncode,
                stdout=None,
                stderr=None
            )
        except subprocess.CalledProcessError as e:
            if not silent:
                print(f"Command failed: {e.cmd}")
                if e.stdout:
                    print(f"Stdout: {e.stdout}")
                if e.stderr:
                    print(f"Stderr: {e.stderr}")
            raise

    def run_commands(self, commands: List[str], cwd: Optional[Union[str, Path]] = None) -> None:
        """Run multiple commands sequentially"""
        for cmd in commands:
            print(f"Running command: {cmd}")
            self.run_command(cmd, cwd=cwd)

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
        """Check if process is running"""
        if self.is_windows:
            result = self.run_command(
                f'tasklist /FI "IMAGENAME eq {process_name}"',
                check=False,
                silent=True
            )
            return process_name.lower() in result.stdout.lower()
        else:
            result = self.run_command(
                f'pgrep -f "{process_name}"',
                check=False,
                silent=True
            )
            return result.returncode == 0
