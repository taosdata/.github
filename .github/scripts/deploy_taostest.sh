#!/bin/bash

# Ensure the correct number of input parameters
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <pub_dl_url> <test_root> <pip_source>"
    echo "or"
    echo "Usage: $0 <pub_dl_url>"
    echo "Example:"
    echo "  $0 https:****/download /root/tests https://pypi.tuna.tsinghua.edu.cn/simple"
    exit 1
fi

# Input parameters
pub_dl_url="$1"             # Public download url
test_root="$2"             # TEST_ROOT for TestNG
pip_source="$3"            # Source of pip3

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/install_via_apt.sh" python3-pip wget

wget -N --no-clobber "$pub_dl_url"/wheels/taostest-0.1.5-py3-none-any.whl
pip3 install taostest-0.1.5-py3-none-any.whl -i "$pip_source"

# Set TEST_ROOT
echo "TEST_ROOT=$test_root"
ENV_FILE=~/.taostest/.env
mkdir -p ~/.taostest
touch $ENV_FILE
echo "TEST_ROOT=$TEST_ROOT" > $ENV_FILE
echo "TAOSTEST_SQL_RECORDING_ENABLED=True" >> $ENV_FILE