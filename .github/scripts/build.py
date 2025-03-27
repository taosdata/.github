import os
import platform
from utils import Utils

class TestBuild:
    """This class provides utility functions for building TDengine or TDinternal"""
    def __init__(self):
        self.utils = Utils()
        self.workdir = self.utils.get_env_var('WKDIR', False)
        self.build_type = self.utils.get_env_var('BUILD_TYPE', 'repo')
        self.wk = self.utils.path(os.path.join(self.workdir, 'TDinternal'))
        self.wkc = self.utils.path(os.path.join(self.wk, 'community'))
        self.platform = platform.system().lower()

        self.ZH_DOC_REPO = 'docs.taosdata.com'
        self.EN_DOC_REPO = 'docs.tdengine.com'

    def docker_build(self):
        """Build TDinternal repo in docker, just for linux platform"""
        cmds = [
            'date',
            f'rm -rf {self.wkc}/debug',
            f'cd {self.wkc}/test/ci && time ./container_build.sh -w {self.workdir} -e'
        ]
        self.utils.run_commands(cmds)

    def doc_build(self):
        # build chinese doc
        cmd = 'yarn ass local && yarn build'
        self.utils.run_command(cmd, cwd=f'{self.workdir}/{self.ZH_DOC_REPO}')

        # build english doc
        self.utils.run_command(cmd, cwd=f'{self.workdir}/{self.EN_DOC_REPO}')

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
            'date'
            f'cd {self.wk} && rm -rf debug && mkdir debug && cd {self.wk}/debug'
            'echo $PATH'
            'echo "PATH=/opt/homebrew/bin:$PATH" >> $GITHUB_ENV'
            f'cd {self.wk}/debug && cmake .. -DBUILD_TEST=true -DBUILD_HTTPS=false  -DCMAKE_BUILD_TYPE=Release && make -j10'
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
            pass

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
