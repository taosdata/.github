#!/bin/bash
# =============================================================================
# build_offline_pkg.sh — Orchestrator for building offline packages
#
# Runs prepare_offline_pkg.sh either directly (native) or inside a Docker
# container.  Fully parameterized so it works the same way from a terminal
# or from a GitHub Actions workflow.
#
# Usage modes:
#   1. Native   — run on the current host directly
#   2. Docker   — spin up a container, mount scripts, run inside it
#
# Examples:
#   # List supported OS targets
#   ./build_offline_pkg.sh --list-os
#
#   # Native (on an Ubuntu 22.04 host)
#   ./build_offline_pkg.sh --mode=native \
#       --system-packages=gdb,valgrind --pkg-label=delivery-20260227
#
#   # Docker (build Ubuntu 22.04 package)
#   ./build_offline_pkg.sh --mode=docker --os=ubuntu --os-ver=22.04 \
#       --system-packages=gdb,valgrind,bpftrace --pkg-label=delivery-20260227
#
#   # Docker + openEuler 24.03
#   ./build_offline_pkg.sh --mode=docker --os=openeuler --os-ver=24.03-lts-sp2 \
#       --system-packages=gdb,valgrind,bpftrace,perf --pkg-label=delivery-20260227
#
#   # ARM64 build
#   ./build_offline_pkg.sh --mode=docker --os=ubuntu --os-ver=22.04 \
#       --arch=arm64 --system-packages=gdb,valgrind --pkg-label=delivery-arm64
# =============================================================================

set -euo pipefail

# ======================== Color helpers ========================
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'; RESET='\033[0m'
red_echo()    { echo -e "${RED}$*${RESET}"; }
green_echo()  { echo -e "${GREEN}$*${RESET}"; }
yellow_echo() { echo -e "${YELLOW}$*${RESET}"; }
cyan_echo()   { echo -e "${CYAN}$*${RESET}"; }

# ======================== Supported OS Registry ===============
# Key:   "<os>:<version>"
# Value: "<docker_image>|<supported_archs>"
#
# To add a new OS target, simply add a new entry below.
# The container name is auto-generated: offline-pkg-<os>-<ver>-<arch>-<pid>
declare -A OS_REGISTRY=(
    # ---- Ubuntu ----
    ["ubuntu:20.04"]="ubuntu:20.04|x64,arm64"
    ["ubuntu:22.04"]="ubuntu:22.04|x64,arm64"
    ["ubuntu:24.04"]="ubuntu:24.04|x64,arm64"
    # ---- CentOS ----
    ["centos:7"]="centos:7|x64"
    # ---- Kylin ----
    ["kylin:v10-sp2"]="macrosan/kylin:v10-sp2|x64,arm64"
    ["kylin:v10-sp3-2403"]="macrosan/kylin:v10-sp3-2403|x64,arm64"
    # ---- openEuler ----
    ["openeuler:20.03-lts"]="openeuler/openeuler:20.03-lts|x64,arm64"
    ["openeuler:20.03-lts-sp1"]="openeuler/openeuler:20.03-lts-sp1|x64,arm64"
    ["openeuler:20.03-lts-sp2"]="openeuler/openeuler:20.03-lts-sp2|x64,arm64"
    ["openeuler:20.03-lts-sp3"]="openeuler/openeuler:20.03-lts-sp3|x64,arm64"
    ["openeuler:20.03-lts-sp4"]="openeuler/openeuler:20.03-lts-sp4|x64,arm64"
    ["openeuler:22.03-lts"]="openeuler/openeuler:22.03-lts|x64,arm64"
    ["openeuler:22.03-lts-sp1"]="openeuler/openeuler:22.03-lts-sp1|x64,arm64"
    ["openeuler:22.03-lts-sp2"]="openeuler/openeuler:22.03-lts-sp2|x64,arm64"
    ["openeuler:22.03-lts-sp3"]="openeuler/openeuler:22.03-lts-sp3|x64,arm64"
    ["openeuler:22.03-lts-sp4"]="openeuler/openeuler:22.03-lts-sp4|x64,arm64"
    ["openeuler:24.03-lts"]="openeuler/openeuler:24.03-lts|x64,arm64"
    ["openeuler:24.03-lts-sp1"]="openeuler/openeuler:24.03-lts-sp1|x64,arm64"
    ["openeuler:24.03-lts-sp2"]="openeuler/openeuler:24.03-lts-sp2|x64,arm64"
    ["openeuler:24.03-lts-sp3"]="openeuler/openeuler:24.03-lts-sp3|x64,arm64"
)

# ======================== Defaults ============================
# -- Orchestrator params --
RUN_MODE="native"                           # native | docker
OS_KEY=""                                   # e.g. ubuntu, centos, kylin, openeuler
OS_VER=""                                   # e.g. 22.04, 7, v10-sp3-2403, 24.03-lts-sp2
ARCH=""                                     # x64 | arm64 (auto-detect if empty)
DOCKER_IMAGE=""                             # resolved from OS_KEY:OS_VER, or set directly
CONTAINER_NAME=""                           # explicit override; leave empty to use pool
CONTAINER_NAME_EXPLICIT=false               # true when --container-name is user-specified
CONTAINER_BASE_NAME=""                      # base name for pool (derived from os+ver+arch)
CONTAINER_POOL_SIZE=5                       # max parallel containers in the pool
CONTAINER_STATUS=""                         # set at runtime: new | stopped | running
CONTAINER_ENGINE="docker"                   # docker | podman
OUTPUT_DIR=""                               # host dir for output (default: ./offline_pkgs)
CACHE_DIR=""                                # host cache dir (default: /tmp/taos-packages)
CLEANUP_CONTAINER="false"                   # remove container after build (default: keep for reuse)
DOCKER_PLATFORM=""                          # e.g. linux/arm64 (for cross-arch builds)
DOCKER_EXTRA_ARGS=""                        # extra args passed to docker run

# -- Action --
ACTION="build"                              # build | test | build-and-test
PKG_LABEL=""                                # extracted from FORWARD_ARGS for build-lock key
BUILD_LOCK_FD=""                            # file descriptor held by flock
BUILD_LOCK_FILE=""                          # lock file path on host

# -- All remaining flags are forwarded verbatim to prepare_offline_pkg.sh --
FORWARD_ARGS=()

# ======================== Script location =====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ======================== Architecture detection ==============
detect_host_arch() {
    local machine
    machine="$(uname -m)"
    case "$machine" in
        x86_64|amd64)   echo "x64" ;;
        aarch64|arm64)  echo "arm64" ;;
        *)              echo "$machine" ;;
    esac
}

# ======================== OS resolution =======================
# Resolve --os + --os-ver into DOCKER_IMAGE and CONTAINER_NAME
resolve_os() {
    local key="${OS_KEY}:${OS_VER}"

    if [[ -z "${OS_REGISTRY[$key]+_}" ]]; then
        red_echo "ERROR: Unsupported OS target: '${key}'"
        red_echo ""
        list_supported_os
        exit 1
    fi

    local entry="${OS_REGISTRY[$key]}"
    local supported_archs
    IFS='|' read -r DOCKER_IMAGE supported_archs <<< "$entry"

    # Validate architecture against supported list
    if [[ ! ",$supported_archs," == *",$ARCH,"* ]]; then
        red_echo "ERROR: OS '${key}' does not support architecture '${ARCH}'"
        red_echo "  Supported architectures: ${supported_archs}"
        exit 1
    fi

    # Build the container pool base name from the OS key
    local safe_ver="${OS_VER//[.:]/-}"
    CONTAINER_BASE_NAME="offline-pkg-${OS_KEY}-${safe_ver}-${ARCH}"

    green_echo "Resolved OS target:"
    green_echo "  Key:        ${key}"
    green_echo "  Image:      ${DOCKER_IMAGE}"
    green_echo "  Arch:       ${ARCH}"
    if [[ "$CONTAINER_NAME_EXPLICIT" == "true" ]]; then
        green_echo "  Container:  ${CONTAINER_NAME} (explicit, bypasses pool)"
    else
        green_echo "  Pool base:  ${CONTAINER_BASE_NAME}-{1..${CONTAINER_POOL_SIZE}}"
    fi
}

# ======================== List supported OS ===================
list_supported_os() {
    cyan_echo "Supported OS targets (--os=<name> --os-ver=<version>):"
    cyan_echo ""
    printf "  %-16s  %-24s  %-40s  %s\n" \
        "OS (--os)" "Version (--os-ver)" "Docker Image" "Architectures"
    printf "  %-16s  %-24s  %-40s  %s\n" \
        "────────────────" "────────────────────────" \
        "────────────────────────────────────────" "──────────────"
    for key in $(printf '%s\n' "${!OS_REGISTRY[@]}" | sort); do
        local os_name="${key%%:*}"
        local os_ver="${key#*:}"
        local entry="${OS_REGISTRY[$key]}"
        local img archs
        IFS='|' read -r img archs <<< "$entry"
        printf "  %-16s  %-24s  %-40s  %s\n" "$os_name" "$os_ver" "$img" "$archs"
    done
    echo ""
}

# ======================== Usage ===============================
show_usage() {
    cat <<'EOF'
build_offline_pkg.sh — Orchestrator for building offline packages

TARGET OS OPTIONS:
  --os=<name>                   OS name: ubuntu, centos, kylin, openeuler
  --os-ver=<version>            OS version: 22.04, 7, v10-sp3-2403, 24.03-lts-sp1, 24.03-lts-sp2
  --arch=<x64|arm64>            Target architecture (default: auto-detect from host)
  --list-os                     List all supported OS targets and exit

ORCHESTRATOR OPTIONS:
  --mode=<native|docker>        Run mode (default: native)
  --action=<action>             build | test | build-and-test (default: build)
  --container-name=<name>       Explicit container name, bypasses pool (default: auto pool)
  --container-pool-size=<n>     Max parallel containers in pool (default: 5)
  --container-engine=<cmd>      Container runtime: docker or podman (default: docker)
  --output-dir=<path>           Host directory for output artifacts (default: ./offline_pkgs)
  --cache-dir=<path>            Host cache directory for downloads (default: /tmp/taos-packages)
  --cleanup-container=<bool>    Remove container after build (default: false, kept for reuse)
  --docker-platform=<platform>  Platform flag, e.g. linux/arm64 (optional)
  --docker-extra-args=<args>    Extra arguments for docker run (optional)
  --docker-image=<image>        [Advanced] Override Docker image directly (skip OS validation)

PASS-THROUGH OPTIONS (forwarded to prepare_offline_pkg.sh):
  --system-packages=<pkgs>      Comma-separated system packages
  --python-version=<ver>        Python version (e.g. 3.10)
  --python-packages=<pkgs>      Comma-separated Python packages
  --python-requirements=<url>   Requirements file URL or path
  --pkg-label=<label>           Package label (e.g. delivery-20260227)
  --tdgpt=<true|false>          Enable TDgpt venv build
  --tdgpt-all                   Build all TDgpt model venvs
  --tdengine-tsdb-ver=<ver>     TDengine version tag for requirements download
  --pip-index-url=<url>         Pip mirror URL
  --pytorch-whl-url=<url>       PyTorch wheel mirror URL
  --install-docker              Include Docker in offline package
  --docker-version=<ver>        Docker version to package
  --install-docker-compose      Include Docker Compose
  --docker-compose-version=<v>  Docker Compose version
  --install-java                Include Java JRE
  --java-version=<ver>          Java version (8,11,17,21,23)
  --idmp=<true|false>           Include IDMP packages
  --idmp-ver=<ver>              IDMP version for requirements download (e.g. 1.0.12.10, maps to tag ver-<ver>)
  --gh-token=<token>            GitHub token for private repos (required for TDasset)
  --bpftrace-version=<ver>      bpftrace version
  --tdgpt-base-dir=<path>       TDgpt base directory
  --idmp-venv-dir=<path>        IDMP venv directory

ENVIRONMENT VARIABLES (optional, override defaults):
  PARENT_DIR                    Override output root inside container (default: /opt/offline-env)
  GITHUB_ACTIONS                Set to "true" when running in GitHub Actions

EXAMPLES:
  # List all supported OS targets
  ./build_offline_pkg.sh --list-os

  # Native build on current host
  ./build_offline_pkg.sh --mode=native \
      --system-packages=gdb,valgrind --pkg-label=delivery-20260227

  # Build for Ubuntu 22.04 via Docker
  ./build_offline_pkg.sh --mode=docker --os=ubuntu --os-ver=22.04 \
      --system-packages=gdb,valgrind,bpftrace --pkg-label=delivery-20260227

  # Build for openEuler 24.03 via Docker
  ./build_offline_pkg.sh --mode=docker --os=openeuler --os-ver=24.03-lts-sp2 \
      --system-packages=gdb,valgrind,bpftrace,perf --pkg-label=delivery-20260227

  # Build for CentOS 7
  ./build_offline_pkg.sh --mode=docker --os=centos --os-ver=7 \
      --system-packages=gdb,valgrind,bpftrace,perf --pkg-label=delivery-20260227

  # Build TDgpt full package for Kylin V10 SP3
  ./build_offline_pkg.sh --mode=docker --os=kylin --os-ver=v10-sp3-2403 \
      --system-packages=build-essential --python-version=3.10 \
      --tdgpt=true --tdgpt-all --tdengine-tsdb-ver=3.4.0.8 --pkg-label=tdgpt-all

  # Build + test in one go
  ./build_offline_pkg.sh --mode=docker --os=ubuntu --os-ver=22.04 \
      --action=build-and-test --system-packages=gdb,valgrind --pkg-label=delivery-20260227

  # ARM64 build
  ./build_offline_pkg.sh --mode=docker --os=ubuntu --os-ver=22.04 \
      --arch=arm64 --system-packages=gdb,valgrind --pkg-label=delivery-arm64
EOF
    exit 1
}

# ======================== Parse args ==========================
parse_args() {
    if [[ $# -eq 0 ]]; then
        show_usage
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --os=*)
                OS_KEY="${1#*=}"
                ;;
            --os-ver=*)
                OS_VER="${1#*=}"
                ;;
            --arch=*)
                ARCH="${1#*=}"
                ;;
            --list-os)
                list_supported_os
                exit 0
                ;;
            --mode=*)
                RUN_MODE="${1#*=}"
                ;;
            --docker-image=*)
                DOCKER_IMAGE="${1#*=}"
                ;;
            --container-name=*)
                CONTAINER_NAME="${1#*=}"
                CONTAINER_NAME_EXPLICIT=true
                ;;
            --container-pool-size=*)
                CONTAINER_POOL_SIZE="${1#*=}"
                ;;
            --container-engine=*)
                CONTAINER_ENGINE="${1#*=}"
                ;;
            --output-dir=*)
                OUTPUT_DIR="${1#*=}"
                ;;
            --cache-dir=*)
                CACHE_DIR="${1#*=}"
                ;;
            --cleanup-container=*)
                CLEANUP_CONTAINER="${1#*=}"
                ;;
            --docker-platform=*)
                DOCKER_PLATFORM="${1#*=}"
                ;;
            --docker-extra-args=*)
                DOCKER_EXTRA_ARGS="${1#*=}"
                ;;
            --action=*)
                ACTION="${1#*=}"
                ;;
            --pkg-label=*)
                # Peek at pkg-label so we can use it for the build lock key.
                # Still forwarded to prepare_offline_pkg.sh via FORWARD_ARGS.
                PKG_LABEL="${1#*=}"
                FORWARD_ARGS+=("$1")
                ;;
            -h|--help)
                show_usage
                ;;
            # Everything else is forwarded to prepare_offline_pkg.sh
            *)
                FORWARD_ARGS+=("$1")
                ;;
        esac
        shift
    done
}

# ======================== Validate ============================
validate() {
    # Validate run mode
    case "$RUN_MODE" in
        native|docker) ;;
        *)
            red_echo "ERROR: --mode must be 'native' or 'docker', got: $RUN_MODE"
            exit 1
            ;;
    esac

    # Validate action
    case "$ACTION" in
        build|test|build-and-test) ;;
        *)
            red_echo "ERROR: --action must be 'build', 'test', or 'build-and-test', got: $ACTION"
            exit 1
            ;;
    esac

    # Auto-detect architecture if not specified
    if [[ -z "$ARCH" ]]; then
        ARCH="$(detect_host_arch)"
        yellow_echo "Auto-detected architecture: ${ARCH}"
    fi

    # Validate architecture value
    case "$ARCH" in
        x64|arm64) ;;
        *)
            red_echo "ERROR: --arch must be 'x64' or 'arm64', got: $ARCH"
            exit 1
            ;;
    esac

    # Resolve Docker image in docker mode
    if [[ "$RUN_MODE" == "docker" ]]; then
        if [[ -n "$OS_KEY" && -n "$OS_VER" ]]; then
            # Strict OS registry lookup
            resolve_os
        elif [[ -n "$DOCKER_IMAGE" ]]; then
            # Advanced: direct image override (skip OS validation)
            yellow_echo "WARNING: Using --docker-image directly bypasses OS registry validation"
            local img_tag="${DOCKER_IMAGE//[:/]/-}"
            CONTAINER_BASE_NAME="offline-pkg-${img_tag}-${ARCH}"
        else
            red_echo "ERROR: Docker mode requires --os + --os-ver (or --docker-image for advanced use)"
            red_echo ""
            list_supported_os
            exit 1
        fi

        # Verify container engine is available
        if ! command -v "$CONTAINER_ENGINE" &>/dev/null; then
            red_echo "ERROR: $CONTAINER_ENGINE is not installed or not in PATH"
            exit 1
        fi
    fi

    # Default output directory
    if [[ -z "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR="${SCRIPT_DIR}/offline_pkgs"
    fi
}

# ======================== Build lock =========================
# Prevents two parallel builds from writing to the same output directory.
# Lock key = os + os-ver + arch + pkg-label (the four values that determine
# the output directory name inside OUTPUT_DIR).
#
# Uses a non-blocking flock so a conflicting build fails immediately instead
# of waiting silently.  The lock is released automatically when this process
# exits (fd closed by kernel), so no explicit cleanup is needed on success.
acquire_build_lock() {
    # Only lock for docker+build actions (test reads, not writes)
    if [[ "$RUN_MODE" != "docker" || "$ACTION" == "test" ]]; then
        return
    fi

    local host_cache_dir="${CACHE_DIR:-/tmp/taos-packages}"
    mkdir -p "$host_cache_dir"

    # Build a deterministic lock key from the four dimensions that decide
    # the output directory name.
    local os_part="${OS_KEY:-$(echo "$DOCKER_IMAGE" | tr '/: ' '-')}"
    local ver_part="${OS_VER//[.:]/-}"
    local label_part="${PKG_LABEL:-noLabel}"
    local lock_key="${os_part}-${ver_part}-${ARCH}-${label_part}"
    BUILD_LOCK_FILE="${host_cache_dir}/.build-lock-${lock_key}"

    # Open the lock file on a free fd (search 200-209)
    local fd
    for fd in $(seq 200 209); do
        if ! ( : >&${fd} ) 2>/dev/null; then
            BUILD_LOCK_FD=$fd
            break
        fi
    done
    if [[ -z "$BUILD_LOCK_FD" ]]; then
        red_echo "ERROR: Could not allocate a file descriptor for build lock"
        exit 1
    fi

    # Open fd pointing at the lock file
    eval "exec ${BUILD_LOCK_FD}>\"${BUILD_LOCK_FILE}\""

    # Try non-blocking exclusive lock
    if ! flock -n "$BUILD_LOCK_FD"; then
        # Read who holds the lock (we write PID into it)
        local holder
        holder=$(cat "$BUILD_LOCK_FILE" 2>/dev/null || echo "unknown")
        red_echo "ERROR: Another build is already in progress for the same target."
        red_echo "  Lock key:  ${lock_key}"
        red_echo "  Lock file: ${BUILD_LOCK_FILE}"
        red_echo "  Held by:   PID ${holder}"
        red_echo "  Wait for that build to complete, or remove the lock file if it is stale:"
        red_echo "    rm -f ${BUILD_LOCK_FILE}"
        # Close the fd we opened
        eval "exec ${BUILD_LOCK_FD}>&-"
        exit 1
    fi

    # Write our PID into the lock file so others can see who holds it
    echo $$ >"$BUILD_LOCK_FILE"
    green_echo "Build lock acquired: ${lock_key}  (PID $$)"
}

# ======================== Native mode =========================
run_native() {
    local action_flag="${1:-}"
    [[ -n "$action_flag" ]] || { red_echo "BUG: run_native() called without action argument"; exit 1; }
    cyan_echo "=== Running in NATIVE mode (action=$action_flag) ==="

    export PARENT_DIR="${PARENT_DIR:-/opt/offline-env}"
    chmod +x "${SCRIPT_DIR}/prepare_offline_pkg.sh"

    "${SCRIPT_DIR}/prepare_offline_pkg.sh" "--${action_flag}" "${FORWARD_ARGS[@]}"
}

# ======================== Container pool =====================
# Scans pool slots 1..CONTAINER_POOL_SIZE to find a free slot.
# Sets globals: CONTAINER_NAME, CONTAINER_STATUS (new | stopped | running)
find_pool_container() {
    local base_name="$1"
    local idx
    for idx in $(seq 1 "$CONTAINER_POOL_SIZE"); do
        local cname="${base_name}-${idx}"

        # Slot not yet created — claim it
        if ! $CONTAINER_ENGINE ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$cname"; then
            CONTAINER_NAME="$cname"
            CONTAINER_STATUS="new"
            yellow_echo "Pool [${idx}/${CONTAINER_POOL_SIZE}]: '$cname' → will create"
            return
        fi

        # Slot exists but stopped — reuse (stopped = definitely not busy)
        if ! $CONTAINER_ENGINE ps --format '{{.Names}}' 2>/dev/null | grep -qx "$cname"; then
            CONTAINER_NAME="$cname"
            CONTAINER_STATUS="stopped"
            yellow_echo "Pool [${idx}/${CONTAINER_POOL_SIZE}]: '$cname' → stopped, will restart and reuse"
            return
        fi

        # Slot is running — check if a build is currently in progress
        if $CONTAINER_ENGINE exec "$cname" pgrep -f "prepare_offline_pkg" &>/dev/null 2>&1; then
            yellow_echo "Pool [${idx}/${CONTAINER_POOL_SIZE}]: '$cname' → busy (build in progress), trying next..."
            continue
        fi

        # Running and idle — reuse
        CONTAINER_NAME="$cname"
        CONTAINER_STATUS="running"
        yellow_echo "Pool [${idx}/${CONTAINER_POOL_SIZE}]: '$cname' → idle, will reuse"
        return
    done

    red_echo "ERROR: All ${CONTAINER_POOL_SIZE} containers in the pool are busy."
    red_echo "  Busy pool: ${base_name}-{1..${CONTAINER_POOL_SIZE}}"
    red_echo "  Options:"
    red_echo "    1. Wait for a running build to complete"
    red_echo "    2. Increase pool size: --container-pool-size=N (current: ${CONTAINER_POOL_SIZE})"
    exit 1
}

# ======================== Docker mode =========================
run_docker() {
    local action_flag="${1:-}"
    [[ -n "$action_flag" ]] || { red_echo "BUG: run_docker() called without action argument"; exit 1; }

    # ---- Select container from pool (sets CONTAINER_NAME + CONTAINER_STATUS) ----
    if [[ "$CONTAINER_NAME_EXPLICIT" == "true" ]]; then
        # User-specified name: detect status directly, no pool logic
        if ! $CONTAINER_ENGINE ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
            CONTAINER_STATUS="new"
        elif ! $CONTAINER_ENGINE ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
            CONTAINER_STATUS="stopped"
        else
            CONTAINER_STATUS="running"
        fi
    else
        find_pool_container "${CONTAINER_BASE_NAME}"
    fi

    # ---- Acquire build lock (prevents duplicate builds for same output target) ----
    acquire_build_lock

    cyan_echo "=== Running in DOCKER mode ==="
    [[ -n "$OS_KEY" ]] && cyan_echo "  OS:         ${OS_KEY}:${OS_VER}"
    cyan_echo "  Image:      $DOCKER_IMAGE"
    cyan_echo "  Container:  $CONTAINER_NAME  [${CONTAINER_STATUS}]"
    cyan_echo "  Engine:     $CONTAINER_ENGINE"
    cyan_echo "  Action:     $action_flag"
    cyan_echo "  Arch:       $ARCH"
    [[ -n "$PKG_LABEL" ]] && cyan_echo "  Label:      $PKG_LABEL"
    [[ -n "$BUILD_LOCK_FILE" ]] && cyan_echo "  Lock:       $BUILD_LOCK_FILE  (PID $$)"
    cyan_echo "  Output:     $OUTPUT_DIR"
    cyan_echo "  Cache:      ${CACHE_DIR:-/tmp/taos-packages}"
    [[ -n "$DOCKER_PLATFORM" ]] && cyan_echo "  Platform:   $DOCKER_PLATFORM"
    echo ""

    # Ensure output directory exists on host
    mkdir -p "$OUTPUT_DIR"

    # Host cache directory (declared early, used in both run_args and post-build output)
    local host_cache_dir="${CACHE_DIR:-/tmp/taos-packages}"
    mkdir -p "$host_cache_dir"

    # Build docker run arguments (used only when CONTAINER_STATUS=new)
    local run_args=()
    run_args+=(run -d --rm=false)
    run_args+=(--name "$CONTAINER_NAME")

    # Platform (for cross-arch)
    if [[ -n "$DOCKER_PLATFORM" ]]; then
        run_args+=(--platform "$DOCKER_PLATFORM")
    fi

    # Mount points:
    #   - output directory → /opt/offline-env (where prepare_offline_pkg.sh writes)
    #   - script directory → /build-scripts (read-only, contains prepare_offline_pkg.sh + install.sh)
    #   - cache directory  → /tmp/taos-packages (shared cache for Java/Arthas/Chromium/FFmpeg)
    run_args+=(-v "${OUTPUT_DIR}:/opt/offline-env")
    run_args+=(-v "${SCRIPT_DIR}:/build-scripts:ro")
    run_args+=(-v "${host_cache_dir}:/tmp/taos-packages")

    # Environment
    run_args+=(-e "PARENT_DIR=/opt/offline-env")

    # Extra user-supplied docker args
    if [[ -n "$DOCKER_EXTRA_ARGS" ]]; then
        # shellcheck disable=SC2206
        run_args+=($DOCKER_EXTRA_ARGS)
    fi

    # Image and initial command (keep container alive)
    run_args+=("$DOCKER_IMAGE" sleep infinity)

    # ---- Container lifecycle ----
    case "$CONTAINER_STATUS" in
        new)
            # Pull image if not available locally
            if ! $CONTAINER_ENGINE image inspect "$DOCKER_IMAGE" &>/dev/null; then
                yellow_echo "Image '$DOCKER_IMAGE' not found locally, pulling..."
                local pull_args=()
                [[ -n "$DOCKER_PLATFORM" ]] && pull_args+=(--platform "$DOCKER_PLATFORM")
                if ! $CONTAINER_ENGINE pull "${pull_args[@]}" "$DOCKER_IMAGE"; then
                    red_echo "ERROR: Failed to pull image: $DOCKER_IMAGE"
                    exit 1
                fi
                green_echo "Image pulled successfully"
            fi
            yellow_echo "Creating new container: $CONTAINER_NAME"
            $CONTAINER_ENGINE "${run_args[@]}"
            green_echo "Container '$CONTAINER_NAME' created and started"
            ;;
        stopped)
            yellow_echo "Starting stopped container: $CONTAINER_NAME"
            if ! $CONTAINER_ENGINE start "$CONTAINER_NAME" &>/dev/null; then
                red_echo "ERROR: Failed to start existing container: $CONTAINER_NAME"
                red_echo "  Remove it manually: $CONTAINER_ENGINE rm -f $CONTAINER_NAME"
                exit 1
            fi
            green_echo "Container '$CONTAINER_NAME' started"
            ;;
        running)
            green_echo "Reusing idle container: $CONTAINER_NAME"
            ;;
    esac

    # ---- Copy install.sh into output dir (prepare_offline_pkg.sh expects it) ----
    # This is done by summary() in prepare_offline_pkg.sh, but we pre-copy so
    # the test phase can find it too
    if [[ -f "${SCRIPT_DIR}/install.sh" ]]; then
        $CONTAINER_ENGINE exec "$CONTAINER_NAME" \
            cp /build-scripts/install.sh /opt/offline-env/ 2>/dev/null || true
    fi

    # ---- Execute build inside container ----
    yellow_echo "Executing prepare_offline_pkg.sh --${action_flag} inside container..."

    # Pass arguments as an array to docker exec to avoid any shell quoting issues.
    # Using "docker exec ... bash SCRIPT_PATH arg1 arg2 ..." is safer than
    # "docker exec ... bash -c 'SCRIPT arg1 arg2'" when args contain special chars.
    local exec_args=(/build-scripts/prepare_offline_pkg.sh "--${action_flag}" "${FORWARD_ARGS[@]}")

    if ! $CONTAINER_ENGINE exec "$CONTAINER_NAME" bash "${exec_args[@]}"; then
        red_echo "ERROR: Build failed inside container"
        # Don't clean up so user can debug
        red_echo "Container '$CONTAINER_NAME' is kept for debugging."
        red_echo "  Inspect:  $CONTAINER_ENGINE exec -it $CONTAINER_NAME bash"
        red_echo "  Logs:     $CONTAINER_ENGINE logs $CONTAINER_NAME"
        red_echo "  Cleanup:  $CONTAINER_ENGINE rm -f $CONTAINER_NAME"
        exit 1
    fi

    green_echo "Action '${action_flag}' completed successfully inside container"

    # Show clear path mapping for user
    echo ""
    cyan_echo "Path mapping (container → host):"
    cyan_echo "  /opt/offline-env    → ${OUTPUT_DIR}"
    cyan_echo "  /tmp/taos-packages  → ${host_cache_dir}"

    # Find the main package tar.gz (depth 2: OUTPUT_DIR/<pkg-dir>/<pkg>.tar.gz)
    # -maxdepth 2 avoids picking up component archives in java/, py_venv/ subdirs
    # xargs ls -t sorts by mtime desc so we always show the just-built package
    local tarball
    tarball=$(find "${OUTPUT_DIR}" -maxdepth 2 -name '*.tar.gz' -type f 2>/dev/null \
        | xargs ls -t 2>/dev/null | head -1)
    if [[ -n "$tarball" ]]; then
        green_echo ""
        green_echo "Offline package (host path): ${tarball}"
    fi
}

# ======================== Cleanup =============================
cleanup_container() {
    if [[ "$RUN_MODE" == "docker" && "$CLEANUP_CONTAINER" == "true" ]]; then
        yellow_echo "Cleaning up container: $CONTAINER_NAME"
        $CONTAINER_ENGINE rm -f "$CONTAINER_NAME" &>/dev/null || true
        green_echo "Container removed"
    fi
}

# ======================== Main ================================
main() {
    parse_args "$@"
    validate

    # Trap for cleanup
    if [[ "$RUN_MODE" == "docker" && "$CLEANUP_CONTAINER" == "true" ]]; then
        trap cleanup_container EXIT
    fi

    case "$ACTION" in
        build)
            if [[ "$RUN_MODE" == "native" ]]; then
                run_native "build"
            else
                run_docker "build"
            fi
            ;;
        test)
            if [[ "$RUN_MODE" == "native" ]]; then
                run_native "test"
            else
                run_docker "test"
            fi
            ;;
        build-and-test)
            if [[ "$RUN_MODE" == "native" ]]; then
                run_native "build"
                run_native "test"
            else
                run_docker "build"
                # Pool logic will find the same idle container for the test phase
                run_docker "test"
            fi
            ;;
    esac

    green_echo ""
    green_echo "============================================"
    green_echo "  Build completed successfully!"
    green_echo "  Output directory: ${OUTPUT_DIR}"
    # Show the final tar.gz path
    local tarball
    tarball=$(find "${OUTPUT_DIR}" -maxdepth 2 -name '*.tar.gz' -type f 2>/dev/null \
        | xargs ls -t 2>/dev/null | head -1)
    if [[ -n "$tarball" ]]; then
        green_echo "  Package: ${tarball}"
        local pkg_size
        pkg_size=$(du -sh "$tarball" 2>/dev/null | awk '{print $1}')
        [[ -n "$pkg_size" ]] && green_echo "  Size:    ${pkg_size}"
    fi
    green_echo "============================================"
}

main "$@"
