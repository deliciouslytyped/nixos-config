#! /usr/bin/env bash
set -euo pipefail #TODO?
set -x

#Load lib.sh functions
. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"/lib.sh

#TODO sort TODOS, I just dumped all the comments at the top here into lib.

main(){
  local self_path
  self_path=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

  local root
  root=$(realpath "$1") #todo realpath and whatnot?
  shift

  mkdir -p "$root"
  pushd "$root"

  init_repo

  make_rootless_branch "$CHANNELS_BRANCH"
  make_rootless_branch "$CONFIGURATION_BRANCH"
  make_rootless_branch "$REPO_UTILS_BRANCH"
  make_rootless_branch "$SYSTEM_BRANCH"

  git checkout --orphan _placeholder #hack to avoid the problems with simultaneous branch checkouts mentioned in new_temp_worktree

  setup_configuration
  setup_channels
  setup_repo_utils "$self_path"
  setup_system
  }

if [ "$#" -eq 0 ]; then
    echo -e "\e[31;1merror:\e[0m must specify a target repo location" >&2
    exit 1
fi

main "$@"
