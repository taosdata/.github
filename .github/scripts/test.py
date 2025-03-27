import os
import platform
import json
from pathlib import Path
from utils import Utils

class TestRunner:
    def __init__(self):
        self.utils = Utils()
        self.wkdir = Path(os.getenv('WKDIR', '/var/lib/jenkins/workspace'))
        self.test_type = os.getenv('TEST_TYPE', '')
        self.wk = self.utils.path(os.path.join(self.wkdir, 'TDinternal'))
        self.wkc = self.utils.path(os.path.join(self.wk, 'community'))
        self.platform = platform.system().lower()
        self.pr_number = self.utils.get_env_var('PR_NUMBER', '')
        self.run_number = self.utils.get_env_var('GITHUB_RUN_NUMBER', '')

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
            print("log_server.json file not found")
        print(f"timeout_cmd: {timeout_cmd}, extra_param: {extra_param}")
        self.utils.set_env_var("timeout_cmd", timeout_cmd, os.getenv('GITHUB_ENV', ''))
        self.utils.set_env_var("extra_param", extra_param, os.getenv('GITHUB_ENV', ''))

    def run_assert_test(self):
        cmd = f"cd {self.wkc}/test/ci && ./run_check_assert_container.sh -d {self.wkdir}",
        self.utils.run_command(cmd, silent=True)

    def run_void_function_test(self):
        cmd = f"cd {self.wkc}/test/ci && ./run_check_void_container.sh -d {self.wkdir}",
        self.utils.run_command(cmd, silent=True, check=False)

    def run_function_return_test(self):
        extra_param = self.utils.get_env_var('extra_param')
        print(f"PR number: {self.pr_number}, run number: {self.run_number}, extra param: {extra_param}")
        cmd = f"cd {self.wkc}/test/ci && ./run_scan_container.sh -d {self.wkdir} -b {self.pr_number}_{self.run_number} -f {self.wkdir}/tmp/{self.pr_number}_{self.run_number}/docs_changed.txt {extra_param}",
        self.utils.run_command(cmd, silent=True)

    def run_function_test(self):
        cmds = [
            f"cd {self.wkc}/test/ci && export DEFAULT_RETRY_TIME=2",
            f"date",
            f"cd {self.wkc}/test/ci && {self.utils.get_env_var('timeout_cmd')} time ./run.sh -e -m /home/m.json -t cases.task -b PR-{self.utils.get_env_var('PR_NUMBER')}_{self.utils.get_env_var('GITHUB_RUN_NUMBER')} -l {self.wkdir}/log -o 1200 {self.utils.get_env_var('extra_param')}",
        ]
        self.utils.run_commands(cmds)

    def run(self):
        self.get_testing_params()
        if self.test_type == 'assert':
            self.run_assert_test()
        elif self.test_type == 'void':
            self.run_void_function_test()
        elif self.test_type == 'function_returns':
            self.run_function_return_test()
        elif self.test_type == 'function':
            self.run_function_test()
            if self.platform == 'linux':
                self.cleanup()
        else:
            raise Exception("Invalid test type")

    def cleanup(self):
        """Clean up any remaining test processes"""
        print("Cleaning up running processes...")
        if self.platform == 'linux':
            self.utils.kill_process('run_case.sh')

if __name__ == '__main__':
    test_runner = TestRunner()
    test_runner.run()
