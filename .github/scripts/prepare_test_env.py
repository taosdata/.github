import concurrent.futures
import json
import logging
import os
import platform
import socket
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List

from utils import Utils

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


class TestPreparer:
    """Prepare the environment for testing TDengine or TDinternal
    1. Prepare the environment
    2. Prepare TDengine or TDinternal repository to source/target branch
    3. Update codes for TDengine or TDinternal
    4. Update submodules
    5. Output file without doc changes
    6. Get testing parameters
    """

    def __init__(self):
        self.utils = Utils()
        # initialize paths and platform from arguments
        self.container_name = self.utils.get_env_var("CONTAINER_NAME", "taosd-test")
        self.wkdir = Path(os.getenv("WKDIR", "/var/lib/jenkins/workspace"))
        self.utils.set_env_var("WKDIR", self.wkdir, os.getenv("GITHUB_ENV", ""))
        self.platform = platform.system().lower()
        logger.info(self.utils.get_env_var("IS_TDINTERNAL"))
        self.enterprise = (
            False if self.utils.get_env_var("IS_TDINTERNAL") == "false" else True
        )
        self.wk = self.utils.path(os.path.join(self.wkdir, "TDinternal"))
        self.wkc = self.utils.path(os.path.join(self.wk, "community"))
        self.run_number = self.utils.get_env_var("GITHUB_RUN_NUMBER", 0)
        self.run_attempt = self.utils.get_env_var("GITHUB_RUN_ATTEMPT", 0)

        # Load GitHub context data
        self.event = json.loads(self.utils.get_env_var("GITHUB_EVENT", "{}"))
        self.inputs = json.loads(self.utils.get_env_var("GITHUB_INPUTS", "{}"))

        self.local_ip = self._get_local_ip()
        # Load host configurations
        self.host_configs = self._load_host_configs()

        # Set branch variables
        self._set_branch_variables()

    def _get_local_ip(self) -> str:
        """get local IP address"""
        try:
            # create a UDP socket
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                # connect to a external address (will not actually send data)
                s.connect(("8.8.8.8", 80))
                ip = s.getsockname()[0]

                if ip.startswith("192.168."):
                    return ip
                else:
                    return None
        except Exception as e:
            logger.error(f"Error getting IP address: {e}")
            return None

    def _load_host_configs(self) -> List[Dict[str, Any]]:
        """Load host configurations from /home/m.json"""
        config_file = "/home/m.json"
        try:
            if os.path.exists(config_file):
                with open(config_file, "r", encoding="utf-8") as f:
                    configs = json.load(f)
                    logger.info(f"Loaded {len(configs)} host configurations")
                    for config in configs:
                        if config["host"] == self.local_ip:
                            configs.remove(config)
                            break
                    return configs
            else:
                logger.info(
                    f"Host config file {config_file} not found, using local execution only"
                )
                return []
        except Exception as e:
            logger.error(f"Error loading host configs: {e}")
            return []

    def _set_branch_variables(self):
        """Determine source/target branches and PR number from inputs or event data"""
        if (
            self.inputs.get("specified_source_branch") == "unavailable"
            and self.inputs.get("specified_target_branch") == "unavailable"
            and self.inputs.get("specified_pr_number") == "unavailable"
        ):
            # From GitHub event
            pr = self.event.get("pull_request", {})
            self.source_branch = pr.get("head", {}).get("ref", "")
            self.target_branch = pr.get("base", {}).get("ref", "")
            self.pr_number = str(pr.get("number", ""))
        else:
            # From inputs
            self.source_branch = self.inputs.get("specified_source_branch", "")
            self.target_branch = self.inputs.get("specified_target_branch", "")
            self.pr_number = self.inputs.get("specified_pr_number", "")

        self.utils.set_env_var(
            "SOURCE_BRANCH", self.source_branch, os.getenv("GITHUB_ENV", "")
        )
        self.utils.set_env_var(
            "TARGET_BRANCH", self.target_branch, os.getenv("GITHUB_ENV", "")
        )
        self.utils.set_env_var("PR_NUMBER", self.pr_number, os.getenv("GITHUB_ENV", ""))

    def prepare_repositories(self):
        """Prepare both TDengine or TDinternal repository"""
        logger.info(f"Preparing TDinternal in {self.wkdir}...")
        if (
            self.inputs.get("specified_source_branch") == "unavailable"
            and self.inputs.get("specified_target_branch") == "unavailable"
            and self.inputs.get("specified_pr_number") == "unavailable"
        ):
            self._prepare_repo(self.wk, self.target_branch)
            # verification needed
            # self._prepare_repo(self.wk, 'main')
        else:
            self._prepare_repo(self.wk, self.source_branch)
        self._prepare_repo(self.wkc, self.target_branch)

    def _prepare_repo(self, repo_path, branch):
        """Prepare a single repository"""
        if not repo_path.exists():
            raise FileNotFoundError(f"Repository path not found: {repo_path}")

        cmds = [
            f"cd {repo_path} && git reset --hard",
            f"cd {repo_path} && git clean -f",
            f"cd {repo_path} && git remote prune origin",
            f"cd {repo_path} && git fetch",
            f"cd {repo_path} && git checkout -f origin/{branch}",
        ]
        self.utils.run_commands(cmds)

    def update_submodules(self):
        cmd = "git submodule update --init --recursive"
        self.utils.run_command(cmd, cwd=self.wkc)

    def update_codes(self):
        """Update codes for TDengine or TDinternal"""
        logger.info(f"is enterprise: {self.enterprise}")
        if self.enterprise:
            logger.info("Updating codes for TDinternal...")
            job_name = "TDinternalCI"
            self._update_latest_merge_from_pr(self.wk, self.pr_number, job_name)
            self._update_latest_from_target_branch(self.wkc)
        else:
            logger.info("Updating codes for community...")
            job_name = "NewTest"
            self._update_latest_merge_from_pr(self.wkc, self.pr_number, job_name)
            self._update_latest_from_target_branch(self.wk)

    def _update_latest_from_target_branch(self, repo_path):
        """Update latest code from target branch, and log to jenkins.log"""
        repo_log_name = "community" if "community" in str(repo_path) else "tdinternal"
        # # 拉取最新代码
        # cmds = [
        #     f"cd {repo_path} && git remote prune origin && git fetch",
        #     f"cd {repo_path} && git pull ",
        # ]
        # self.utils.run_commands(cmds)
        # 记录日志
        log = subprocess.getoutput(f"cd {repo_path} && git log -5")
        with open(f"{self.wkdir}/jenkins.log", "a") as f:
            f.write(f"{repo_log_name} log: {log}\n")

    def _update_latest_merge_from_pr(self, repo_path, pr_number, job_name=""):
        """Update latest codes and merge from PR, and log to jenkins.log"""
        repo_log_name = "community" if "community" in str(repo_path) else "tdinternal"
        # # 拉取最新代码
        # cmds = [f"cd {repo_path} && git pull"]
        # self.utils.run_commands(cmds)
        # 记录日志
        log = subprocess.getoutput(f"cd {repo_path} && git log -5")
        with open(f"{self.wkdir}/jenkins.log", "a") as f:
            now = datetime.now().strftime("%Y%m%d-%H%M%S")
            f.write(
                f"{now} {job_name}/PR-{pr_number}:{self.run_number}:{self.target_branch}\n"
            )
            f.write(f"CHANGE_BRANCH:{self.source_branch}\n")
            f.write(f"{repo_log_name} log: {log}\n")
        # fetch PR 并切换
        cmds = [
            f"cd {repo_path} && git fetch origin +refs/pull/{pr_number}/merge",
            f"cd {repo_path} && git checkout -qf FETCH_HEAD",
        ]
        self.utils.run_commands(cmds)
        # 记录 merge 后日志
        log_merged = subprocess.getoutput(f"cd {repo_path} && git log -5")
        with open(f"{self.wkdir}/jenkins.log", "a") as f:
            f.write(f"{repo_log_name} log merged: {log_merged}\n")

    def output_file_no_doc_change(self):
        cmds = [
            f"mkdir -p {self.wkdir}/tmp/{self.pr_number}_{self.run_number}",
            f"""
            cd {self.wkc} \
            && changed_files_non_doc=$(git --no-pager diff --name-only FETCH_HEAD `git merge-base FETCH_HEAD origin/{self.target_branch}` | grep -v '^docs/en/' | grep -v '^docs/zh/' | grep -v '.md$' | tr '\n' ' ' || :) \
            && echo $changed_files_non_doc > {self.wkdir}/tmp/{self.pr_number}_{self.run_number}/docs_changed.txt
            """,
        ]
        self.utils.run_commands(cmds)

    def output_environment_info(self):
        cmd = f"echo {self.wkdir}/restore.sh -p PR-{self.pr_number} -n {self.run_number} -c {self.container_name}"
        self.utils.run_command(cmd)

    def get_testing_params(self):
        """Get testing parameters from log_server.json file"""
        log_server_file = "/home/log_server.json"
        timeout_cmd = ""
        extra_param = ""

        if self.utils.file_exists(log_server_file):
            with open(log_server_file) as file:
                log_server_data = json.load(file)
                log_server_enabled = log_server_data.get("enabled")
                timeout_param = log_server_data.get("timeout")
                if timeout_param and timeout_param != 0:
                    timeout_cmd = f"timeout {timeout_param}"
                if log_server_enabled == 1:
                    log_server = log_server_data.get("server")
                    if log_server:
                        extra_param = f"-w {log_server}"
        else:
            logger.info("log_server.json file not found")
        logger.info(f"timeout_cmd: {timeout_cmd}, extra_param: {extra_param}")
        self.utils.set_env_var(
            "timeout_cmd", timeout_cmd, env_file=os.getenv("GITHUB_ENV", "")
        )
        self.utils.set_env_var(
            "extra_param", extra_param, env_file=os.getenv("GITHUB_ENV", "")
        )

    def _execute_remote_command(self, host_config, command):
        """Execute a command on remote host via SSH"""
        try:
            import paramiko

            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

            # Connect to remote host
            ssh.connect(
                hostname=host_config["host"],
                username=host_config["username"],
                timeout=30,
            )

            # Execute command
            stdin, stdout, stderr = ssh.exec_command(command)
            stdout_text = stdout.read().decode("utf-8")
            stderr_text = stderr.read().decode("utf-8")
            exit_code = stdout.channel.recv_exit_status()

            ssh.close()

            success = exit_code == 0
            output = stdout_text if success else stderr_text
            return success, output

        except Exception as e:
            return False, str(e)

    def _prepare_repositories_remote(self, host_config):
        """Prepare repositories on remote host"""
        host = host_config["host"]
        workdir = host_config["workdir"]

        logger.info(f"Preparing repositories on {host}...")

        # Prepare TDinternal repository
        if (
            self.inputs.get("specified_source_branch") == "unavailable"
            and self.inputs.get("specified_target_branch") == "unavailable"
            and self.inputs.get("specified_pr_number") == "unavailable"
        ):
            success, _ = self._execute_remote_command(
                host_config,
                f"cd {workdir}/TDinternal && git reset --hard && git clean -f && git remote prune origin && git fetch && git checkout -f origin/{self.target_branch}",
            )
            if not success:
                logger.info(f"Failed to prepare TDinternal on {host}")
                return False
        else:
            success, _ = self._execute_remote_command(
                host_config,
                f"cd {workdir}/TDinternal && git reset --hard && git clean -f && git remote prune origin && git fetch && git checkout -f origin/{self.source_branch}",
            )
            if not success:
                logger.info(f"Failed to prepare TDinternal on {host}")
                return False

        # Prepare community repository
        success, _ = self._execute_remote_command(
            host_config,
            f"cd {workdir}/TDinternal/community && git reset --hard && git clean -f && git remote prune origin && git fetch && git checkout -f origin/{self.target_branch}",
        )
        if not success:
            logger.error(f"Failed to prepare community on {host}")
            return False

        return True

    def _update_codes_remote(self, host_config):
        """Update codes on remote host"""
        host = host_config["host"]
        workdir = host_config["workdir"]

        logger.info(f"Updating codes on {host}...")

        if self.enterprise:
            logger.info(f"Updating codes for TDinternal on {host}...")
            job_name = "TDinternalCI"
            success = self._update_latest_merge_from_pr_remote(
                host_config, f"{workdir}/TDinternal", self.pr_number, job_name
            )
            if not success:
                return False
            success = self._update_latest_from_target_branch_remote(
                host_config, f"{workdir}/TDinternal/community"
            )
            if not success:
                return False
        else:
            logger.info(f"Updating codes for community on {host}...")
            job_name = "NewTest"
            success = self._update_latest_merge_from_pr_remote(
                host_config, f"{workdir}/TDinternal/community", self.pr_number, job_name
            )
            if not success:
                return False
            success = self._update_latest_from_target_branch_remote(
                host_config, f"{workdir}/TDinternal"
            )
            if not success:
                return False

        return True

    def _update_latest_from_target_branch_remote(self, host_config, repo_path):
        """Update latest code from target branch on remote host"""
        host = host_config["host"]
        repo_log_name = "community" if "community" in repo_path else "tdinternal"

        # # Pull latest code
        # success, _ = self._execute_remote_command(
        #     host_config, f"cd {repo_path} && git remote prune origin && git pull"
        # )
        # if not success:
        #     logger.error(f"Failed to pull latest code from target branch on {host}")
        #     return False

        # Log git history
        success, log = self._execute_remote_command(
            host_config, f"cd {repo_path} && git log -5"
        )
        if success:
            log_content = f"{repo_log_name} log: {log}\n"
            success, _ = self._execute_remote_command(
                host_config,
                f"echo '{log_content}' >> {host_config['workdir']}/jenkins.log",
            )
            if not success:
                logger.error(f"Failed to write log on {host}")

        return True

    def _update_latest_merge_from_pr_remote(
        self, host_config, repo_path, pr_number, job_name=""
    ):
        """Update latest codes and merge from PR on remote host"""
        host = host_config["host"]
        repo_log_name = "community" if "community" in repo_path else "tdinternal"

        # # Pull latest code
        # success, _ = self._execute_remote_command(
        #     host_config, f"cd {repo_path} && git pull"
        # )
        # if not success:
        #     logger.error(f"Failed to pull latest code on {host}")
        #     return False

        # Log git history
        success, log = self._execute_remote_command(
            host_config, f"cd {repo_path} && git log -5"
        )
        if success:
            now = datetime.now().strftime("%Y%m%d-%H%M%S")
            log_content = f"{now} {job_name}/PR-{pr_number}:{self.run_number}:{self.target_branch}\nCHANGE_BRANCH:{self.source_branch}\n{repo_log_name} log: {log}\n"
            success, _ = self._execute_remote_command(
                host_config,
                f"echo '{log_content}' >> {host_config['workdir']}/jenkins.log",
            )
            if not success:
                logger.error(f"Failed to write log on {host}")

        # Fetch PR and checkout
        success, _ = self._execute_remote_command(
            host_config,
            f"cd {repo_path} && git fetch origin +refs/pull/{pr_number}/merge && git checkout -qf FETCH_HEAD",
        )
        if not success:
            logger.error(f"Failed to fetch and checkout PR on {host}")
            return False

        # Log merged history
        success, log_merged = self._execute_remote_command(
            host_config, f"cd {repo_path} && git log -5"
        )
        if success:
            log_content = f"{repo_log_name} log merged: {log_merged}\n"
            success, _ = self._execute_remote_command(
                host_config,
                f"echo '{log_content}' >> {host_config['workdir']}/jenkins.log",
            )
            if not success:
                logger.error(f"Failed to write merged log on {host}")

        return True

    def _update_submodules_remote(self, host_config):
        """Update submodules on remote host"""
        host = host_config["host"]
        workdir = host_config["workdir"]

        logger.info(f"Updating submodules on {host}...")
        success, _ = self._execute_remote_command(
            host_config,
            f"cd {workdir}/TDinternal/community && git submodule update --init --recursive",
        )
        if not success:
            logger.error(f"Failed to update submodules on {host}")
            return False
        return True

    def _output_file_no_doc_change_remote(self, host_config):
        """Output file without doc changes on remote host"""
        host = host_config["host"]
        workdir = host_config["workdir"]

        logger.info(f"Outputting file without doc changes on {host}...")
        cmd = f"""
        mkdir -p {workdir}/tmp/{self.pr_number}_{self.run_number} && \
        cd {workdir}/TDinternal/community && \
        changed_files_non_doc=$(git --no-pager diff --name-only FETCH_HEAD `git merge-base FETCH_HEAD {self.target_branch}` | grep -v '^docs/en/' | grep -v '^docs/zh/' | grep -v '.md$' | tr '\\n' ' ' || :) && \
        echo $changed_files_non_doc > {workdir}/tmp/{self.pr_number}_{self.run_number}/docs_changed.txt
        """
        success, _ = self._execute_remote_command(host_config, cmd)
        if not success:
            logger.error(f"Failed to output file without doc changes on {host}")
            return False
        return True

    def _get_testing_params_remote(self, host_config):
        """Get testing parameters on remote host"""
        host = host_config["host"]
        workdir = host_config["workdir"]

        logger.info(f"Getting testing parameters on {host}...")
        cmd = f"""
        log_server_file="/home/log_server.json"
        timeout_cmd=""
        extra_param=""
        
        if [ -f "$log_server_file" ]; then
            log_server_enabled=$(jq -r '.enabled' "$log_server_file")
            timeout_param=$(jq -r '.timeout' "$log_server_file")
            if [ "$timeout_param" != "null" ] && [ "$timeout_param" != "0" ]; then
                timeout_cmd="timeout $timeout_param"
            fi
            if [ "$log_server_enabled" = "1" ]; then
                log_server=$(jq -r '.server' "$log_server_file")
                if [ "$log_server" != "null" ]; then
                    extra_param="-w $log_server"
                fi
            fi
        else
            echo "log_server.json file not found"
        fi
        
        echo "timeout_cmd: $timeout_cmd, extra_param: $extra_param"
        echo "timeout_cmd=$timeout_cmd" >> {workdir}/env_vars.txt
        echo "extra_param=$extra_param" >> {workdir}/env_vars.txt
        """
        success, _ = self._execute_remote_command(host_config, cmd)
        if not success:
            logger.error(f"Failed to get testing parameters on {host}")
            return False
        return True

    def _process_single_host(self, host_config):
        """Process a single host - prepare and update repositories"""
        host = host_config["host"]
        logger.info(f"Processing host: {host}")

        try:
            # Prepare repositories
            if not self._prepare_repositories_remote(host_config):
                return False

            # Update codes
            if not self._update_codes_remote(host_config):
                return False

            # # Update submodules
            # if not self._update_submodules_remote(host_config):
            #     return False

            # Output file without doc changes (Linux only)
            if platform.system().lower() == "linux":
                if not self._output_file_no_doc_change_remote(host_config):
                    return False

                # Get testing parameters
                if not self._get_testing_params_remote(host_config):
                    return False

            logger.info(f"Successfully processed host: {host}")
            return True

        except Exception as e:
            logger.error(f"Error processing host {host}: {e}")
            return False

    def run(self):
        """Execute preparation steps"""
        logger.info("Starting preparation phase...")
        if platform.system().lower() == "windows" and self.target_branch == "3.3.6":
            logger.info("Preparation phase skipped on Windows for target branch 3.3.6.")
            return True

        try:
            # Process remote hosts if configured
            if self.host_configs:
                logger.info(f"Processing {len(self.host_configs)} remote hosts...")
                success = self._process_remote_hosts()
                if not success:
                    logger.error("Failed to process some remote hosts")
                    return False

            # Process local environment
            logger.info("Processing local environment...")
            if platform.system().lower() == "linux":
                self.output_environment_info()
            self.prepare_repositories()
            self.update_codes()
            # self.update_submodules()
            if platform.system().lower() == "linux":
                self.output_file_no_doc_change()
                self.get_testing_params()

            logger.info("Preparation phase completed successfully.")
            return True

        except Exception as e:
            import traceback

            traceback.print_exc()  # prints full stack + exception
            # If it's a CalledProcessError, also print captured stdout/stderr
            if isinstance(e, subprocess.CalledProcessError):
                logger.error(f"Standard Output: {e.output}")
                logger.error(f"Standard Error: {e.stderr}")
            return False

    def _process_remote_hosts(self):
        """Process all remote hosts in parallel"""
        if not self.host_configs:
            return True

        logger.info(f"Processing {len(self.host_configs)} remote hosts...")
        # Use ThreadPoolExecutor for parallel processing
        max_threads = max(
            1, min(len(self.host_configs), 10)
        )  # Limit to 10 concurrent threads
        results = []

        with concurrent.futures.ThreadPoolExecutor(max_workers=max_threads) as executor:
            # Submit all host processing tasks
            future_to_host = {
                executor.submit(self._process_single_host, host_config): host_config
                for host_config in self.host_configs
                if host_config["host"] != self.local_ip
            }

            # Collect results
            for future in concurrent.futures.as_completed(future_to_host):
                host_config = future_to_host[future]
                host = host_config["host"]
                try:
                    result = future.result()
                    results.append((host, result))
                    if result:
                        logger.info(f"✓ Host {host} processed successfully")
                    else:
                        logger.error(f"✗ Host {host} processing failed")
                except Exception as e:
                    logger.error(f"✗ Host {host} processing failed with exception: {e}")
                    results.append((host, False))

        # Check if all hosts processed successfully
        failed_hosts = [host for host, success in results if not success]
        if failed_hosts:
            logger.error(f"Failed to process hosts: {failed_hosts}")
            return False

        logger.info("All remote hosts processed successfully")
        return True


if __name__ == "__main__":
    prepare = TestPreparer()
    assert prepare.run() == True
