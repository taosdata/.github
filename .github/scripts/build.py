import os
import platform
from utils import Utils
import shutil

class TestBuild:
    """This class provides utility functions for building TDengine or TDinternal"""
    def __init__(self):
        self.utils = Utils()
        self.wkdir = self.utils.get_env_var('WKDIR')
        self.build_type = self.utils.get_env_var('BUILD_TYPE')
        self.target_branch = self.utils.get_env_var('TARGET_BRANCH')
        self.wk = self.utils.path(os.path.join(self.wkdir, 'TDinternal'))
        self.wkc = self.utils.path(os.path.join(self.wk, 'community'))
        self.platform = platform.system().lower()

        self.ZH_DOC_REPO = 'docs.taosdata.com'
        self.EN_DOC_REPO = 'docs.tdengine.com'
        self.win_vs_path = "C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\VC\\Auxiliary\\Build\\vcvarsall.bat"
        self.win_cpu_type = "x64"

    def docker_build(self):
        """Build TDinternal repo in docker, just for linux platform"""
        cmds = [
            'date',
            f'rm -rf {self.wkc}/debug',
            f'cd {self.wkc}/test/ci && time ./container_build.sh -w {self.wkdir} -e -b {self.target_branch}'
        ]
        self.utils.run_commands(cmds)

    def doc_build(self):
        # build chinese doc
        cmd = 'yarn ass local && yarn build'
        self.utils.run_command(cmd, cwd=f'{self.wkdir}/{self.ZH_DOC_REPO}')

        # build english doc
        self.utils.run_command(cmd, cwd=f'{self.wkdir}/{self.EN_DOC_REPO}')

    def repo_build(self, install_dependencies=False):
        linux_cmds = [
            f'cd {self.wk} && rm -rf debug && mkdir debug && cd debug',
            f'cd {self.wk}/debug && cmake .. -DBUILD_TOOLS=true \
                -DBUILD_KEEPER=true \
                -DBUILD_HTTP=false \
                -DBUILD_TEST=true \
                -DWEBSOCKET=true \
                -DCMAKE_BUILD_TYPE=Release \
                -DBUILD_DEPENDENCY_TESTS=false',
            f'cd {self.wk}/debug && make -j 4 && sudo make install',
            'which taosd',
            'which taosadapter',
            'which taoskeeper'
        ]
        mac_cmds = [
            'date',
            f'cd {self.wk} && rm -rf debug && mkdir debug && cd {self.wk}/debug',
            'echo $PATH',
            'echo "PATH=/opt/homebrew/bin:$PATH" >> $GITHUB_ENV',
            f'cd {self.wk}/debug && cmake .. -DBUILD_TEST=true -DBUILD_HTTPS=false  -DCMAKE_BUILD_TYPE=Release && make -j10'
        ]
        windows_cmds = [
            # removed Unix rm -rf; we'll handle dir cleanup in Python below
            # call vcvarsall then run cmake and jom from the debug directory
            # using cmd /c so "call" and "&&" work on Windows
            f'cd {self.wk}\\debug  && call "{self.win_vs_path}" {self.win_cpu_type} && set CL=/MP8 && cmake .. -G "NMake Makefiles JOM" -DBUILD_TEST=true -DBUILD_TOOLS=true',
            f'cd {self.wk}\\debug  && jom -j6'
        ]
        if self.platform == 'linux':
            if install_dependencies:
                self.utils.install_dependencies('linux')
            self.utils.run_commands(linux_cmds)
        elif self.platform == 'darwin':
            if install_dependencies:
                self.utils.install_dependencies('macOS')
            self.utils.run_commands(mac_cmds)
        elif self.platform == 'windows':
            debug_dir = os.path.join(self.wk, 'debug')
            if os.path.isdir(debug_dir):
                shutil.rmtree(debug_dir)
            os.makedirs(debug_dir, exist_ok=True)

            # run the prepared windows commands (strings will be executed via cmd /c)
            for c in windows_cmds:
                # use run_command with string so run_command will dispatch to cmd /c on Windows
                self.utils.run_command(c, cwd=self.wk)

    def run(self):
        if self.build_type == 'docker':
            self.docker_build()
        elif self.build_type == 'doc':
            self.doc_build()
        elif self.build_type == 'repo':
            self.repo_build()
        else:
            raise ValueError(f"Invalid build type: {self.build_type}")

if __name__ == '__main__':
    build = TestBuild()
    build.run()
