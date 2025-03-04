#!/bin/bash

###############################################
# Environment Initialization
# Detects execution context and sets up outputs
###############################################

init_environment() {
    # Check if running in GitHub Actions
    if [[ -z "${GITHUB_ACTIONS}" ]]; then
        # Set default output file for local execution
        export GITHUB_OUTPUT="${GITHUB_OUTPUT:-runner-output.txt}"
        echo "##[debug] Local execution mode activated" >&2
        echo "INFO: Output file - ${PWD}/${GITHUB_OUTPUT}" >&2
    fi
}

###############################################
# Unified Output Handler
# Parameters:
#   $1: Content to output (JSON string)
#   $2: Output variable name (optional)
###############################################

handle_output() {
    local content="$1"
    local output_var="${2:-SELECTED_RUNNERS}"

    # Write to GitHub output or local file
    if [[ -f "${GITHUB_OUTPUT}" ]]; then
        {
            echo "${output_var}=${content}"
        } >> "${GITHUB_OUTPUT}"
    else
        {
            echo "${output_var}=${content}"
        } > "${GITHUB_OUTPUT}"
    fi

    # Local execution debug info
    if [[ "${GITHUB_ACTIONS}" != "true" ]]; then
        echo -e "\n=== Local Execution Result ==="
        echo "Output file: ${PWD}/${GITHUB_OUTPUT}"
        echo "Content preview:"
        echo "${content}" | jq .
    fi
}