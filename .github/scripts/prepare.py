import os
import json
import platform
from utils import Utils
from pathlib import Path

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
        self.container_name = self.utils.get_env_var('CONTAINER_NAME', 'taosd-test')
        self.wkdir = Path(os.getenv('WKDIR', '/var/lib/jenkins/workspace'))
        self.utils.set_env_var('WKDIR', self.wkdir, os.getenv('GITHUB_ENV', ''))
        self.platform = platform.system().lower()
        print(self.utils.get_env_var('IS_TDINTERNAL'))
        self.enterprise = False if self.utils.get_env_var('IS_TDINTERNAL') == 'false' else True
        self.wk = self.utils.path(os.path.join(self.wkdir, 'TDinternal'))
        self.wkc = self.utils.path(os.path.join(self.wk, 'community'))
        self.run_number = self.utils.get_env_var('GITHUB_RUN_NUMBER', 0)

        # Load GitHub context data
        self.event = json.loads(self.utils.get_env_var('GITHUB_EVENT', '{}'))
        self.inputs = json.loads(self.utils.get_env_var('GITHUB_INPUTS', '{}'))

        # Set branch variables
        self._set_branch_variables()

    def _set_branch_variables(self):
        """Determine source/target branches and PR number from inputs or event data"""
        if (self.inputs.get('specified_source_branch') == 'unavailable' and
            self.inputs.get('specified_target_branch') == 'unavailable' and
            self.inputs.get('specified_pr_number') == 'unavailable'):
            # From GitHub event
            pr = self.event.get('pull_request', {})
            self.source_branch = pr.get('head', {}).get('ref', '')
            self.target_branch = pr.get('base', {}).get('ref', '')
            self.pr_number = str(pr.get('number', ''))     
        else:
            # From inputs
            self.source_branch = self.inputs.get('specified_source_branch', '')
            self.target_branch = self.inputs.get('specified_target_branch', '')
            self.pr_number = self.inputs.get('specified_pr_number', '')

        self.utils.set_env_var('SOURCE_BRANCH', self.source_branch, os.getenv('GITHUB_ENV', ''))
        self.utils.set_env_var('TARGET_BRANCH', self.target_branch, os.getenv('GITHUB_ENV', ''))
        self.utils.set_env_var('PR_NUMBER', self.pr_number, os.getenv('GITHUB_ENV', ''))

    def prepare_repositories(self):
        """Prepare both TDengine or TDinternal repository"""
        print(f"Preparing TDinternal in {self.wkdir}...")
        if (self.inputs.get('specified_source_branch') == 'unavailable' and
        self.inputs.get('specified_target_branch') == 'unavailable' and
        self.inputs.get('specified_pr_number') == 'unavailable'):
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
            f"cd {repo_path} && git checkout {branch}"
        ]
        self.utils.run_commands(cmds)

    def update_submodules(self):
        cmd = "git submodule update --init --recursive"
        self.utils.run_command(cmd, cwd=self.wkc)

    def update_codes(self):
        """Update codes for TDengine or TDinternal"""
        print("is enterprise: ", self.enterprise)
        if self.enterprise:
            print("Updating codes for TDinternal...")
            self._update_lastest_merge_from_pr(self.wk, self.pr_number)
            self._update_latest_from_target_branch(self.wkc)
        else:
            print("Updating codes for community...")
            self._update_lastest_merge_from_pr(self.wkc, self.pr_number)
            self._update_latest_from_target_branch(self.wk)

    def _update_latest_from_target_branch(self, repo_path):
        """Update latest code from target branch"""
        cmds = [
            f"cd {repo_path} && git remote prune origin",
            f"cd {repo_path} && git pull > /dev/null",
            f"cd {repo_path} && git log -5",
            f"cd {repo_path} && echo 'community log: `git log -5`' >> {repo_path}/jenkins.log"
        ]
        self.utils.run_commands(cmds)

    def _update_lastest_merge_from_pr(self, repo_path, pr_number):
        """Update latest codes and merge from PR"""
        repo_name = 'TDinternal' if 'TDinternal' in str(repo_path) else 'TDengine'

        cmds = [
            f"cd { repo_path } && git pull >/dev/null",
            f"cd { repo_path } && git log -5",
            f'''echo `date "+%Y%m%d-%H%M%S"` {repo_name}Test/PR-{pr_number}:{self.run_number}:{self.target_branch} >> {self.wkdir}/jenkins.log''',
            f"cd { repo_path } && echo CHANGE_BRANCH:{self.source_branch} >> {self.wkdir}/jenkins.log",
            f"cd { repo_path } && echo {repo_name} log: `git log -5` >> {self.wkdir}/jenkins.log",
            f"cd { repo_path } && git fetch origin +refs/pull/{pr_number}/merge",
            f"cd { repo_path } && git checkout -qf FETCH_HEAD",
            f"cd { repo_path } && git log -5",
            f"cd { repo_path } && echo {repo_name} log merged: `git log -5` >> {self.wkdir}/jenkins.log"
        ]
        self.utils.run_commands(cmds)

    def outut_file_no_doc_change(self):
        cmds = [
            f"mkdir -p {self.wkdir}/tmp/{self.pr_number}_{self.run_number}",
            f"""
            cd {self.wkc} \
            && changed_files_non_doc=$(git --no-pager diff --name-only FETCH_HEAD `git merge-base FETCH_HEAD {self.target_branch}` | grep -v '^docs/en/' | grep -v '^docs/zh/' | grep -v '.md$' | tr '\n' ' ' || :) \
            && echo $changed_files_non_doc > {self.wkdir}/tmp/{self.pr_number}_{self.run_number}/docs_changed.txt
            """
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
            print("log_server.json file not found")
        print(f"timeout_cmd: {timeout_cmd}, extra_param: {extra_param}")
        self.utils.set_env_var("timeout_cmd", timeout_cmd, env_file=os.getenv('GITHUB_ENV', ''))
        self.utils.set_env_var("extra_param", extra_param, env_file=os.getenv('GITHUB_ENV', ''))

    def run(self):
        """Execute preparation steps"""
        print("Starting preparation phase...")
        try:
            # update scripts of .github repository
            self.output_environment_info()
            self.prepare_repositories()
            self.update_codes()
            self.update_submodules()
            if platform.system().lower() == 'linux':
                self.outut_file_no_doc_change()
                self.get_testing_params()
            print("Preparation phase completed successfully.")
            return True
        except Exception as e:
            print(f"Error during preparation: {str(e)}")
            return False

if __name__ == '__main__':
    prepare = TestPreparer()
    assert(prepare.run() == True)
