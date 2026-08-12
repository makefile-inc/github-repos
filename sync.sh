#!/usr/bin/env bash

# Copyright 2026
# license that can be found in the LICENSE file.

set -Eeuo pipefail

function echo_err() {
	echo -e "\033[0;31m${1:-}\033[0m" >&2
}

function echo_info() {
	echo -e "\033[0;32m${1:-}\033[0m" >&2
}

function echo_warn() {
	echo -e "\033[0;33m${1:-}\033[0m" >&2
}

function exit_with_err() {
	local exit_code="${2:-}"
	
  if [ -z "$exit_code" ]; then
		exit_code="1"
	fi
	
  if [ "$exit_code" -eq 0 ]; then
		exit_code="1"
	fi
	
  echo_err "${1:-Error}"
	exit "$exit_code"
}

if [ -z "${WORKING_DIR:-}" ]; then
  WORKING_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
else
  echo_info "Use passed '$WORKING_DIR' WORKING_DIR"
  if ! cd "$WORKING_DIR"; then
    exit_with_err "Cannot cd to '$WORKING_DIR'"
  fi
fi

CONST_TOKEN_SEPARATOR="||"

BIN_DIR="${WORKING_DIR}/.bin"
TOFU_BIN="${BIN_DIR}/tofu"
TOFU_RC="${WORKING_DIR}/.tofurc"
TOFU_PLUGINS_DIR="${BIN_DIR}"

OS_NAME=""
FIND_BIN="find"

TMPDIR="${WORKING_DIR}/.tmp"
ORGS_DIR="${WORKING_DIR}/organizations"
PLANS_DIR="${TMPDIR}/plans"

if [ -z "${TOKENS_FILE:-}" ]; then
  TOKENS_FILE=""
fi

declare -A ORG_TO_TOKEN

# shellcheck disable=SC2329
function cleanup_after_exit() {
  unset -v GITHUB_TOKEN
  unset -v ORG_TO_TOKEN
  rm -rfv "$PLANS_DIR"
}

if [ -z "${ORG_TO_SYNC:-}" ]; then
  ORG_TO_SYNC=""
fi

if [ -z "${REPO_TO_SYNC:-}" ]; then
  REPO_TO_SYNC=""
fi

if [ -z "${SHOW_SENSITIVE:-}" ]; then
  SHOW_SENSITIVE=""
fi

function ask_user() {
  local prompt="$1"
  local answer=""

  # shellcheck disable=SC2162
  read -p "${prompt} [y/n]: " answer

  if [[ "$answer" == "y" ]]; then
    return 0
  fi

  return 1
}

function usage() {
    local exit_code="${1-}"
    if [ -z "$exit_code" ]; then
      exit_code="0"
    fi
    echo "Usage: $0 [OPTIONS]"
    echo "For MacOS gfind should installed!"
    echo "Options:"
    echo "  -t|--gh-tokens-file PATH - Path to github token file"
    echo "                             Also can be passed via env TOKENS_FILE"
    echo "                             Token file should be dot env file"
    echo "                             with variables with next rules:"
    echo "                             - variables started with GITHUB_TOKEN_FILE_"
    echo "                               should contains string 'org_name${CONST_TOKEN_SEPARATOR}path'"
    echo "                               from path script will read github token (with sudo if need)"
    echo "                               for organization with org_name"
    echo "                             - variables started with GITHUB_TOKEN_STRING_"
    echo "                               should contains string 'org_name${CONST_TOKEN_SEPARATOR}token_str'"
    echo "                               token_str will set for organization with org_name"
    echo "  -o|--sync-only ORG_NAME[/REPO]"  
    echo "                         - Sync only repo"
    echo "                              If pass only ORG_NAME will sync all repos for organization"
    echo "                              If pass only ORG_NAME/REPO will sync only one repo for organization"
    echo "                              If not passed - will sync all repos for all organizations"
    echo "                           Also can passed via next envs:" 
    echo "                             SYNC_ONLY - format same as argument" 
    echo "                             ORG_TO_SYNC - org for sync" 
    echo "                             REPO_TO_SYNC - repo for sync. If passed" 
    echo "                               ORG_TO_SYNC should be passed"
    echo "  -s|--show-sensitive    - Show sensitives in tofu plan"
    echo "                           Also can be passed via non empty env SHOW_SENSITIVE"
    echo "                           Useful for import exists repositories to control import secrets"  
    echo "  -h|--help              - Display this help message"
    exit "$exit_code"
}

function exit_with_err_and_usage() {
  echo_err "${1:-Error}"
  usage "1"
}

function check_find_installed() {
  if [[ "$OS_NAME" == "Linux" ]]; then
    FIND_BIN="find"
  else
    FIND_BIN="gfind"
  fi

  if ! command -v "$FIND_BIN" > /dev/null; then
    exit_with_err "Find bin '$FIND_BIN' not installed"
  fi
}

function extract_token() {
  local var_name="${1:-}"
  local consumer="${2:-}"
  local consumer_msg="${3:-}"

  local -a token_parts=()
  local var_str="${!var_name}"

  readarray -t -d '' token_parts < <(sed -z "s/$CONST_TOKEN_SEPARATOR/\x00/g" < <(printf '%s' "$var_str"))

  if [[ "${#token_parts[@]}" != "2" ]]; then
    exit_with_err "Token $consumer_msg '$var_name' should contains string with 2 parts separated by '$CONST_TOKEN_SEPARATOR' Got ${#token_parts[@]} parts" 
  fi

  local org_name="${token_parts[0]}"
  local token_str="${token_parts[1]}"

  if [ -z "$org_name" ]; then
    exit_with_err "First part of '$var_name' should not empty organization (owner) name" 
  fi

  if [ -z "$token_str" ]; then
    exit_with_err "Second part of '$var_name' should not empty token $consumer_msg string for org '$org_name'" 
  fi

  local gh_token=""
  if ! gh_token="$("$consumer" "$token_str")"; then
    exit_with_err_and_usage "Cannot extract token with $consumer_msg for var '$var_name' for org '$org_name'"
  fi

  if [ -z "$gh_token" ]; then
    exit_with_err_and_usage "Extracted empty token with $consumer_msg for var '$var_name' for org '$org_name'"
  fi

  ORG_TO_TOKEN["$org_name"]="$gh_token"

  echo_info "Github token for org '$org_name' consumed with $consumer_msg from var $var_name"
}

# shellcheck disable=SC2329
function extract_token_from_file() { 
  local file_path="${1}"
  local extracted_token=""

  if ! extracted_token="$(cat "$file_path")"; then
    if ! extracted_token="$(sudo cat "$file_path")"; then
      exit_with_err_and_usage "Cannot read token from file '$file_path'"
    fi
  fi

  echo -n "$extracted_token"
}

# shellcheck disable=SC2329
function extract_token_from_str() { 
  echo -n "${1}"
}

function consume_github_tokens() {
  local tokens_env_file="${1:-}"

  if [ -n "$tokens_env_file" ]; then
    if [ ! -f "$tokens_env_file" ]; then
      exit_with_err "'$tokens_env_file' file with tokens not found" 
    fi
    set -a 
    # shellcheck disable=SC1090
    if ! source "$tokens_env_file"; then
      set +a
      exit_with_err "Cannot source '$tokens_env_file' with tokens" 
    fi
    set +a
  fi
  
  for var_name in "${!GITHUB_TOKEN_FILE_@}"; do
    if ! extract_token "$var_name" "extract_token_from_file" "token file"; then
      exit_with_err_and_usage "Cannot extract token from token file var '$var_name'"
    fi
  done

  for token_var_name in "${!GITHUB_TOKEN_STRING_@}"; do
    if ! extract_token "$token_var_name" "extract_token_from_str" "direct token string"; then
      exit_with_err_and_usage "Cannot extract token from token file var '$token_var_name'"
    fi
  done
}

function get_github_token_for_org() {
  local org_name="${1}"

  if [[ ! -v ORG_TO_TOKEN["$org_name"] ]]; then
    return 1
  fi

  local token="${ORG_TO_TOKEN[$org_name]}" 

  if [[ -z "$token" ]]; then
    return 1
  fi

  echo -n "$token"
  return 0
  #export GITHUB_TOKEN="$gh_token"
}

function extract_sync_only_params() {
  if [ -n "$REPO_TO_SYNC" ]; then
    if [ -z "$ORG_TO_SYNC" ]; then
      exit_with_err_and_usage "env REPO_TO_SYNC passed but ORG_TO_SYNC is empty"
    else
      return 0
    fi
  fi

  local passed_string="${1:-}"
  if [ -n "${SYNC_ONLY:-}" ]; then
    passed_string="${SYNC_ONLY:-}"
  fi

  if [ -z "$passed_string" ]; then
    return 0
  fi

  local -a sync_only_parts=()

  readarray -t -d '' sync_only_parts < <(sed -z "s|/|\x00|g" < <(printf '%s' "$passed_string"))

  case "${#sync_only_parts[@]}" in
    0)
      return 0
      ;;
    1)
      ORG_TO_SYNC="${sync_only_parts[0]}"
      return 0
      ;;
    2)
      ORG_TO_SYNC="${sync_only_parts[0]}"
      REPO_TO_SYNC="${sync_only_parts[1]}"
      return 0
      ;;
    *)
      exit_with_err_and_usage "Incorrect parts number ${#sync_only_parts} for sync only arg/env. Should be 2"
      ;;
  esac
}

function parse_args() {
  local org_repo=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--gh-tokens-file)
        if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
          exit_with_err "Error: Argument for $1 is missing" >&2
        fi
        TOKENS_FILE="${2-}"
        shift 2
        ;;
      -o|--sync-only)
        if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
          exit_with_err "Error: Argument for $1 is missing" >&2
        fi
        org_repo="${2-}"
        shift 2
        ;;
      -s|--show-sensitive)
        SHOW_SENSITIVE="true"
        shift 1
        ;;
      -h|--help)
        usage "0"
        ;;
      *)
        exit_with_err_and_usage "Unknown argument '${1}'"
        ;;
    esac
  done

  if ! OS_NAME="$(uname)"; then
    exit_with_err "Cannot call uname"
  fi

  check_find_installed

  consume_github_tokens "$TOKENS_FILE"

  extract_sync_only_params "$org_repo"
}

function prepare_tofurc() {
  echo_info "Write tofu cli config to ${TOFU_RC}"

  cat > "$TOFU_RC" <<EOF
plugin_cache_dir = "${WORKING_DIR}/.tmp/cache"
provider_installation {
  filesystem_mirror {
    path    = "${TOFU_PLUGINS_DIR}"
    include = ["*/*"]
  }
}
EOF

  if [ ! -s "$TOFU_RC" ]; then
    exit_with_err "$TOFU_RC is empty" 
  fi

  if ! mkdir -p "$TMPDIR"; then
    exit_with_err "Temp dir '$TMPDIR' was not created" 
  fi

  if ! mkdir -p "$PLANS_DIR"; then
    exit_with_err "Plans dir '$PLANS_DIR' was not created" 
  fi

  trap 'cleanup_after_exit' EXIT
  trap 'cleanup_after_exit' SIGINT
  trap 'cleanup_after_exit' SIGTERM

  export TF_CLI_CONFIG_FILE="$TOFU_RC"
}

function tofu_plan() {
  local plan_file="$1"
  
  local plan_args=("-detailed-exitcode" "-lock=false" "-out=$plan_file")

  if [ -n "$SHOW_SENSITIVE" ]; then
    plan_args+=("-show-sensitive")
  fi
  
  if [ -n "$REPO_TO_SYNC" ]; then
    plan_args+=("-target=module.repos[\"$REPO_TO_SYNC\"]")
  fi

  local plan_exit_code="255"
  if "$TOFU_BIN" plan "${plan_args[@]}"; then
    echo_info "Tofu plan has not changes! Exit"
    return 0
  else
    plan_exit_code="$?"
    case "$plan_exit_code" in
      1)
        echo_err "tofu plan exit with error ^^^"
        return 1
        ;;
      2)
        echo_warn "Plan has diff ^^^"
        if ! ask_user "Apply plan?"; then
          echo_err "Plan dismiss"
          return 1
        fi
        return 2
        ;;
      *)
        echo_err "tofu plan exit with unexpected error code: $plan_exit_code"
        return 1
        ;;
    esac
  fi
}

function print_err_and_pop() {
  local _org="${1:-UNKNOWN_ORG}"
  local _err="${2:-}"

  unset -v GITHUB_TOKEN

  if [ -n "$_err" ]; then
    echo_err "Org '$_org': ${_err}"
  fi

  if ! popd > /dev/null; then
    exit_with_err "Cannot pop dir for org '$_org'" "1"
  fi
}

function sync() {
  local org_name="${1:-}"

  if [ -z "$org_name" ]; then
    echo_err "Org name is not passed"
    return 1
  fi

  local org_dir="${ORGS_DIR}/${org_name}"

  echo_info "Start sync org '$org_name' in dir '$org_dir'"

  unset -v GITHUB_TOKEN

  local gh_token_for_org=""
  if ! gh_token_for_org="$(get_github_token_for_org "$org_name")"; then
    echo_err "Cannot get github token for org '$org_name'"
    return 1
  fi

  export GITHUB_TOKEN="$gh_token_for_org"

  if ! pushd . > /dev/null; then
     exit_with_err "Cannot push current dir"
  fi

  if ! cd "$org_dir"; then
    print_err_and_pop "$org_name" "Cannot cd to org dir '$org_dir'"
    return 1
  fi

  local plan_file=""

  if ! plan_file="$(mktemp -p "$PLANS_DIR" "${org_name}.XXXXXXXXXX.tfplan")"; then
    print_err_and_pop "$org_name" "Cannot create plan file"
    return 1
  fi

  if [ -z "$plan_file" ]; then
    print_err_and_pop "$org_name" "Plan file path is empty"
    return 1
  fi

  echo_info "Tofu plan file for org '$org_name': $plan_file"

  if ! "$TOFU_BIN" init "-plugin-dir=$TOFU_PLUGINS_DIR"; then
    print_err_and_pop "$org_name" "Cannot init tofu"
    return 1
  fi

  local plan_code="255"

  if tofu_plan "$plan_file"; then
    print_err_and_pop "$org_name" ""
    return 0
  else
    plan_code="$?"
    if [[ "$plan_code" != "2" ]]; then
      print_err_and_pop "$org_name" "tofu plan produce error"
      return 1
    fi
  fi

  if ! "$TOFU_BIN" apply -lock=false "$plan_file"; then
    print_err_and_pop "$org_name" "Cannot tofu apply"
    return 1
  fi

  if [ -n "$REPO_TO_SYNC" ]; then
    echo_warn "Repo '$REPO_TO_SYNC' for org '$org_name' synced, but only one!"
  else
    echo_info "Org '$org_name' synced!"
  fi

  print_err_and_pop "$org_name" ""
  return 0
}

function extract_org_name() {
  local org_dir="${1:-}"
  
  if [ -z "$org_dir" ]; then
    return 1
  fi
  
  local org_name=""
  
  if ! org_name="$(basename "$org_dir")"; then
    echo_err "Cannot extract org name from path '$org_dir'"
    return 1
  fi
  
  if [ -z "$org_name" ]; then
    return 1
  fi

  if [[ "$ORG_TO_SYNC" != "" && "$org_name" != "$ORG_TO_SYNC"  ]]; then
    echo_warn "Org '$org_name' skip because ORG_TO_SYNC set to '$ORG_TO_SYNC'"
    return 1
  fi

  echo -n "$org_name"
  return 0
}

function main() {
  parse_args "$@"

  prepare_tofurc

  local org_dir=""

  local -a orgs_list=()

  while IFS= read -r -d '' org_dir; do
    echo_info "Found org dir '$org_dir'"
    local org_name_e=""

    if org_name_e="$(extract_org_name "$org_dir")"; then
      orgs_list+=("$org_name_e")
    fi
	done < <($FIND_BIN "$ORGS_DIR" -maxdepth 1 -mindepth 1 -type d -print0)

  if [ "${#orgs_list[@]}" -eq 0 ]; then
    echo_warn "Nothing to sync"
    exit 0
  fi

  local -a not_passed_tokens=()
  for org_name in "${orgs_list[@]}"; do
    if ! get_github_token_for_org "$org_name" > /dev/null; then
      not_passed_tokens+=("$org_name")
    fi
  done

  if [[ "${#not_passed_tokens[@]}" != "0" ]]; then
    exit_with_err_and_usage "Github tokens not passed for next organizations: ${not_passed_tokens[*]}"
  fi

  for org_name in "${orgs_list[@]}"; do
    echo_info "Found org '$org_name'"
    if ! sync "$org_name"; then
      echo_err "Sync for org '$org_name' failed"
      if ! ask_user "Do you continue?"; then
        exit_with_err "Dismiss continue after fail"
      fi
    fi
  done
}

main "$@"
exit $?