#!/usr/bin/env python3
"""
Prepare test environment across multiple machines
Executes git operations locally or remotely based on host configuration
"""

import json
import subprocess
import sys
from datetime import datetime
from typing import Dict, List, Optional, Tuple


class Colors:
    """ANSI color codes for terminal output"""
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    END = '\033[0m'


def log(msg: str, color: str = ''):
    """Print colored log message"""
    print(f"{color}{msg}{Colors.END}", flush=True)


def log_step(host: str, step: str, msg: str):
    """Print step information"""
    log(f"[{host}] {step}: {msg}", Colors.BLUE)


def log_success(host: str, msg: str):
    """Print success message"""
    log(f"[{host}] ✓ {msg}", Colors.GREEN)


def log_error(host: str, msg: str):
    """Print error message"""
    log(f"[{host}] ✗ {msg}", Colors.RED)


def run_cmd(
    cmd: str, 
    host: Optional[str] = None, 
    username: str = 'root', 
    check: bool = True,
    local_host: Optional[str] = None
) -> Tuple[int, str, str]:
    """
    Execute command locally or remotely
    
    Args:
        cmd: Command to execute
        host: Remote host IP (None for local execution)
        username: SSH username
        check: Raise exception on failure
        local_host: IP of the local machine (first in config)
    
    Returns:
        Tuple of (return_code, stdout, stderr)
    """
    is_local = (
        not host or 
        host in ['127.0.0.1', 'localhost'] or 
        (local_host and host == local_host)
    )
    
    if not is_local:
        ssh_cmd = [
            'ssh',
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'UserKnownHostsFile=/dev/null',
            '-o', 'LogLevel=ERROR',
            '-o', 'ConnectTimeout=10',
            f'{username}@{host}',
            cmd
        ]
        result = subprocess.run(ssh_cmd, capture_output=True, text=True)
    else:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    
    if check and result.returncode != 0:
        raise RuntimeError(f"Command failed: {cmd}\nError: {result.stderr}")
    
    return result.returncode, result.stdout, result.stderr


def prepare_repository(
    host: str, 
    username: str, 
    repo_path: str, 
    branch: str,
    local_host: Optional[str] = None
) -> bool:
    """
    Prepare git repository: reset, clean, fetch, checkout
    
    Args:
        host: Host IP
        username: SSH username
        repo_path: Repository path
        branch: Target branch
        local_host: IP of the local machine
    
    Returns:
        True if successful
    """
    log_step(host, "PREPARE", f"Repository {repo_path} -> {branch}")
    
    commands = [
        f"cd {repo_path} && git reset --hard",
        f"cd {repo_path} && git clean -fdx",
        f"cd {repo_path} && git remote prune origin",
        f"cd {repo_path} && git fetch",
        f"cd {repo_path} && git checkout {branch}",
    ]
    
    try:
        for cmd in commands:
            returncode, stdout, stderr = run_cmd(cmd, host, username, check=False, local_host=local_host)
            if returncode != 0:
                log_error(host, f"Failed: {cmd.split('&&')[-1].strip()}")
                log_error(host, f"Error: {stderr.strip()}")
                return False
        
        log_success(host, f"Prepared {repo_path}")
        return True
    
    except Exception as e:
        log_error(host, f"Exception: {e}")
        return False


def fetch_pr_merge(
    host: str, 
    username: str, 
    repo_path: str, 
    pr_number: str,
    local_host: Optional[str] = None
) -> bool:
    """
    Fetch and checkout PR merge commit
    
    Args:
        host: Host IP
        username: SSH username
        repo_path: Repository path
        pr_number: Pull request number
        local_host: IP of the local machine
    
    Returns:
        True if successful
    """
    log_step(host, "FETCH PR", f"#{pr_number} in {repo_path}")
    
    commands = [
        f"cd {repo_path} && git fetch origin +refs/pull/{pr_number}/merge",
        f"cd {repo_path} && git checkout -qf FETCH_HEAD",
    ]
    
    try:
        for cmd in commands:
            returncode, stdout, stderr = run_cmd(cmd, host, username, check=False, local_host=local_host)
            if returncode != 0:
                log_error(host, f"Failed: {cmd.split('&&')[-1].strip()}")
                log_error(host, f"Error: {stderr.strip()}")
                return False
        
        log_success(host, f"Fetched PR #{pr_number}")
        return True
    
    except Exception as e:
        log_error(host, f"Exception: {e}")
        return False


def show_logs(
    host: str, 
    username: str, 
    repo_path: str, 
    repo_name: str,
    local_host: Optional[str] = None
):
    """Show recent git logs"""
    cmd = f"cd {repo_path} && git log -5 --oneline"
    returncode, stdout, stderr = run_cmd(cmd, host, username, check=False, local_host=local_host)
    
    if returncode == 0 and stdout:
        log(f"[{host}] {repo_name} logs:", Colors.YELLOW)
        for line in stdout.strip().split('\n')[:5]:
            log(f"[{host}]   {line}", '')


def prepare_host(
    host_config: Dict,
    tdinternal_branch: str,
    tdengine_branch: str,
    pr_number: Optional[str],
    is_tdinternal_pr: bool,
    local_host: Optional[str] = None
) -> bool:
    """
    Prepare test environment on a single host
    
    Args:
        host_config: Host configuration dict
        tdinternal_branch: Branch for TDinternal repository
        tdengine_branch: Branch for TDengine/Community repository
        pr_number: PR number (if applicable)
        is_tdinternal_pr: Whether this is TDinternal PR
        local_host: IP of the local machine
    
    Returns:
        True if successful
    """
    host = host_config['host']
    username = host_config['username']
    workdir = host_config['workdir']
    
    wk = f"{workdir}/TDinternal"
    wkc = f"{wk}/community"
    
    log(f"\n{'='*70}", Colors.BOLD)
    log(f"Processing Host: {host}", Colors.BOLD)
    log(f"{'='*70}", Colors.BOLD)
    
    # Step 1: Prepare TDinternal repository
    if not prepare_repository(host, username, wk, tdinternal_branch, local_host):
        return False
    
    # Step 2: Prepare Community repository
    if not prepare_repository(host, username, wkc, tdengine_branch, local_host):
        return False
    
    # Step 3: Handle PR merge and pull latest
    if pr_number:
        if is_tdinternal_pr:
            # TDinternal PR: fetch merge into TDinternal, pull latest community
            log_step(host, "TDINTERNAL PR", f"Processing PR #{pr_number}")
            
            if not fetch_pr_merge(host, username, wk, pr_number, local_host):
                return False
            
            # Pull latest community (keep it on tdengine_branch)
            log_step(host, "UPDATE", "Pulling latest community")
            cmd = f"cd {wkc} && git pull"
            returncode, _, stderr = run_cmd(cmd, host, username, check=False, local_host=local_host)
            if returncode == 0:
                log_success(host, "Community updated")
            else:
                log(f"[{host}] ⚠ Community pull warning (non-fatal): {stderr.strip()}", Colors.YELLOW)
        
        else:
            # Community PR: fetch merge into community, pull latest TDinternal
            log_step(host, "COMMUNITY PR", f"Processing PR #{pr_number}")
            
            if not fetch_pr_merge(host, username, wkc, pr_number, local_host):
                return False
            
            # Pull latest TDinternal (keep it on tdinternal_branch)
            log_step(host, "UPDATE", "Pulling latest TDinternal")
            cmd = f"cd {wk} && git pull"
            returncode, _, stderr = run_cmd(cmd, host, username, check=False, local_host=local_host)
            if returncode == 0:
                log_success(host, "TDinternal updated")
            else:
                log(f"[{host}] ⚠ TDinternal pull warning (non-fatal): {stderr.strip()}", Colors.YELLOW)
    
    else:
        # No PR: just pull both repos
        log_step(host, "UPDATE", "Pulling latest changes")
        for path in [wk, wkc]:
            cmd = f"cd {path} && git pull"
            run_cmd(cmd, host, username, check=False, local_host=local_host)
    
    # Step 4: Show logs
    show_logs(host, username, wk, "TDinternal", local_host)
    show_logs(host, username, wkc, "Community", local_host)
    
    # Step 5: Write jenkins.log (only on local machine)
    is_local = host in ['127.0.0.1', 'localhost'] or (local_host and host == local_host)
    if is_local and pr_number:
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        repo_name = "TDinternal" if is_tdinternal_pr else "TDengine"
        log_entry = f"{timestamp} {repo_name}CI/PR-{pr_number}:{tdengine_branch}"
        
        cmd = f"echo '{log_entry}' >> {workdir}/jenkins.log"
        run_cmd(cmd, host, username, check=False, local_host=local_host)
        log_success(host, "Jenkins log written")
    
    log_success(host, f"Host preparation completed")
    return True


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Prepare test environment across multiple machines',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Prepare for TDinternal PR (TDinternal PR branch + TDengine target branch)
  %(prog)s -c machines.json --pr 12345 --tdinternal --tdinternal-branch feature/new-api --tdengine-branch 3.0

  # Prepare for Community PR (TDinternal target branch + TDengine PR branch)
  %(prog)s -c machines.json --pr 67890 --tdinternal-branch 3.0 --tdengine-branch feature/new-feature

  # Just update to latest (no PR, both use target branches)
  %(prog)s -c machines.json --tdinternal-branch 3.0 --tdengine-branch 3.0
        """
    )
    
    parser.add_argument('-c', '--config', required=True, help='Path to machines.json')
    parser.add_argument('--tdinternal-branch', default='3.0', help='Branch for TDinternal repository (default: 3.0)')
    parser.add_argument('--tdengine-branch', default='3.0', help='Branch for TDengine/Community repository (default: 3.0)')
    parser.add_argument('--pr', help='Pull request number')
    parser.add_argument('--tdinternal', action='store_true', help='Is TDinternal PR (default: Community PR)')
    
    args = parser.parse_args()
    
    # Load configuration
    try:
        with open(args.config, 'r') as f:
            machines = json.load(f)
    except Exception as e:
        log_error("CONFIG", f"Failed to load {args.config}: {e}")
        sys.exit(1)
    
    # Use first host as local machine
    local_host = machines[0]['host'] if machines else None
    
    log(f"\n{'='*70}", Colors.BOLD)
    log("Test Environment Preparation", Colors.BOLD)
    log(f"{'='*70}", Colors.BOLD)
    log(f"Local Host: {local_host}", Colors.GREEN)
    log(f"TDinternal Branch: {args.tdinternal_branch}", Colors.YELLOW)
    log(f"TDengine Branch: {args.tdengine_branch}", Colors.YELLOW)
    log(f"PR Number: {args.pr or 'N/A'}", '')
    log(f"Is TDinternal PR: {args.tdinternal}", '')
    log(f"Total Hosts: {len(machines)}", '')
    
    # Process each host
    results = {}
    for machine in machines:
        host = machine['host']
        try:
            success = prepare_host(
                machine,
                args.tdinternal_branch,
                args.tdengine_branch,
                args.pr,
                args.tdinternal,
                local_host
            )
            results[host] = success
        except Exception as e:
            log_error(host, f"Unexpected error: {e}")
            results[host] = False
    
    # Summary
    log(f"\n{'='*70}", Colors.BOLD)
    log("Summary", Colors.BOLD)
    log(f"{'='*70}", Colors.BOLD)
    
    success_count = sum(1 for v in results.values() if v)
    total_count = len(results)
    
    for host, success in results.items():
        if success:
            log_success(host, "SUCCESS")
        else:
            log_error(host, "FAILED")
    
    log(f"\nTotal: {success_count}/{total_count} succeeded", Colors.BOLD)
    
    sys.exit(0 if all(results.values()) else 1)


if __name__ == '__main__':
    main()