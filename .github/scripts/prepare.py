import os
import json
import argparse
import platform
from .utils import Utils
from pathlib import Path

class TestPreparer:
    def __init__(self):
        self.utils = Utils()
        # initialize paths and platform from arguments
        self.wkdir = Path(os.getenv('WKDIR', '/var/lib/jenkins/workspace'))
        self.platform = platform.system().lower()

        self.enterprise = self.utils.get_env_var('IS_TDINTERNAL', False)
        self.wk = self.wkdir + os.sep + 'TDinternal'
        self.wkc = self.wk + os.sep + 'community'
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

        self._set_env_var('SOURCE_BRANCH', self.source_branch)
        self._set_env_var('TARGET_BRANCH', self.target_branch)
        self._set_env_var('PR_NUMBER', self.pr_number)

    def _set_env_var(self, name, value):
        """Set environment variable in specified file"""
        self.utils.set_env_var(name, value, os.getenv('GITHUB_ENV', ''))

    def prepare_repositories(self):
        """Prepare both TDengine or TDinternal repository"""
        if self.enterprise:
            print(f"Preparing TDinternal in {self.wkdir}...")
            if (self.inputs.get('specified_source_branch') == 'unavailable' and
            self.inputs.get('specified_target_branch') == 'unavailable' and
            self.inputs.get('specified_pr_number') == 'unavailable'):
                self._prepare_repo(self.wk, self.target_branch)
            else:
                self._prepare_repo(self.wk, self.source_branch)
            self._prepare_repo(self.wkc, self.target_branch)
        else:
            print(f"Preparing TDengine in {self.wkc}...")
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
        cmds = [
            f"cd {self.wkc} && git submodule update --init --recursive"
        ]
        self.utils.run_commands(cmds)

    def update_codes(self):
        if self.enterprise:
            self._update_lastest_merge_from_pr(self.wk, self.pr_number)
            self._update_latest_from_target_branch(self.wkc)
        else:
            self._update_lastest_merge_from_pr(self.wkc, self.pr_number)
            self._update_latest_from_target_branch(self.wk)

    def _update_latest_from_target_branch(self, repo_path):
        """Update latest code from target branch"""
        cmds = [
            f"cd {repo_path} && git remote prune origin",
            f"cd {repo_path} && git pull > /dev/null",
            f"cd {repo_path} && git log -5"
            f"cd {repo_path} && echo 'community log: `git log -5`' >> {repo_path}/jenkins.log"
        ]
        self.utils.run_commands(cmds)

    def _update_lastest_merge_from_pr(self, repo_path, pr_number):
        """Update latest codes and merge from PR"""
        cmds = [
            f"cd { repo_path } && git pull >/dev/null",
            f"cd { repo_path } && git log -5",
            f'''echo '`date "+%Y%m%d-%H%M%S"` TDinternalTest/{self.pr_number}:{self.run_number}:{self.target_branch}' >> {self.wkdir}/jenkins.log''',
            f"cd { repo_path } && echo 'CHANGE_BRANCH:{self.source_branch}' >> {repo_path}/jenkins.log",
            f"cd { repo_path } && echo 'TDinternal log: `git log -5`' >> {repo_path}/jenkins.log",
            f"cd { repo_path } && git fetch origin +refs/pull/{pr_number}/merge",
            f"cd { repo_path } && git checkout -qf FETCH_HEAD",
            f"cd { repo_path } && git log -5",
            f"cd { repo_path } && echo 'TDinternal log merged: `git log -5`' >> {repo_path}/jenkins.log"
        ]
        self.utils.run_commands(cmds)
    
    def outut_file_no_doc_change(self):
        cmds = [
            f"mkdir -p {self.wkdir}/tmp/{self.pr_number}_{self.run_number}",
            f"cd {self.wkc} \
            && changed_files_non_doc=$(git --no-pager diff --name-only FETCH_HEAD `git merge-base FETCH_HEAD $TARGET_BRANCH`|grep -v '^docs/en/'|grep -v '^docs/zh/'|grep -v '.md$' | tr '\n' ' ' || :) \
            && echo $changed_files_non_doc > {self.wkdir}/tmp/{self.pr_number}_{self.run_number}/docs_changed.txt"
        ]
        self.utils.run_commands(cmds)

    def run(self):
        """Execute preparation steps"""
        print("Starting preparation phase...")
        try:
            self.prepare_repositories()
            print("Preparation phase completed successfully.")
            self.update_codes()
            self.update_submodules()
            self.outut_file_no_doc_change()
            return True
        except Exception as e:
            print(f"Error during preparation: {str(e)}")
            return False

if __name__ == '__main__':
    prepare = TestPreparer()
    if prepare.run():
        print("Preparation completed successfully.")
    else:
        print("Preparation failed.")
