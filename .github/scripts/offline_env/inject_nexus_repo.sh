#!/bin/bash
# =============================================================================
# inject_nexus_repo.sh — Inject a Nexus mirror repo into the current OS
#
# Adds a nexus-<os>.repo (RPM) or nexus-<os>.list + apt.conf.d ssl snippet
# (DEB) so the system can pull packages from a private Nexus instance.
#
# Default behaviour (safe / additive):
#   The existing OS repo files are LEFT INTACT.  Nexus is added alongside
#   them; the package manager will use whichever source responds first.
#
# With --disable-originals (destructive / offline mode):
#   Existing repo files are renamed to *.disabled so the Nexus mirror
#   becomes the sole package source.  The Nexus URL is validated for
#   reachability before any files are renamed.
#   Original repo files are preserved with the .disabled suffix and can
#   be restored manually by renaming them back.
#
# Run this script directly on the target machine.  All parameters have
# defaults or are auto-detected, so a plain invocation with no args works
# on any supported OS with the default Nexus instance:
#   ./inject_nexus_repo.sh
#
# OS / version are auto-detected from /etc/os-release.
# Supported OS IDs: ubuntu, debian, centos, kylin, openeuler
#
# Verified Nexus repo mappings (https://nexus.tdengine.net):
#   OS        Nexus repo    Upstream mirror
#   ubuntu    ubuntu        http://cn.archive.ubuntu.com/ubuntu
#   debian    debian{N}     http://deb.debian.org/debian
#   centos    centos        http://mirrors.aliyun.com/centos
#   kylin     kylinv10      http://update.cs2c.com.cn:8080
#   openeuler openeuler     https://repo.openeuler.org
#
# Usage:
#   inject_nexus_repo.sh [OPTIONS]
#
# Options:
#   --nexus-url=<url>          Nexus base URL
#                              Default: https://nexus.tdengine.net
#   --os-key=<id>              OS family: ubuntu|debian|centos|kylin|openeuler
#                              Default: auto-detect from /etc/os-release
#   --os-ver=<ver>             OS version string (e.g. 22.04, v10-sp3-2403)
#                              Default: auto-detect from /etc/os-release
#   --disable-originals        Rename existing OS repo files to *.disabled and
#                              (RPM) redirect yum reposdir to a nexus-only dir.
#                              Default: off (original files are not touched)
#   -h|--help                  Show this help and exit
# =============================================================================

set -euo pipefail

# ======================== Color helpers ========================
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'; RESET='\033[0m'
red_echo()    { echo -e "${RED}$*${RESET}" >&2; }
green_echo()  { echo -e "${GREEN}$*${RESET}"; }
yellow_echo() { echo -e "${YELLOW}$*${RESET}"; }
cyan_echo()   { echo -e "${CYAN}$*${RESET}"; }

# ======================== Defaults ============================
NEXUS_URL="https://nexus.tdengine.net"
OS_KEY=""              # auto-detect from /etc/os-release if empty
OS_VER=""              # auto-detect from /etc/os-release if empty
DISABLE_ORIGINALS=false  # rename existing repo files (opt-in)

# ======================== Parse args ==========================
show_usage() {
    grep '^# ' "$0" | sed -n '/^# Usage:/,/^# =====/p' | sed 's/^# \?//'
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        --nexus-url=*)       NEXUS_URL="${arg#*=}" ;;
        --os-key=*)          OS_KEY="${arg#*=}" ;;
        --os-ver=*)          OS_VER="${arg#*=}" ;;
        --disable-originals) DISABLE_ORIGINALS=true ;;
        -h|--help)           show_usage ;;
        *) red_echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

# ======================== Validate user-supplied OS_KEY =======
# Validate early so a typo fails loudly before any OS changes are made.
if [[ -n "$OS_KEY" ]]; then
    case "$OS_KEY" in
        ubuntu|debian|centos|kylin|openeuler) ;;
        *)
            red_echo "ERROR: Unsupported --os-key '${OS_KEY}' — must be one of: ubuntu debian centos kylin openeuler"
            exit 1
            ;;
    esac
fi

# ======================== OS auto-detection ===================
# Reads /etc/os-release from the host (native mode) or from the target
# container (container mode) and normalises the values into OS_KEY / OS_VER.
#
# Normalisation rules per OS family:
#   ubuntu   : VERSION_ID=22.04            → os_ver=22.04
#   debian   : VERSION_ID=12               → os_ver=12
#   centos   : VERSION_ID=7                → os_ver=7
#   openeuler: VERSION_ID=22.03
#              PRETTY_NAME="openEuler 22.03 (LTS-SP1)"
#              → os_ver=22.03-lts-sp1
#   kylin    : VERSION="V10 (Halberd)"  → os_ver=v10-sp3-2403  (codename-based mapping)

_read_os_release() {
    cat /etc/os-release 2>/dev/null || true
}

# Extract a field value from os-release content (strips surrounding quotes).
_field() {
    local content="$1" field="$2"
    printf '%s' "$content" \
        | grep -i "^${field}=" | head -1 \
        | cut -d= -f2- | tr -d '"' | tr -d "'"
}

detect_os() {
    local content
    content="$(_read_os_release)"

    if [[ -z "$content" ]]; then
        red_echo "ERROR: Could not read /etc/os-release"
        exit 1
    fi

    local id version_id pretty_name
    id=$(_field "$content" "ID" | tr '[:upper:]' '[:lower:]')
    version_id=$(_field "$content" "VERSION_ID")
    pretty_name=$(_field "$content" "PRETTY_NAME")

    # ---- Resolve OS_KEY ----
    if [[ -z "$OS_KEY" ]]; then
        case "$id" in
            ubuntu)    OS_KEY="ubuntu" ;;
            debian)    OS_KEY="debian" ;;
            centos)    OS_KEY="centos" ;;
            kylin)     OS_KEY="kylin" ;;
            openeuler) OS_KEY="openeuler" ;;
            *)
                red_echo "ERROR: Unsupported OS ID '${id}' — supported: ubuntu debian centos kylin openeuler"
                exit 1
                ;;
        esac
        yellow_echo "Auto-detected OS key : ${OS_KEY}"
    fi

    # ---- Resolve OS_VER ----
    if [[ -z "$OS_VER" ]]; then
        case "$OS_KEY" in
            ubuntu|debian|centos)
                OS_VER="$version_id"
                ;;
            openeuler)
                # Parse "(LTS-SP1)" / "(LTS)" from PRETTY_NAME.
                # e.g. "openEuler 24.03 (LTS-SP2)" → "24.03-lts-sp2"
                local oe_suffix
                oe_suffix=$(printf '%s' "$pretty_name" \
                    | grep -oP '\(LTS[^)]*\)' \
                    | tr -d '()' \
                    | tr '[:upper:]' '[:lower:]' \
                    | sed 's/ /-/g' || true)
                if [[ -n "$oe_suffix" ]]; then
                    OS_VER="${version_id}-${oe_suffix}"
                else
                    OS_VER="${version_id}"
                    yellow_echo "WARNING: LTS/SP suffix not found in '${pretty_name}'; using VERSION_ID only"
                fi
                ;;
            kylin)
                # Kylin does NOT embed SP numbers in os-release; it uses release code names.
                # VERSION="V10 (Codename)" — extract codename and map to known SP version.
                # Known mappings (from actual Kylin release images):
                #   Tercel  → v10-sp1
                #   Sword   → v10-sp2
                #   Lance   → v10-sp3
                #   Halberd → v10-sp3-2403
                local codename
                codename=$(printf '%s' "$content" \
                    | grep '^VERSION=' \
                    | grep -oP '(?<=\()\w+(?=\))' \
                    | head -1 || true)

                case "$codename" in
                    Tercel)  OS_VER="v10-sp1" ;;
                    Sword)   OS_VER="v10-sp2" ;;
                    Lance)   OS_VER="v10-sp3" ;;
                    Halberd) OS_VER="v10-sp3-2403" ;;
                    "")
                        red_echo "ERROR: Cannot extract codename from VERSION field; content:"
                        red_echo "$(printf '%s' "$content" | grep '^VERSION=')"
                        exit 1
                        ;;
                    *)
                        red_echo "ERROR: Unknown Kylin codename '${codename}'; supported: Tercel Sword Lance Halberd"
                        exit 1
                        ;;
                esac
                ;;
        esac

        if [[ -z "$OS_VER" ]]; then
            red_echo "ERROR: Could not detect OS version for '${OS_KEY}'"
            exit 1
        fi
        yellow_echo "Auto-detected OS ver  : ${OS_VER}"
    fi
}

# ======================== Write helpers =======================
_write_file() {
    local dest="$1" content="$2"
    printf '%s' "$content" > "$dest"
}

# Validate that the Nexus base URL is reachable before making destructive changes.
# Uses curl with a short timeout; skips check if curl is not available.
_check_nexus_reachability() {
    local url="$1"
    if ! command -v curl &>/dev/null; then
        yellow_echo "WARNING: curl not found — skipping Nexus reachability check"
        return 0
    fi
    yellow_echo "Checking Nexus reachability: ${url}"
    local http_code
    http_code=$(curl -sko /dev/null -w '%{http_code}' \
        --connect-timeout 5 --max-time 10 \
        --insecure "${url}" 2>/dev/null || true)
    # Accept any HTTP response (including 4xx/5xx) — a response means the host is up.
    # Only treat connection-level failures (http_code empty or 000) as unreachable.
    if [[ -z "$http_code" || "$http_code" == "000" ]]; then
        red_echo "ERROR: Nexus URL '${url}' is unreachable (connection failed)."
        red_echo "       Refusing to disable original repos to avoid leaving the system without package sources."
        red_echo "       Fix the URL or omit --disable-originals if Nexus is not accessible."
        exit 1
    fi
    yellow_echo "Nexus reachable (HTTP ${http_code})"
}

# Disable original OS repo files so yum/apt uses ONLY the Nexus repo.
# RPM: renames *.repo  (excluding nexus-*.repo) → *.repo.disabled
# DEB: renames sources.list and sources.list.d/*.list (excluding nexus-*.list)
_disable_original_repos() {
    local pkg_family="$1"
    if [[ "$pkg_family" == "rpm" ]]; then
        local f
        for f in /etc/yum.repos.d/*.repo; do
            [[ "$(basename "$f")" == nexus-* ]] && continue
            [[ -f "$f" ]] || continue
            mv "$f" "${f}.disabled"
            yellow_echo "Disabled: $f"
        done
    else
        local f
        # disable /etc/apt/sources.list
        if [[ -f /etc/apt/sources.list ]]; then
            mv /etc/apt/sources.list /etc/apt/sources.list.disabled
            yellow_echo "Disabled: /etc/apt/sources.list"
        fi
        # disable sources.list.d/*.list (excluding nexus-*.list)
        for f in /etc/apt/sources.list.d/*.list; do
            [[ "$(basename "$f")" == nexus-* ]] && continue
            [[ -f "$f" ]] || continue
            mv "$f" "${f}.disabled"
            yellow_echo "Disabled: $f"
        done
    fi
}

# ======================== Main injection ======================
inject() {
    local nexus_base="${NEXUS_URL%/}"

    cyan_echo "=== Nexus repo injection ==="
    cyan_echo "  Nexus URL : ${nexus_base}"
    cyan_echo "  OS        : ${OS_KEY}:${OS_VER}"

    local nexus_repo="" path_prefix="" pkg_family="rpm"
    local subrepos=()

    case "${OS_KEY}" in
        openeuler)
            nexus_repo="openeuler"
            local oe_ver; oe_ver=$(printf '%s' "$OS_VER" | tr '[:lower:]' '[:upper:]')
            path_prefix="openEuler-${oe_ver}"
            subrepos=("OS" "everything" "EPOL/main" "update")
            ;;
        centos)
            nexus_repo="centos"
            path_prefix="centos/${OS_VER}"
            subrepos=("os" "updates" "extras")
            ;;
        kylin)
            nexus_repo="kylinv10"
            local kylin_ver
            case "$OS_VER" in
                v10-sp1) kylin_ver="V10SP1.1" ;;
                *)       kylin_ver=$(printf '%s' "$OS_VER" | sed 's/v10-sp/V10SP/') ;;
            esac
            path_prefix="NS/V10/${kylin_ver}/os/adv/lic"
            subrepos=("base" "updates")
            ;;
        ubuntu)
            pkg_family="deb"
            nexus_repo="ubuntu"
            ;;
        debian)
            pkg_family="deb"
            local debian_major="${OS_VER%%.*}"
            nexus_repo="debian${debian_major}"
            ;;
        *)
            # Should never be reached after early validation, but guard anyway.
            red_echo "ERROR: No Nexus mapping for OS_KEY '${OS_KEY}'"
            exit 1
            ;;
    esac

    # ---- RPM: write .repo file ----
    if [[ "$pkg_family" == "rpm" ]]; then
        local repo_content="" subrepo
        for subrepo in "${subrepos[@]}"; do
            local section_id="nexus-${subrepo//\//-}"
            repo_content+="[${section_id}]
name=Nexus ${OS_KEY} ${subrepo}
baseurl=${nexus_base}/repository/${nexus_repo}/${path_prefix}/${subrepo}/\$basearch/
enabled=1
gpgcheck=0
sslverify=0
metadata_expire=1h

"
        done

        if [[ "$DISABLE_ORIGINALS" == true ]]; then
            # Validate Nexus is reachable before disabling originals — if the URL is
            # wrong the system must not be left without any working package source.
            _check_nexus_reachability "${nexus_base}"
            # Write nexus repo to the standard directory alongside existing repos,
            # then rename originals so yum ignores them (.repo suffix required by yum).
            # NOTE: package updates (e.g. centos-release) may restore original .repo
            # files; re-run this script or exclude such packages with
            # `yum update --exclude=centos-release` if that is a concern.
            local dest="/etc/yum.repos.d/nexus-${OS_KEY}.repo"
            yellow_echo "Writing: ${dest}  (${#subrepos[@]} sections)"
            _write_file "$dest" "$repo_content"
            _disable_original_repos "rpm"
            green_echo "Done — Nexus yum repo active; original repos disabled"
        else
            # Safe mode: write into the standard reposdir; existing repos are kept.
            local dest="/etc/yum.repos.d/nexus-${OS_KEY}.repo"
            yellow_echo "Writing: ${dest}  (${#subrepos[@]} sections)"
            _write_file "$dest" "$repo_content"
            green_echo "Done — Nexus yum repo added; original repos kept"
        fi

    # ---- DEB: write .list file ----
    else
        local os_rel_content; os_rel_content="$(_read_os_release)"
        local codename
        codename=$(_field "$os_rel_content" "VERSION_CODENAME")
        [[ -z "$codename" ]] && codename=$(_field "$os_rel_content" "UBUNTU_CODENAME")
        if [[ -z "$codename" ]]; then
            red_echo "ERROR: Cannot detect release codename from /etc/os-release — cannot configure apt source"
            exit 1
        fi

        local components="main restricted universe multiverse"
        [[ "$OS_KEY" == "debian" ]] && components="main contrib non-free non-free-firmware"
        local security_repo="${nexus_repo}-security"
        local list_content="deb ${nexus_base}/repository/${nexus_repo} ${codename} ${components}
deb ${nexus_base}/repository/${nexus_repo} ${codename}-updates ${components}
deb ${nexus_base}/repository/${security_repo} ${codename}-security ${components}
"
        local dest="/etc/apt/sources.list.d/nexus-${OS_KEY}.list"
        yellow_echo "Writing: ${dest}  (codename=${codename})"
        _write_file "$dest" "$list_content"

        # Disable TLS peer verification for the Nexus host — needed when Nexus uses
        # a self-signed / internal CA that the OS doesn't have in its trust store.
        # [trusted=yes] in sources.list only skips GPG, NOT the TLS handshake.
        local nexus_host; nexus_host=$(printf '%s' "$nexus_base" | sed 's|https\?://||;s|/.*||')
        local ssl_conf="Acquire::https::${nexus_host}::Verify-Peer \"false\";
Acquire::https::${nexus_host}::Verify-Host \"false\";
"
        local ssl_dest="/etc/apt/apt.conf.d/99nexus-ssl.conf"
        yellow_echo "Writing: ${ssl_dest}  (host=${nexus_host})"
        _write_file "$ssl_dest" "$ssl_conf"
        if [[ "$DISABLE_ORIGINALS" == true ]]; then
            _check_nexus_reachability "${nexus_base}"
            _disable_original_repos "deb"
            green_echo "Done — Nexus apt source active; original sources disabled"
        else
            green_echo "Done — Nexus apt source added; original sources kept"
        fi
    fi
}

# ======================== Entry point ========================
# When called by build_offline_pkg.sh with --nexus-url="" (Nexus disabled),
# exit silently without doing anything.
[[ -z "$NEXUS_URL" ]] && exit 0

detect_os
inject
