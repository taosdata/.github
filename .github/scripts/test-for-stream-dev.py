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

    def run_function_test(self):
        print(f"timeout: {self.timeout}")
        linux_cmds = [
            f"cd {self.wkc}/test/ci && export DEFAULT_RETRY_TIME=2",
            f"date",
            f"cd {self.wkc}/test/ci && {self.timeout} time ./run.sh -e -m /home/m.json -t ../tools/streamlist_for_ci.task -b PR-{self.utils.get_env_var('PR_NUMBER')}_{self.utils.get_env_var('GITHUB_RUN_NUMBER')} -l {self.wkdir}/log -o 1030 {self.utils.get_env_var('extra_param')}",
        ]
        if self.platform == 'linux':
            self.utils.run_commands(linux_cmds)

    def run(self):
        if self.test_type == 'function':
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
