import os
import platform
import json
from pathlib import Path
from utils import Utils

class TestRunner:
    """This class runs the test cases for TDengine or TDinternal"""
    def __init__(self):
        self.utils = Utils()
        self.wkdir = self.utils.get_env_var('WKDIR')
        self.test_type = os.getenv('TEST_TYPE', '')
        self.wk = self.utils.path(os.path.join(self.wkdir, 'TDinternal'))
        self.wkc = self.utils.path(os.path.join(self.wk, 'community'))
        self.platform = platform.system().lower()
        self.pr_number = self.utils.get_env_var('PR_NUMBER')
        self.run_number = self.utils.get_env_var('GITHUB_RUN_NUMBER')
        self.timeout = self.utils.get_env_var('timeout_cmd')
        self.extra_param = self.utils.get_env_var('extra_param')

    def run_assert_test(self):
        cmd = f"cd {self.wkc}/test/ci && ./run_check_assert_container.sh -d {self.wkdir}",
        self.utils.run_command(cmd, silent=False)

    def run_void_function_test(self):
        cmd = f"cd {self.wkc}/test/ci && ./run_check_void_container.sh -d {self.wkdir}",
        self.utils.run_command(cmd, silent=False, check=False)

    def run_function_return_test(self):
        print(f"PR number: {self.pr_number}, run number: {self.run_number}, extra param: {self.extra_param}")
        cmd = f"cd {self.wkc}/test/ci && ./run_scan_container.sh -d {self.wkdir} -b {self.pr_number}_{self.run_number} -f {self.wkdir}/tmp/{self.pr_number}_{self.run_number}/docs_changed.txt {self.extra_param}",
        self.utils.run_command(cmd, silent=False)

    def run_function_test(self):
        print(f"timeout: {self.timeout}")
        linux_cmds = [
            f"cd {self.wkc}/test/ci && export DEFAULT_RETRY_TIME=2",
            f"date",
            f"cd {self.wkc}/test/ci && {self.timeout} time ./run.sh -e -m /home/m.json -t cases.task -b PR-{self.utils.get_env_var('PR_NUMBER')}_{self.utils.get_env_var('GITHUB_RUN_NUMBER')} -l {self.wkdir}/log -o 1230 {self.utils.get_env_var('extra_param')}",
        ]
        mac_cmds = [
            "date",
            f"cd {self.wkc}/test && python3.9 -m venv .venv",
            f"cd {self.wkc}/test && source .venv/bin/activate && pip install --upgrade pip",
            f"cd {self.wkc}/test && source .venv/bin/activate && pip install -r requirements.txt",
            f"cd {self.wkc}/test && source .venv/bin/activate && sudo TAOS_BIN_PATH={self.wk}/debug/build/bin WORK_DIR=`pwd`/yourtest DYLD_LIBRARY_PATH={self.wk}/debug/build/lib pytest --clean cases/01-DataTypes/test_datatype_bigint.py",
            "date"
        ]
        windows_cmds = [
            "time",
            f"cd {self.wkc}/test && python3 ci/run_win_cases.py ci\\cases_win.task c:\\workspace\\ci-log\\PR-{self.utils.get_env_var('PR_NUMBER')}-{self.utils.get_env_var('GITHUB_RUN_NUMBER')}"
        ]
        if self.platform == 'linux':
            self.utils.run_commands(linux_cmds)
        elif self.platform == 'darwin':
            self.utils.run_commands(mac_cmds)
        elif self.platform == 'windows':
            self.utils.run_commands(windows_cmds)

    def run_tdgpt_test(self):
        print(f"timeout: {self.timeout}")
        linux_cmds = [
            f"cd {self.wkc}/test/ci && export DEFAULT_RETRY_TIME=2",
            f"date",
            f"cd {self.wkc}/test/ci && timeout 900 time ./run.sh -e -m /home/m.json -t tdgpt_cases.task -b PR-{self.utils.get_env_var('PR_NUMBER')}_{self.utils.get_env_var('GITHUB_RUN_NUMBER')} -l {self.wkdir}/log -o 900 {self.utils.get_env_var('extra_param')}",
        ]
        if self.platform == 'linux':
            self.utils.run_commands(linux_cmds)

    def run(self):
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
        elif self.test_type == 'tdgpt':
            self.run_tdgpt_test()
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
