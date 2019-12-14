#! /usr/bin/env bash
set -euo pipefail #TODO?
set -x

#Has been run through https://www.shellcheck.net/

#TODO move all these functions to a lib?

#NOTE you need to set $GITCACHEDIR currently (look at the source)
# run like: GITCACHEDIR=somedir/ ./bootstrap.sh ../repo
# somedir needs to contain a clone of nixpkgs and nixpkgs-channels, I did this because I keep cloning all over my machine and it also makes testing faster, I dont have to spam redownloads of all of nixpkgs

#REFERENCE https://www.atlassian.com/blog/git/alternatives-to-git-submodule-git-subtree

#NOTE well I guess this is kind of pointless but eh?
#NOTE assumes empty target
#TODO nix shebang
#TODO flag for choosing between full clone and --reference?
#TODO nix based tests (dont really see any other way to get reproable tests with this?) <- hand-checking if a result looks ok paradigm, as opposed to property based
#TODO pruning unnecessary old nixpkgs branches?
#TODO add exit traps for worktree cleanup

#TODO add creating initial system branch

################################################################################
#### Constants
################################################################################
CHANNELS_BRANCH="channels"
REPO_UTILS_BRANCH="repo_utils"
CONFIGURATION_BRANCH="configuration"
SYSTEM_BRANCH="system"
NIXOS_CURRENT="nixos-19.09"
#///////////////////////////////////////////////////////////////////////////////
#/// Constants
#///////////////////////////////////////////////////////////////////////////////

################################################################################
#### Repo
################################################################################

#create repo and do config
init_repo(){
  git init
  git config user.name user #TODO
  git config user.email email

  git remote add nixpkgs https://github.com/NixOS/nixpkgs.git # enable easier use
  git remote add nixpkgs-channels https://github.com/NixOS/nixpkgs-channels.git # enable easier use
  add_alternates # makes testing easier because I dont have to spam/wait for nixpkgs clones
  git fetch nixpkgs "master"
  git fetch "nixpkgs-channels" "$NIXOS_CURRENT"
  }


#This is necessary because the repository already exists and --reference is a flag only for clone AFAICT
# https://git-scm.com/docs/gitrepository-layout
add_alternates(){
  # TODO conditional on cache existing or something
  echo "$GITCACHEDIR"/nixpkgs/.git/objects >> ./.git/objects/info/alternates
  echo "$GITCACHEDIR"/nixpkgs-channels/.git/objects >> ./.git/objects/info/alternates
  }

# Create an orphan branch with an empty commit
# https://stackoverflow.com/questions/15034390/how-to-create-a-new-and-empty-root-branch
# TODO this might be pointless in some cases? https://stackoverflow.com/questions/41545293/branch-is-already-checked-out-at-other-location-in-git-worktrees
make_rootless_branch(){
  local branch
  branch="$1"
  git checkout --orphan "$branch"
  git rm -rf . || true
  git commit --allow-empty -m 'base commit (empty)'  #Work around git bugs caused by empty repo
  }

git_commit_all(){
  local message
  message="$1"
  #https://unix.stackexchange.com/questions/155046/determine-if-git-working-directory-is-clean-from-a-script/155077#155077
  if [ -z "$(git status --porcelain)" ]; then
    echo "Workdir clean" #TODO remove
  else
    git add -A
    git commit -m "$message"
  fi
  }

#///////////////////////////////////////////////////////////////////////////////
#/// Repo
#///////////////////////////////////////////////////////////////////////////////

################################################################################
#### Worktree
################################################################################

# Create temporary worktree so we can do operations without interrupting the currently "open" repository
# Note, git doesn't allow having the same branch checked out in multiple worktrees. https://stackoverflow.com/questions/41545293/branch-is-already-checked-out-at-other-location-in-git-worktrees
# TODO note this also means you cant run muliple operations that use this on the same branch at once, i need to figure out a better way to do the wrapping, or just check if we're already in the same place...
# This function should be paired with close_temp_worktree
#   local retFile
#   retFile=$(mktemp -t "worktree.XXXXXXXX")
#   new_temp_worktree "$CHANNELS_BRANCH" "$retFile"
#   local tempLoc
#   tempLoc=$(cat $retFile)
#   close_temp_worktree "$tempLoc"
#   rm "$retFile"
# retFile is used because bash's way of returning values from functions sucks. This also sucks but at least I dont have to fight with I/O descriptors
new_temp_worktree(){
  local branch
  branch="$1"
  local retTarget
  retTarget="$2"
  local target
  target=$(mktemp -d -t "worktree.XXXXXXXX") #should be an absolute path
  git worktree add "$target"/"$branch" "$branch"
  echo "$target"/"$branch" >> "$retTarget"
  }

# Generally paired with new_temp_worktree
# Is used for cleaning up a temporary worktree
close_temp_worktree(){
  local target
  target="$1"
  git worktree remove "$target" #TODO error handling (probably just bail script) (see man page for failure cases; not clean repo)
  rm -rf "$(dirname "$target")" #TODO this still doesnt remove the actual parent directory, how to get this to work?
  }

#///////////////////////////////////////////////////////////////////////////////
#/// Worktree
#///////////////////////////////////////////////////////////////////////////////

################################################################################
#### Channels
################################################################################
init_channel(){
  local branch
  branch="$1"
  #TODO is this how I should be doing this?
  # I imagined it being pointers/checkouts of the master branch at known good (channel) commits
  # But in this case im doing it of the nixpkgs-channels repo? this shouldnt be inefficient because the DB should contain the same data?
  # It doesn't quite feel clean though
  init_channellike "nixpkgs-channels" "$branch"
  }

# Add a branch in a subtree to the channels branch
init_channellike(){
  local upstream
  upstream="$1"
  local branch
  branch="$2"
  #local currentLoc
  #currentLoc="$PWD" #TODO

  local retFile
  retFile=$(mktemp -t "worktree.XXXXXXXX")
  new_temp_worktree "$CHANNELS_BRANCH" "$retFile"
  local tempLoc
  tempLoc=$(cat "$retFile") #TODO might need to make this a lazy operation if this is slow and the same branch needs to be used multiple times; i.e. lazy build and GC at the end of the script
  pushd "$tempLoc"

    #TODO the naming is a hack so i can do subtree pull
    # bleh https://stackoverflow.com/questions/22485673/get-the-upstream-branch-from-a-git-subtree
    # https://stackoverflow.com/questions/16641057/how-can-i-list-the-git-subtrees-on-the-root
    # git log --first-parent channels | grep ...
    git subtree add --prefix "$branch-=-=-$upstream" "$upstream" "$branch"

  popd
  close_temp_worktree "$tempLoc"
  rm "$retFile"
  }

update_channels(){
  local retFile
  retFile=$(mktemp -t "worktree.XXXXXXXX")
  new_temp_worktree "$CHANNELS_BRANCH" "$retFile"
  local tempLoc
  tempLoc=$(cat "$retFile") #TODO might need to make this a lazy operation if this is slow and the same branch needs to be used multiple times; i.e. lazy build and GC at the end of the script
  pushd "$tempLoc"

    for i in */; do
      local branch
      branch="${i%-=-=-*}" # https://stackoverflow.com/questions/13767252/ubuntu-bash-script-how-to-split-path-by-last-slash
      local upstream_ #TODO bleh
      upstream_="${i##*-=-=-}"
      local upstream
      upstream="${upstream_%*/}"
      git subtree pull --prefix "$i" "$upstream" "$branch"
    done
    git_commit_all "updated channels"

  popd
  close_temp_worktree "$tempLoc"
  rm "$retFile"
  }

#///////////////////////////////////////////////////////////////////////////////
#/// Channels
#///////////////////////////////////////////////////////////////////////////////

################################################################################
#### Set up branches
################################################################################

setup_channels(){
  local retFile
  retFile=$(mktemp -t "worktree.XXXXXXXX")
  new_temp_worktree "$CHANNELS_BRANCH" "$retFile"
  local tempLoc
  tempLoc=$(cat "$retFile") #TODO might need to make this a lazy operation if this is slow and the same branch needs to be used multiple times; i.e. lazy build and GC at the end of the script
  pushd "$tempLoc"

    touch readme.adoc
    git_commit_all "Created initial branch structure"

  popd
  close_temp_worktree "$tempLoc"
  rm "$retFile"


  #NOTE more channels is a proportionally larger checkout
  #TODO maybe swap this out / "inline" the functions, this looks like itll check out and remove the worktree 3 times
  init_channellike "nixpkgs" "master"
  init_channel "nixos-unstable"
  init_channel "$NIXOS_CURRENT"
  }

setup_configuration(){
  local retFile
  retFile=$(mktemp -t "worktree.XXXXXXXX")
  new_temp_worktree "$CONFIGURATION_BRANCH" "$retFile"
  local tempLoc
  tempLoc=$(cat "$retFile") #TODO might need to make this a lazy operation if this is slow and the same branch needs to be used multiple times; i.e. lazy build and GC at the end of the script
  pushd "$tempLoc"

    touch readme.adoc
    mkdir docs
    touch docs/pinning.adoc # channels and pinning
    touch docs/obfuscation.adoc # out-of-band data
    mkdir nodes; touch nodes/.keep
    mkdir tests; touch tests/.keep
    mkdir interconnect; touch interconnect/.keep
    mkdir modules; touch modules/.keep
    mkdir overlays; touch overlays/.keep
    touch default.nix
    touch .envrc # TODO tmuxp + direnv auto-dev-environment
    git_commit_all "Created initial branch structure"

  popd
  close_temp_worktree "$tempLoc"
  rm "$retFile"
  }

setup_repo_utils(){
  local self_path
  self_path="$1"

  local retFile
  retFile=$(mktemp -t "worktree.XXXXXXXX")
  new_temp_worktree "$REPO_UTILS_BRANCH" "$retFile"
  local tempLoc
  tempLoc=$(cat "$retFile") #TODO might need to make this a lazy operation if this is slow and the same branch needs to be used multiple times; i.e. lazy build and GC at the end of the script
  pushd "$tempLoc"

    touch readme.adoc
    mkdir docs; touch docs/.keep
    script_template "activate"

    script_template "update_channels"
    #TODO idiosyncratic
    {
      echo "# defined in bootstrap.sh"
      echo "set -x"
      echo CHANNELS_BRANCH="\"$CHANNELS_BRANCH\""
      type git_commit_all new_temp_worktree close_temp_worktree update_channels | grep -v "is a function"
      echo "update_channels"
      } >> "update_channels"

    cp "$self_path" .
    git_commit_all "Created initial branch structure"

  popd
  close_temp_worktree "$tempLoc"
  rm "$retFile"
  }

script_template (){
  local name
  name="$1"
  touch "$name"
  chmod +x "$name"
  echo "#! /usr/bin/env bash" >> "$name"
  echo "set -euo pipefail" >> "$name"
  }

#///////////////////////////////////////////////////////////////////////////////
#/// Set up branches
#///////////////////////////////////////////////////////////////////////////////

# clone_nixpkgs_branch(){
#   local branch="$NIXOS_CURRENT"
#
#   #TODO this is for when merging branch into a config
#   ##add nixpkgs
#   ##TODO
#   #
#   #git subtree add --prefix nixpkgs nixpkgs "$branch" #TODO does this need to be in the root or can i put it in channels?
#   #git subtree add --prefix unstable nixpkgs master #TODO put in channels?
#   ##git subtree pull --prefix nixpkgs nixpkgs master
#   ##TODO document/figure out how to branch and upstream
#   ##mkdir nixpkgs
#
#   }

main(){
  local self_path
  self_path=$(realpath "${BASH_SOURCE[0]}")

  local root
  root=$(realpath "$1") #todo realpath and whatnot?
  shift

  mkdir -p "$root"
  pushd "$root"

  init_repo

  make_rootless_branch "$CHANNELS_BRANCH"
  make_rootless_branch "$CONFIGURATION_BRANCH"
  make_rootless_branch "$REPO_UTILS_BRANCH"

  setup_configuration
  setup_channels
  git checkout --orphan _placeholder #hack to avoid the problems with simultaneous branch checkouts mentioned in new_temp_worktree
  setup_repo_utils "$self_path"
  }

if [ "$#" -eq 0 ]; then
    echo -e "\e[31;1merror:\e[0m must specify a target repo location" >&2
    exit 1
fi

main "$@"
