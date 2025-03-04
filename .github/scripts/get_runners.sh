#!/bin/bash
set -eo pipefail


# ###############################################
# # Import Common Utilities
# ###############################################

# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# source "${SCRIPT_DIR}/libs/common.sh"

# Global Defaults
DEFAULT_SCOPE="org"
DEFAULT_TARGET="taosdata"
DEFAULT_MATCH_MODE="all"
DEFAULT_EXCLUDE_LABELS=""

################################################################
# Main Execution Flow
# Parameters:
#   $1: Include labels (comma-separated) - REQUIRED
#   $2: Required runner count - REQUIRED
#   $3: Exclude labels (comma-separated) - OPTIONAL
#   $4: Match mode (any/all) - OPTIONAL
#   $5: Scope (org/repo) - OPTIONAL
#   $6: Target name (org or repo slug) - OPTIONAL
################################################################

# Validate mandatory parameters
if [[ $# -lt 2 ]]; then
  echo "::error::Missing required parameters"
  echo "Usage: $0 <include_labels> <required_count> [exclude_labels] [match_mode] [scope] [target]"
  exit 1
fi

# Parameter parsing with defaults
include_labels="$1"
required_count="$2"
exclude_labels="${3:-$DEFAULT_EXCLUDE_LABELS}"
match_mode="${4:-$DEFAULT_MATCH_MODE}"
scope="${5:-$DEFAULT_SCOPE}"
target="${6:-$DEFAULT_TARGET}"

# Validate GH_TOKEN presence
if [[ -z "${GH_TOKEN}" ]]; then
  echo "::error::GH_TOKEN environment variable not set"
  exit 1
fi

# Convert labels to JSON arrays
include_json=$(jq -cn --arg labels "$include_labels" '$labels | split(",")')
exclude_json=$(jq -cn --arg labels "$exclude_labels" '$labels | split(",")')

# Validate scope and target format
if [[ "$scope" == "repo" && "$target" != */* ]]; then
  echo "::error::Repo target must be in 'owner/repo' format"
  exit 1
elif [[ "$scope" != "org" && "$scope" != "repo" ]]; then
  echo "::error::Invalid scope: must be 'org' or 'repo'"
  exit 1
fi

# Construct API URL
if [[ "$scope" == "org" ]]; then
  api_url="https://api.github.com/orgs/${target}/actions/runners"
else
  api_url="https://api.github.com/repos/${target}/actions/runners"
fi

# API call with retry logic
max_retries=3
for ((i=1; i<=max_retries; i++)); do
  response=$(curl -sfS \
    -H "Authorization: token ${GH_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "$api_url" 2>/dev/null) && break || sleep $((i*2))

  if [[ $i -eq max_retries ]]; then
    echo "::error::Failed to fetch runners after ${max_retries} attempts"
    exit 1
  fi
done

# JQ filter construction
jq_filter=$(cat <<FILTER
.runners[]
| select(.status == "online")
| select(
    (if "$match_mode" == "all" then
      .labels | map(.name) | contains($include_json)
    else
      .labels | map(.name) | any(IN($include_json[]))
    end)
    and
    (.labels | map(.name) | any(IN($exclude_json[])) | not)
  )
| .name
FILTER
)

# Process and validate results
selected_runners=$(echo "$response" | jq -r "$jq_filter" | head -n "$required_count")
selected_count=$(echo "$selected_runners" | wc -w)

if [[ $selected_count -lt $required_count ]]; then
  echo "::error::Insufficient runners: found ${selected_count}, need ${required_count}"
  exit 1
fi

# Format output
output_json=$(echo "$selected_runners" | jq -R -s -c 'split("\n") | map(select(. != ""))')

echo "SELECTED_RUNNERS=${output_json}"
echo "SELECTED_RUNNERS=${output_json}" >> $GITHUB_OUTPUT
echo "GITHUB_OUTPUT in action=$GITHUB_OUTPUT"

# # Initialize environment
# init_environment

# handle_output "${output_json}" "CUSTOM_OUTPUT_VAR"