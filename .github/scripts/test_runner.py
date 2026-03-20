from datetime import datetime
import os
import platform
import shlex

from utils import Utils


class TestRunner:
    """This class runs the test cases for TDengine or TDinternal"""

    def __init__(self):
        self.utils = Utils()
        self.wkdir = self.utils.get_env_var("WKDIR")
        self.test_type = os.getenv("TEST_TYPE", "")
        self.wk = self.utils.path(os.path.join(self.wkdir, "TDinternal"))
        self.wkc = self.utils.path(os.path.join(self.wk, "community"))
        self.platform = platform.system().lower()
        self.pr_number = self.utils.get_env_var("PR_NUMBER")
        self.run_number = self.utils.get_env_var("GITHUB_RUN_NUMBER")
        self.run_attempt = self.utils.get_env_var("GITHUB_RUN_ATTEMPT")
        self.timeout = self.utils.get_env_var("timeout_cmd")
        self.extra_param = self.utils.get_env_var("extra_param")
        self.date_tag = datetime.now().strftime("%Y%m%d-%H%M%S")
        self.test_log_dir_name_base = f"PR-{self.pr_number}_{self.run_number}_{self.run_attempt}"
        self.test_log_dir_name = f"PR-{self.pr_number}_{self.run_number}_{self.run_attempt}_{self.date_tag}"
        self.mac_test_log_dir_name = str(self.wk.parent / f"PR-{self.pr_number}_{self.run_number}_{self.run_attempt}_{self.date_tag}")
        self.changed_files_path = self.utils.path(
            self.wkdir,
            "tmp",
            f"{self.pr_number}_{self.run_number}_{self.run_attempt}",
            "docs_changed.txt",
        )
        self.cases_task_diff_path = self.utils.path(
            self.wkdir,
            "tmp",
            f"{self.pr_number}_{self.run_number}_{self.run_attempt}",
            "cases_task_diff.txt",
        )
        self.cases_task_path = self.utils.path(self.wkc, "test", "ci", "cases.task")
        self.win_cases_task_path = self.utils.path(self.wkc, "test", "ci", "win_cases.task")
        self.temp_cases_task_path = self.utils.path(self.wkc, "test", "ci", "temp_run_cases.task")
        self.temp_win_cases_task_path = self.utils.path(self.wkc, "test", "ci", "temp_run_win_cases.task")

    def _read_changed_files(self):
        if not self.utils.file_exists(self.changed_files_path):
            return []

        content = self.utils.read_file(self.changed_files_path)
        return [
            file_path.strip().replace("\\", "/")
            for file_path in content.split()
            if file_path.strip()
        ]

    def _is_cases_only_change(self, changed_files):
        if not changed_files:
            return False

        allowed_case_prefix = "test/cases/"
        allowed_task_file = "test/ci/cases.task"
        return all(
            file_path.startswith(allowed_case_prefix) or file_path == allowed_task_file
            for file_path in changed_files
        )

    def _is_active_task_line(self, line):
        stripped = line.strip()
        return bool(stripped) and not stripped.startswith("#")

    def _normalize_case_token(self, token):
        normalized = token.strip().strip('"\'').replace("\\", "/")
        if normalized.startswith("./"):
            normalized = normalized[2:]
        return normalized

    def _extract_case_path_from_task_line(self, line):
        line = line.strip()
        if not line or line.startswith("#"):
            return ""

        parts = [part.strip() for part in line.split(",", 4)]
        if len(parts) < 5:
            return ""

        case_path_field = self._normalize_case_token(parts[3])
        if case_path_field and case_path_field != ".":
            if case_path_field.startswith("cases/"):
                return case_path_field
            if case_path_field.startswith(("tsim/", "sim/")):
                return case_path_field

        case_cmd = parts[4]
        cmd_parts = shlex.split(case_cmd)

        for token in cmd_parts:
            normalized = self._normalize_case_token(token)
            if normalized.startswith("--tsim="):
                tsim_path = self._normalize_case_token(normalized.split("=", 1)[1])
                if tsim_path:
                    return tsim_path
            if "cases/" in normalized and normalized.endswith((".py", ".sh")):
                return normalized[normalized.index("cases/") :]
            if normalized.startswith(("tsim/", "sim/")) and normalized.endswith(".sim"):
                return normalized

        return ""

    def _read_cases_task_diff(self):
        if not self.utils.file_exists(self.cases_task_diff_path):
            return {"added_lines": [], "removed_lines": []}

        added_lines = []
        removed_lines = []
        diff_content = self.utils.read_file(self.cases_task_diff_path)
        for raw_line in diff_content.splitlines():
            if raw_line.startswith(("diff --git", "index ", "--- ", "+++ ", "@@")):
                continue
            if raw_line.startswith("+"):
                task_line = raw_line[1:]
                if self._is_active_task_line(task_line):
                    added_lines.append(task_line)
            elif raw_line.startswith("-"):
                task_line = raw_line[1:]
                if self._is_active_task_line(task_line):
                    removed_lines.append(task_line)

        return {"added_lines": added_lines, "removed_lines": removed_lines}

    def _build_task_line_index(self, task_lines):
        line_index = {}
        for raw_line in task_lines:
            if not self._is_active_task_line(raw_line):
                continue
            case_path = self._extract_case_path_from_task_line(raw_line)
            if not case_path:
                continue
            line_index.setdefault(case_path, []).append(raw_line)
        return line_index

    def _dedupe_lines(self, task_lines):
        deduped_lines = []
        seen_lines = set()
        for raw_line in task_lines:
            if raw_line in seen_lines:
                continue
            deduped_lines.append(raw_line)
            seen_lines.add(raw_line)
        return deduped_lines

    def _resolve_task_lines_for_cases(self, task_path, selected_cases):
        task_content = self.utils.read_file(task_path)
        task_lines = task_content.splitlines()
        task_line_index = self._build_task_line_index(task_lines)

        matched_lines = []
        matched_cases = set()
        for case_path in sorted(selected_cases):
            if case_path in task_line_index:
                matched_lines.extend(task_line_index[case_path])
                matched_cases.add(case_path)

        return self._dedupe_lines(matched_lines), matched_cases

    def _write_task_file(self, target_task_path, task_lines):
        if not task_lines:
            return []

        self.utils.write_file(target_task_path, "\n".join(task_lines) + "\n")
        return task_lines

    def _get_case_selection(self):
        changed_files = self._read_changed_files()
        if not self._is_cases_only_change(changed_files):
            return {
                "enabled": False,
                "skip": False,
                "changed_cases": set(),
                "selected_cases": set(),
                "linux_task_lines": [],
                "unmatched_cases": set(),
            }

        changed_cases = {
            file_path[len("test/"):] for file_path in changed_files if file_path.startswith("test/cases/")
        }
        cases_task_diff = self._read_cases_task_diff()

        added_cases = {
            self._extract_case_path_from_task_line(line)
            for line in cases_task_diff["added_lines"]
            if self._extract_case_path_from_task_line(line)
        }
        selected_cases = changed_cases | added_cases
        linux_task_lines, matched_cases = self._resolve_task_lines_for_cases(
            self.cases_task_path,
            selected_cases,
        )
        unmatched_cases = changed_cases - matched_cases

        if unmatched_cases:
            print(
                "Skip changed cases not present in active cases.task entries: "
                f"{sorted(unmatched_cases)}"
            )

        if not linux_task_lines:
            print("Only cases.task comment/removal changes detected, skip function test.")
            return {
                "enabled": True,
                "skip": True,
                "changed_cases": changed_cases,
                "selected_cases": matched_cases,
                "linux_task_lines": [],
                "unmatched_cases": unmatched_cases,
            }

        print(
            "Only cases-related files changed, run selected cases only: "
            f"{sorted(matched_cases)}"
        )
        return {
            "enabled": True,
            "skip": False,
            "changed_cases": changed_cases,
            "selected_cases": matched_cases,
            "linux_task_lines": linux_task_lines,
            "unmatched_cases": unmatched_cases,
        }

    def _get_mac_case_commands(self):
        base_command = (
            f"cd {self.wkc}/test && source .venv/bin/activate && sudo "
            f"TAOS_BIN_PATH={self.wk}/debug/build/bin WORK_DIR=`pwd`/yourtest "
            f"DYLD_LIBRARY_PATH={self.wk}/debug/build/lib"
        )
        return [
            (
                "cases/01-DataTypes/test_datatype_bigint.py",
                f"{base_command} pytest --clean cases/01-DataTypes/test_datatype_bigint.py "
                f"|| (cp -rf {self.wk}/sim/* {self.mac_test_log_dir_name}/; "
                f"[ -d /cores ] && ls /cores/core* 1>/dev/null 2>&1 && "
                f"cp -rf /cores/core* {self.mac_test_log_dir_name}/ || true)",
            ),
            (
                "cases/81-Tools/03-Benchmark/test_benchmark_taosc.py",
                f"{base_command} pytest --clean cases/81-Tools/03-Benchmark/test_benchmark_taosc.py "
                f"|| (cp -rf {self.wk}/sim/* {self.mac_test_log_dir_name}/; "
                f"[ -d /cores ] && ls /cores/core* 1>/dev/null 2>&1 && "
                f"cp -rf /cores/core* {self.mac_test_log_dir_name}/ || true)",
            ),
        ]

    def run_assert_test(self):
        cmd = (
            f"cd {self.wkc}/test/ci && ./run_check_assert_container.sh -d {self.wkdir}"
        )
        self.utils.run_command(cmd, silent=False)

    def run_void_function_test(self):
        cmd = f"cd {self.wkc}/test/ci && ./run_check_void_container.sh -d {self.wkdir}"
        self.utils.run_command(cmd, silent=False)

    def run_function_return_test(self):
        print(
            f"PR number: {self.pr_number}, run number: {self.run_number}, attempt: {self.run_attempt}, extra param: {self.extra_param}"
        )
        cmd = f"cd {self.wkc}/test/ci && ./run_scan_container.sh -d {self.wkdir} -b {self.pr_number}_{self.run_number}_{self.run_attempt} -f {self.wkdir}/tmp/{self.pr_number}_{self.run_number}_{self.run_attempt}/docs_changed.txt {self.extra_param}"
        self.utils.run_command(cmd, silent=False)

    def run_function_test(self):
        print(f"timeout: {self.timeout}")
        case_selection = self._get_case_selection()
        if case_selection["enabled"] and case_selection["skip"]:
            return

        cases_task_name = "cases.task"
        windows_task_path = "ci/win_cases.task"
        if case_selection["enabled"]:
            matched_case_lines = self._write_task_file(
                self.temp_cases_task_path,
                case_selection["linux_task_lines"],
            )
            matched_win_task_lines, matched_win_cases = self._resolve_task_lines_for_cases(
                self.win_cases_task_path,
                case_selection["selected_cases"],
            )
            matched_win_case_lines = self._write_task_file(
                self.temp_win_cases_task_path,
                matched_win_task_lines,
            )

            if matched_case_lines:
                cases_task_name = "temp_run_cases.task"
                print(f"Use filtered linux task file: {self.temp_cases_task_path}")
            else:
                print("No matching case found in cases.task, skip linux function test.")

            if matched_win_case_lines:
                windows_task_path = "ci/temp_run_win_cases.task"
                print(f"Use filtered windows task file: {self.temp_win_cases_task_path}")
            else:
                print("No matching case found in win_cases.task, skip windows function test.")

            unmatched_win_cases = case_selection["selected_cases"] - matched_win_cases
            if unmatched_win_cases:
                print(
                    "Skip selected cases not present in active win_cases.task entries: "
                    f"{sorted(unmatched_win_cases)}"
                )

        linux_cmds = [
            f"cd {self.wkc}/test/ci && export DEFAULT_RETRY_TIME=1",
            "date",
            f"cd {self.wkc}/test/ci && {self.timeout} time ./run.sh -e -m /home/m.json -t {cases_task_name} -b {self.test_log_dir_name_base} -l {self.wkdir}/log -o 1230 {self.extra_param}",
        ]
        mac_cmds = [
            "date",
            f"mkdir -p {self.mac_test_log_dir_name}",
            f"cd {self.wkc}/test && python3.9 -m venv .venv",
            f"cd {self.wkc}/test && source .venv/bin/activate && pip install --upgrade pip",
            f"cd {self.wkc}/test && source .venv/bin/activate && pip install -r requirements.txt",
            "date",
        ]
        windows_copy_dll_cmd = f"copy {self.wkc}\\..\\debug\\build\\bin\\taos.dll C:\\Windows\\System32 && copy {self.wkc}\\..\\debug\\build\\bin\\pthreadVC3.dll C:\\Windows\\System32 && copy {self.wkc}\\..\\debug\\build\\bin\\taosnative.dll C:\\Windows\\System32"
        windows_cmds = f"cd {self.wkc}/test && python3 ci/run_win_cases.py {windows_task_path} c:/workspace/0/ci-log/{self.test_log_dir_name}"

        mac_case_commands = self._get_mac_case_commands()
        if case_selection["enabled"]:
            mac_case_commands = [
                (case_path, command)
                for case_path, command in mac_case_commands
                if case_path in case_selection["selected_cases"]
            ]
            if mac_case_commands:
                print(
                    "Run matching mac cases only: "
                    f"{[case_path for case_path, _ in mac_case_commands]}"
                )
            else:
                print("No matching mac case found in fixed mac case list, skip mac function test.")

        mac_cmds[5:5] = [command for _, command in mac_case_commands]

        if self.platform == "linux":
            if case_selection["enabled"] and cases_task_name == "cases.task":
                return
            self.utils.run_commands(linux_cmds)
        elif self.platform == "darwin":
            if case_selection["enabled"] and not mac_case_commands:
                return
            self.utils.run_commands(mac_cmds)
        elif self.platform == "windows":
            if case_selection["enabled"] and windows_task_path == "ci/win_cases.task":
                return
            self.utils.run_command(windows_copy_dll_cmd)
            self.utils.run_command(windows_cmds)

    def run_upgrade_compat_test(self):
        """Run cold/hot upgrade compatibility tests in an isolated Docker container (Linux only)"""
        print(f"PR number: {self.pr_number}, run number: {self.run_number}, attempt: {self.run_attempt}")
        log_dir = self.utils.path(self.wkdir, "log", "upgrade_compat")
        cmd = (
            f"cd {self.wkc}/test/ci && "
            f"bash run_upgrade_compat.sh -w {self.wkdir} -l {log_dir} -e"
        )
        self.utils.run_command(cmd, silent=False)

    def run_tdgpt_test(self):
        print(f"timeout: {self.timeout}")

        linux_cmds = [
            f"cd {self.wkc}/test/ci && export DEFAULT_RETRY_TIME=2",
            "date",
            f"cd {self.wkc}/test/ci && timeout 900 time ./run.sh -e -m /home/m.json -t tdgpt_cases.task -b {self.test_log_dir_name_base} -l {self.wkdir}/log -o 900 {self.extra_param}",
        ]
        if self.platform == "linux":
            self.utils.run_commands(linux_cmds)

    def run(self):
        if self.test_type == "assert":
            self.run_assert_test()
        elif self.test_type == "void":
            self.run_void_function_test()
        elif self.test_type == "function_returns":
            self.run_function_return_test()
        elif self.test_type == "function":
            self.run_function_test()
            if self.platform == "linux":
                self.cleanup()
        elif self.test_type == "upgrade_compat":
            self.run_upgrade_compat_test()
        elif self.test_type == "tdgpt":
            self.run_tdgpt_test()
        else:
            raise Exception("Invalid test type")

    def cleanup(self):
        """Clean up any remaining test processes"""
        print("Cleaning up running processes...")
        if self.platform == "linux":
            self.utils.kill_process("run_case.sh")


if __name__ == "__main__":
    test_runner = TestRunner()
    test_runner.run()
