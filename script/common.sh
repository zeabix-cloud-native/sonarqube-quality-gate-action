#!/usr/bin/env bash

# Begin Standard 'imports'
set -e
set -o pipefail

gray="\\e[37m"
blue="\\e[36m"
red="\\e[31m"
yellow="\\e[33m"
green="\\e[32m"
reset="\\e[0m"

info() { echo -e "${blue}INFO: $*${reset}"; }
error() { echo -e "${red}ERROR: $*${reset}"; }
debug() {
    if [[ "${DEBUG}" == "true" ]]; then
        echo -e "${gray}DEBUG: $*${reset}";
    fi
}

success() { echo -e "${green}✔ $*${reset}"; }
warn() { echo -e "${yellow}✖ $*${reset}"; exit 1; }
fail() { echo -e "${red}✖ $*${reset}"; exit 1; }

# support old GH Actions runners
set_output () {
  if [[ -n "${GITHUB_OUTPUT}" ]]; then
    echo "${1}=${2}" >> "${GITHUB_OUTPUT}"
  else
    echo "::set-output name=${1}::${2}"
  fi
}

# Handle multiline outputs for GitHub Actions
set_multiline_output () {
  local name="$1"
  local value="$2"
  
  if [[ -n "${GITHUB_OUTPUT}" ]]; then
    # Use heredoc-like syntax for multiline outputs
    local delimiter="EOF_${name}_$(date +%s)"
    echo "${name}<<${delimiter}" >> "${GITHUB_OUTPUT}"
    echo "${value}" >> "${GITHUB_OUTPUT}"
    echo "${delimiter}" >> "${GITHUB_OUTPUT}"
  else
    # For older runners, escape newlines
    local escaped_value
    escaped_value=$(printf '%s' "${value}" | jq -Rs .)
    echo "::set-output name=${name}::${escaped_value}"
  fi
}

## Enable debug mode.
enable_debug() {
  if [[ "${DEBUG}" == "true" ]]; then
    info "Enabling debug mode."
    set -x
  fi
}

# Execute a command, saving its output and exit status code, and echoing its output upon completion.
# Globals set:
#   status: Exit status of the command that was executed.
#   output: Output generated from the command.
#
run() {
  echo "$@"
  set +e
  output=$("$@" 2>&1)
  status=$?
  set -e
  echo "${output}"
}

# End standard 'imports'

