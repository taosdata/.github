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
    ["openeuler:22.03-lts-sp3"]="openeuler/openeuler:22.03-lts-sp3|x64,arm64"
    ["openeuler:22.03-lts-sp4"]="openeuler/openeuler:22.03-lts-sp4|x64,arm64"
    ["openeuler:24.03-lts-sp2"]="openeuler/openeuler:24.03-lts-sp2|x64,arm64"
)

# ======================== Defaults ============================
# -- Orchestrator params --
RUN_MODE="native"                           # native | docker
OS_KEY=""                                   # e.g. ubuntu, centos, kylin, openeuler
OS_VER=""                                   # e.g. 22.04, 7, v10-sp3-2403, 24.03-lts-sp2
ARCH=""                                     # x64 | arm64 (auto-detect if empty)
DOCKER_IMAGE=""                             # resolved from OS_KEY:OS_VER, or set directly
CONTAINER_NAME=""                           # auto-generated from os+ver+arch
CONTAINER_ENGINE="docker"                   # docker | podman
OUTPUT_DIR=""                               # host dir for output (default: ./offline_pkgs)
CLEANUP_CONTAINER="true"                    # remove container after build
DOCKER_PLATFORM=""                          # e.g. linux/arm64 (for cross-arch builds)
DOCKER_EXTRA_ARGS=""                        # extra args passed to docker run

# -- Action --
ACTION="build"                              # build | test | build-and-test

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

    # Auto-generate container name if not explicitly set
    if [[ -z "$CONTAINER_NAME" ]]; then
        local safe_ver="${OS_VER//[.:]/-}"
        CONTAINER_NAME="offline-pkg-${OS_KEY}-${safe_ver}-${ARCH}-$$"
    fi

    green_echo "Resolved OS target:"
    green_echo "  Key:        ${key}"
    green_echo "  Image:      ${DOCKER_IMAGE}"
    green_echo "  Arch:       ${ARCH}"
    green_echo "  Container:  ${CONTAINER_NAME}"
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
  --os-ver=<version>            OS version: 22.04, 7, v10-sp3-2403, 24.03-lts-sp2
  --arch=<x64|arm64>            Target architecture (default: auto-detect from host)
  --list-os                     List all supported OS targets and exit

ORCHESTRATOR OPTIONS:
  --mode=<native|docker>        Run mode (default: native)
  --action=<action>             build | test | build-and-test (default: build)
  --container-name=<name>       Custom container name (default: auto-generated)
  --container-engine=<cmd>      Container runtime: docker or podman (default: docker)
  --output-dir=<path>           Host directory for output artifacts (default: ./offline_pkgs)
  --cleanup-container=<bool>    Remove container after build (default: true)
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
  --idmp-ver=<ver>              IDMP version/tag for requirements download (from TDasset repo)
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
                ;;
            --container-engine=*)
                CONTAINER_ENGINE="${1#*=}"
                ;;
            --output-dir=*)
                OUTPUT_DIR="${1#*=}"
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
            if [[ -z "$CONTAINER_NAME" ]]; then
                local img_tag="${DOCKER_IMAGE//[:\/]/-}"
                CONTAINER_NAME="offline-pkg-${img_tag}-${ARCH}-$$"
            fi
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

# ======================== Native mode =========================
run_native() {
    local action_flag="$1"
    cyan_echo "=== Running in NATIVE mode (action=$action_flag) ==="

    export PARENT_DIR="${PARENT_DIR:-/opt/offline-env}"
    chmod +x "${SCRIPT_DIR}/prepare_offline_pkg.sh"

    "${SCRIPT_DIR}/prepare_offline_pkg.sh" "--${action_flag}" "${FORWARD_ARGS[@]}"
}

# ======================== Docker mode =========================
run_docker() {
    local action_flag="$1"
    cyan_echo "=== Running in DOCKER mode ==="
    [[ -n "$OS_KEY" ]] && cyan_echo "  OS:         ${OS_KEY}:${OS_VER}"
    cyan_echo "  Image:      $DOCKER_IMAGE"
    cyan_echo "  Container:  $CONTAINER_NAME"
    cyan_echo "  Engine:     $CONTAINER_ENGINE"
    cyan_echo "  Action:     $action_flag"
    cyan_echo "  Arch:       $ARCH"
    cyan_echo "  Output:     $OUTPUT_DIR"
    [[ -n "$DOCKER_PLATFORM" ]] && cyan_echo "  Platform:   $DOCKER_PLATFORM"
    echo ""

    # Ensure output directory exists on host
    mkdir -p "$OUTPUT_DIR"

    # Build docker run arguments
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
    run_args+=(-v "${OUTPUT_DIR}:/opt/offline-env")
    run_args+=(-v "${SCRIPT_DIR}:/build-scripts:ro")

    # Environment
    run_args+=(-e "PARENT_DIR=/opt/offline-env")

    # Extra user-supplied docker args
    if [[ -n "$DOCKER_EXTRA_ARGS" ]]; then
        # shellcheck disable=SC2206
        run_args+=($DOCKER_EXTRA_ARGS)
    fi

    # Image and initial command (keep container alive)
    run_args+=("$DOCKER_IMAGE" sleep infinity)

    # ---- Pull image if not available locally ----
    if ! $CONTAINER_ENGINE image inspect "$DOCKER_IMAGE" &>/dev/null; then
        yellow_echo "Image '$DOCKER_IMAGE' not found locally, pulling..."
        local pull_args=()
        if [[ -n "$DOCKER_PLATFORM" ]]; then
            pull_args+=(--platform "$DOCKER_PLATFORM")
        fi
        if ! $CONTAINER_ENGINE pull "${pull_args[@]}" "$DOCKER_IMAGE"; then
            red_echo "ERROR: Failed to pull image: $DOCKER_IMAGE"
            exit 1
        fi
        green_echo "Image pulled successfully"
    fi

    # ---- Remove stale container with same name ----
    if $CONTAINER_ENGINE ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
        yellow_echo "Removing existing container: $CONTAINER_NAME"
        $CONTAINER_ENGINE rm -f "$CONTAINER_NAME" &>/dev/null || true
    fi

    # ---- Start container ----
    yellow_echo "Starting container..."
    $CONTAINER_ENGINE "${run_args[@]}"
    green_echo "Container '$CONTAINER_NAME' started"

    # ---- Copy install.sh into output dir (prepare_offline_pkg.sh expects it) ----
    # This is done by summary() in prepare_offline_pkg.sh, but we pre-copy so
    # the test phase can find it too
    if [[ -f "${SCRIPT_DIR}/install.sh" ]]; then
        $CONTAINER_ENGINE exec "$CONTAINER_NAME" \
            cp /build-scripts/install.sh /opt/offline-env/ 2>/dev/null || true
    fi

    # ---- Execute build inside container ----
    yellow_echo "Executing prepare_offline_pkg.sh --${action_flag} inside container..."

    local exec_cmd
    exec_cmd="chmod +x /build-scripts/prepare_offline_pkg.sh && "
    exec_cmd+="/build-scripts/prepare_offline_pkg.sh --${action_flag}"

    # Append forwarded arguments
    for arg in "${FORWARD_ARGS[@]}"; do
        # Safely quote arguments containing spaces
        exec_cmd+=" $(printf '%q' "$arg")"
    done

    if ! $CONTAINER_ENGINE exec "$CONTAINER_NAME" bash -c "$exec_cmd"; then
        red_echo "ERROR: Build failed inside container"
        # Don't clean up so user can debug
        red_echo "Container '$CONTAINER_NAME' is kept for debugging."
        red_echo "  Inspect:  $CONTAINER_ENGINE exec -it $CONTAINER_NAME bash"
        red_echo "  Logs:     $CONTAINER_ENGINE logs $CONTAINER_NAME"
        red_echo "  Cleanup:  $CONTAINER_ENGINE rm -f $CONTAINER_NAME"
        exit 1
    fi

    green_echo "Action '${action_flag}' completed successfully inside container"
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
                # For test, we need a fresh container from the same image
                # but the output dir already has the built package
                local build_container="$CONTAINER_NAME"
                cleanup_container

                # Reset cleanup trap since we manually cleaned
                trap - EXIT

                CONTAINER_NAME="${build_container}-test"
                if [[ "$CLEANUP_CONTAINER" == "true" ]]; then
                    trap cleanup_container EXIT
                fi

                run_docker "test"
            fi
            ;;
    esac

    green_echo ""
    green_echo "============================================"
    green_echo "  Build completed successfully!"
    green_echo "  Output: ${OUTPUT_DIR}"
    green_echo "============================================"
}

main "$@"
