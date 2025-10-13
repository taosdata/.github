import os
import platform
from utils import Utils
import shutil
import subprocess

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

    def _find_vcvars(self) -> str:
        """Try to locate vcvarsall.bat using vswhere or common install paths"""
        # explicit configured path first
        if os.path.isfile(self.win_vs_path):
            return self.win_vs_path

        # try vswhere (Program Files x86)
        vswhere = os.path.join(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"), "Microsoft Visual Studio", "Installer", "vswhere.exe")
        try:
            if os.path.isfile(vswhere):
                out = subprocess.check_output([vswhere, "-latest", "-products", "*", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"], text=True).strip()
                if out:
                    candidate = os.path.join(out, "VC", "Auxiliary", "Build", "vcvarsall.bat")
                    if os.path.isfile(candidate):
                        return candidate
        except subprocess.CalledProcessError:
            pass

        # try other common paths
        common = [
            r"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat",
            r"C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat"
        ]
        for p in common:
            if os.path.isfile(p):
                return p
        return None
    
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

    def _vcvars_env(self, vcvars_path: str, arch: str) -> dict:
        cmd = f'{vcvars_path} {arch} && set'
        try:
            out = subprocess.check_output(['cmd', '/c', cmd], text=True, stderr=subprocess.STDOUT)
        except subprocess.CalledProcessError as e:
            print(f"vcvarsall.bat failed with output:\n{e.output}")
            raise
        env = {}
        for line in out.splitlines():
            if '=' in line:
                k, v = line.split('=', 1)
                env[k] = v
        return env
    def set_win_dev_env(self):
        vcvars_path = self._find_vcvars()
        if not vcvars_path:
            raise FileNotFoundError("Unable to find vcvarsall.bat")

        output = os.popen(f'{vcvars_path} x64 && set').read()

        for line in output.splitlines():
            pair = line.split("=", 1)
            if (len(pair) >= 2):
                os.environ[pair[0]] = pair[1]

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

            self.set_win_dev_env()
            # run cmake and build using the captured env (no need to use 'call' or 'set' in the same cmd)
            cmake_cmd = [
                'cmake', '..',
                '-G', 'NMake Makefiles JOM',
                '-DBUILD_TEST=true',
                '-DBUILD_TOOLS=true'
            ]
            self.utils.run_command(cmake_cmd, cwd=debug_dir, check=True)

            # run jom build
            self.utils.run_command(['jom', '-j6'], cwd=debug_dir, check=True)

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
