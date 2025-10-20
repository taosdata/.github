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

    def merge_task_files(self):
        """合并 cases_others.task 到 cases.task"""
        cases_task_path = os.path.join(self.wkc, 'test', 'ci', 'cases.task')
        cases_others_task_path = os.path.join(self.wkc, 'test', 'ci', 'cases_others.task')
        
        if not os.path.exists(cases_task_path):
            print(f"Warning: {cases_task_path} not found")
            return False
            
        if not os.path.exists(cases_others_task_path):
            print(f"Warning: {cases_others_task_path} not found")
            return False
        
        try:
            # 读取 cases_others.task 的内容
            with open(cases_others_task_path, 'r', encoding='utf-8') as f:
                others_content = f.read().rstrip()  # 移除末尾的空白字符
            
            # 追加到 cases.task
            with open(cases_task_path, 'a', encoding='utf-8') as f:
                # 添加一个换行符作为分隔
                f.write('\n')
                # 添加内容
                f.write(others_content)
                # 强制添加两个换行符确保文件正确结束
                f.write('\n\n')
            
            print(f"Successfully merged {cases_others_task_path} into {cases_task_path}")
            print("Added proper line endings to prevent execution issues")
            return True
            
        except Exception as e:
            print(f"Error merging task files: {e}")
            return False
    
    def run_function_test(self):
        print(f"timeout: {self.timeout}")
        
        self.merge_task_files()
        # 获取环境变量并提供默认值
        pr_number = self.utils.get_env_var('PR_NUMBER') or 'unknown'
        run_number = self.utils.get_env_var('GITHUB_RUN_NUMBER') or '0'
        extra_param = self.utils.get_env_var('extra_param') or ''
        
        # 处理 None 值
        if extra_param is None or extra_param == 'None':
            extra_param = ''
        
        branch_id = f"PR-{pr_number}_{run_number}"
    
        linux_cmds = [
            f"cd {self.wkc}/test/ci && export DEFAULT_RETRY_TIME=2",
            f"date",
            f"cd {self.wkc}/test/ci && timeout 36000 time ./run.sh -e -m /home/m.json -t cases.task -b {branch_id} -l {self.wkdir}/log -o 1230 {self.utils.get_env_var('extra_param')}".strip(),
        ]
        mac_cmds = [
            "date",
            f"cd {self.wkc}/test && python3.9 -m venv .venv",
            f"cd {self.wkc}/test && source .venv/bin/activate && pip install --upgrade pip",
            f"cd {self.wkc}/test && source .venv/bin/activate && pip install -r requirements.txt",
            f"cd {self.wkc}/test && source .venv/bin/activate && sudo TAOS_BIN_PATH={self.wk}/debug/build/bin WORK_DIR=`pwd`/yourtest DYLD_LIBRARY_PATH={self.wk}/debug/build/lib pytest --clean cases/01-DataTypes/test_datatype_bigint.py",
            "date"
        ]
        windows_cmds = f"cd {self.wkc}/test && python3 ci/run_win_cases.py ci/cases_win.task c:/workspace/0/ci-log/PR-{self.utils.get_env_var('PR_NUMBER')}-{self.utils.get_env_var('GITHUB_RUN_NUMBER')}"

        if self.platform == 'linux':
            self.utils.run_commands(linux_cmds)
        elif self.platform == 'darwin':
            self.utils.run_commands(mac_cmds)
        elif self.platform == 'windows':
            self.utils.run_command(windows_cmds)

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
        
        # 定义多种搜索模式来兼容不同的目录命名格式
        patterns = [
            f"PR-{self.pr_number}_{self.run_number}_*",           # PR-123_456_xxx
            f"PR-{self.pr_number}_{self.run_number}*",            # PR-123_456xxx (包含时间戳)
            f"PR-{self.pr_number}_*_{self.run_number}_*",         # PR-123_xxx_456_xxx
            f"PR-{self.pr_number}_*",                             # PR-123_xxx
            f"PR-unknown_{self.run_number}_*",                    # PR-unknown_456_xxx
            f"PR-*_{self.run_number}_*",                          # PR-xxx_456_xxx
        ]
        
        all_matching_dirs = []
        
        for i, pattern in enumerate(patterns, 1):
            search_pattern = os.path.join(log_base_dir, pattern)
            matching_dirs = glob.glob(search_pattern)
            
            print(f"Pattern{i} ({pattern}): Found {len(matching_dirs)} directories")
            
            # 过滤掉重复的目录
            for dir_path in matching_dirs:
                if dir_path not in all_matching_dirs:
                    all_matching_dirs.append(dir_path)
        
        if not all_matching_dirs:
            print("No existing test log directory found with any pattern")
            return None
        
        # 按修改时间排序，最新的在前面
        all_matching_dirs.sort(key=lambda x: os.path.getmtime(x), reverse=True)
        
        print(f"Total found {len(all_matching_dirs)} matching directories:")
        for i, dir_path in enumerate(all_matching_dirs[:10]):  # 只显示前10个
            mtime = os.path.getmtime(dir_path)
            mtime_str = datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M:%S')
            cases_exists = os.path.exists(os.path.join(dir_path, "cases"))
            dir_name = os.path.basename(dir_path)
            print(f"  {i+1}. {dir_name} (modified: {mtime_str}, cases dir: {'exists' if cases_exists else 'not_exists'})")
        
        if len(all_matching_dirs) > 10:
            print(f"  ... and {len(all_matching_dirs) - 10} more directories")
        
        # 优先选择包含 cases 目录的最新目录
        for dir_path in all_matching_dirs:
            cases_dir = os.path.join(dir_path, "cases")
            if os.path.exists(cases_dir):
                print(f"Selected directory with cases: {os.path.basename(dir_path)}")
                return dir_path
        
        # 如果没有找到包含 cases 目录的，选择最新的目录
        latest_dir = all_matching_dirs[0]
        print(f"Selected latest directory (no cases dir found): {os.path.basename(latest_dir)}")
        
        return latest_dir
            
    def run_coverage_test(self):
        print(f"PR number: {self.pr_number}, run number: {self.run_number}")
        print(f"timeout: {self.timeout}")
        print(f"Searching for test logs with PR number: '{self.pr_number}', run number: '{self.run_number}'")

        test_log_dir = self.find_latest_test_log_dir()
        
        if test_log_dir:
            print(f"✓ Found test log directory: {test_log_dir}")
            
            # 验证目录内容
            cases_dir = os.path.join(test_log_dir, "cases")
            if os.path.exists(cases_dir):
                case_count = len([f for f in os.listdir(cases_dir) if os.path.isdir(os.path.join(cases_dir, f))])
                print(f"  - Cases directory contains {case_count} test case directories")
            else:
                print(f"  - Warning: No cases directory found in {test_log_dir}")
        else:
            print("⚠ No existing test log directory found, coverage test will only use basic debug directory")
            test_log_dir = ""
    
        branch_id = self.utils.get_env_var('TARGET_BRANCH') or 'cover/3.0'
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