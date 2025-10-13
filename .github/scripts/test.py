import os
import platform
import json
import glob
from datetime import datetime
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
        cmd = f"cd {self.wkc}/test/ci && ./run_check_assert_container.sh -d {self.wkdir}"
        self.utils.run_command(cmd, silent=False)

    def run_void_function_test(self):
        cmd = f"cd {self.wkc}/test/ci && ./run_check_void_container.sh -d {self.wkdir}"
        self.utils.run_command(cmd, silent=False)

    def run_function_return_test(self):
        print(f"PR number: {self.pr_number}, run number: {self.run_number}, extra param: {self.extra_param}")
        cmd = f"cd {self.wkc}/test/ci && ./run_scan_container.sh -d {self.wkdir} -b {self.pr_number}_{self.run_number} -f {self.wkdir}/tmp/{self.pr_number}_{self.run_number}/docs_changed.txt {self.extra_param}"
        self.utils.run_command(cmd, silent=False)

    def run_function_test(self):
        print(f"timeout: {self.timeout}")
        linux_cmds = [
            f"cd {self.wkc}/test/ci && export DEFAULT_RETRY_TIME=2",
            f"date",
            f"cd {self.wkc}/test/ci && {self.timeout} time ./run.sh -e -m /home/m.json -t cases.task -b PR-{self.utils.get_env_var('PR_NUMBER')}_{self.utils.get_env_var('GITHUB_RUN_NUMBER')} -l {self.wkdir}/log -o 1230 {self.utils.get_env_var('extra_param')}",
        ]
        # mac_cmds = [
        #     "date",
        #     f"cd {self.wkc}/test && python3.9 -m venv .venv",
        #     f"cd {self.wkc}/test && source .venv/bin/activate && pip install --upgrade pip",
        #     f"cd {self.wkc}/test && source .venv/bin/activate && pip install -r requirements.txt",
        #     f"cd {self.wkc}/test && source .venv/bin/activate && sudo TAOS_BIN_PATH={self.wk}/debug/build/bin WORK_DIR=`pwd`/yourtest DYLD_LIBRARY_PATH={self.wk}/debug/build/lib pytest --clean cases/01-DataTypes/test_datatype_bigint.py",
        #     "date"
        # ]
        # windows_cmds = f"cd {self.wkc}/test && python3 ci/run_win_cases.py ci/cases_win.task c:/workspace/0/ci-log/PR-{self.utils.get_env_var('PR_NUMBER')}-{self.utils.get_env_var('GITHUB_RUN_NUMBER')}"

        if self.platform == 'linux':
            self.utils.run_commands(linux_cmds)
        # elif self.platform == 'darwin':
        #     self.utils.run_commands(mac_cmds)
        # elif self.platform == 'windows':
        #     self.utils.run_command(windows_cmds)

    def run_tdgpt_test(self):
        print(f"timeout: {self.timeout}")
        linux_cmds = [
            f"cd {self.wkc}/test/ci && export DEFAULT_RETRY_TIME=2",
            f"date",
            f"cd {self.wkc}/test/ci && timeout 900 time ./run.sh -e -m /home/m.json -t tdgpt_cases.task -b PR-{self.utils.get_env_var('PR_NUMBER')}_{self.utils.get_env_var('GITHUB_RUN_NUMBER')} -l {self.wkdir}/log -o 900 {self.utils.get_env_var('extra_param')}",
        ]
        if self.platform == 'linux':
            self.utils.run_commands(linux_cmds)
            
    def find_latest_test_log_dir(self):
        log_base_dir = f"{self.wkdir}/log"
        if not os.path.exists(log_base_dir):
            print(f"No existing test log directory found: {log_base_dir}")
            return None
        
        pattern1 = f"PR-{self.pr_number}_{self.run_number}_*"
        search_pattern1 = os.path.join(log_base_dir, pattern1)
        matching_dirs1 = glob.glob(search_pattern1)
        
        pattern2 = f"PR-{self.pr_number}_*"
        search_pattern2 = os.path.join(log_base_dir, pattern2)
        matching_dirs2 = glob.glob(search_pattern2)
        
        print(f"Pattern1 ({pattern1}): Found {len(matching_dirs1)} cases directory")
        print(f"Pattern2 ({pattern2}): Found {len(matching_dirs2)} cases directory")
        
        matching_dirs = matching_dirs1 if matching_dirs1 else matching_dirs2
        
        if not matching_dirs:
            print("No existing test log directory found")
            return None
        
        matching_dirs.sort(key=lambda x: os.path.getmtime(x), reverse=True)
        
        for i, dir_path in enumerate(matching_dirs):
            mtime = os.path.getmtime(dir_path)
            mtime_str = datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M:%S')
            cases_exists = os.path.exists(os.path.join(dir_path, "cases"))
            print(f"  {i+1}. {os.path.basename(dir_path)} (data: {mtime_str}, cases dir: {'cases_exists' if cases_exists else 'cases_not_exists'})")
        
        latest_dir = matching_dirs[0]
        print(f"latest_dir: {latest_dir}")
        
        return latest_dir
            
    def run_coverage_test(self):
        print(f"PR number: {self.pr_number}, run number: {self.run_number}")
        print(f"timeout: {self.timeout}")
        
        test_log_dir = self.find_latest_test_log_dir()
        
        if test_log_dir:
            print(f"Found test log directory: {test_log_dir}")
        else:
            print("No existing test log directory found, coverage test will only use basic debug directory")
            test_log_dir = ""
    
        branch_id = self.utils.get_env_var('TARGET_BRANCH')
        print(f"Target branch: {branch_id}")
        print(f"Test log directory: {test_log_dir}")
        
        cmd = f"cd {self.wkc}/test/ci && ./run_coverage_container.sh -d {self.wkdir} -b {branch_id} -l {test_log_dir}"
        
        print(f"Running coverage test with command: {cmd}")
        self.utils.run_command(cmd, silent=False)

    def run(self):
        print(f"Test type: '{self.test_type}'") 
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
        elif self.test_type == 'coverage':
            self.run_coverage_test()
        else:
            raise Exception(f"Invalid test type: '{self.test_type}'")

    def cleanup(self):
        """Clean up any remaining test processes"""
        print("Cleaning up running processes...")
        if self.platform == 'linux':
            self.utils.kill_process('run_case.sh')

if __name__ == '__main__':
    test_runner = TestRunner()
    test_runner.run()
