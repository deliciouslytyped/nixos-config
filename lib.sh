#! /usr/bin/env bash
#TODO are these necessary here?
set -euo pipefail #TODO?
set -x

#Has been run through https://www.shellcheck.net/

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
  local branch="$1"
  git checkout --orphan "$branch"
  git rm -rf . || true
  git commit --allow-empty -m 'base commit (empty)'  #Work around git bugs caused by empty repo
  }

git_commit_all(){
  local message="$1"
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
# Note the dynamically scoped variable technique from https://mywiki.wooledge.org/BashFAQ/084 is used for return values
# Originally, I used the file technique, but this is less verbose.
new_temp_worktree(){
  local branch="$1"
  local target
  target=$(mktemp -d -t "worktree.XXXXXXXX") #should be an absolute path
  git worktree add "$target"/"$branch" "$branch"
  retVal="$target"/"$branch"
  }

# Generally paired with new_temp_worktree
# Is used for cleaning up a temporary worktree
close_temp_worktree(){
  local target="$1"
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
  local branch="$1"
  #TODO is this how I should be doing this?
  # I imagined it being pointers/checkouts of the master branch at known good (channel) commits
  # But in this case im doing it of the nixpkgs-channels repo? this shouldnt be inefficient because the DB should contain the same data?
  # It doesn't quite feel clean though
  init_channellike "nixpkgs-channels" "$branch"
  }

# Add a branch in a subtree to the channels branch
#TODO document/figure out how to branch and upstream
init_channellike(){
  local upstream="$1"
  local branch="$2"
  #local currentLoc
  #currentLoc="$PWD" #TODO

  local retVal
  new_temp_worktree "$CHANNELS_BRANCH" #TODO might need to make this a lazy operation if this is slow and the same branch needs to be used multiple times; i.e. lazy build and GC at the end of the script
  pushd "$retVal"

    #TODO the naming is a hack so i can do subtree pull
    # bleh https://stackoverflow.com/questions/22485673/get-the-upstream-branch-from-a-git-subtree
    # https://stackoverflow.com/questions/16641057/how-can-i-list-the-git-subtrees-on-the-root
    # git log --first-parent channels | grep ...
    git subtree add --prefix "$branch-=-=-$upstream" "$upstream" "$branch"

  popd
  close_temp_worktree "$retVal"
  }

update_channels(){
  local retVal
  new_temp_worktree "$CHANNELS_BRANCH" #TODO might need to make this a lazy operation if this is slow and the same branch needs to be used multiple times; i.e. lazy build and GC at the end of the script
  pushd "$retVal"

    for i in */; do
      local branch="${i%-=-=-*}" # https://stackoverflow.com/questions/13767252/ubuntu-bash-script-how-to-split-path-by-last-slash
      local upstream_="${i##*-=-=-}" #TODO bleh
      local upstream="${upstream_%*/}"
      git subtree pull --prefix "$i" "$upstream" "$branch"
    done
    #TODO I can't tell if this is actually necesary? I think subtree pull already creates a commit.
    git_commit_all "updated channels"

  popd
  close_temp_worktree "$retVal"
  }

#///////////////////////////////////////////////////////////////////////////////
#/// Channels
#///////////////////////////////////////////////////////////////////////////////

################################################################################
#### Set up branches
################################################################################

setup_channels(){
  local retVal
  new_temp_worktree "$CHANNELS_BRANCH" #TODO might need to make this a lazy operation if this is slow and the same branch needs to be used multiple times; i.e. lazy build and GC at the end of the script
  pushd "$retVal"

    touch readme.adoc
    git_commit_all "Created initial branch structure"

  popd
  close_temp_worktree "$retVal"


  #NOTE more channels is a proportionally larger checkout
  #TODO maybe swap this out / "inline" the functions, this looks like itll check out and remove the worktree 3 times
  init_channellike "nixpkgs" "master"
  init_channel "nixos-unstable"
  init_channel "$NIXOS_CURRENT"
  }

setup_configuration(){
  local retVal
  new_temp_worktree "$CONFIGURATION_BRANCH" #TODO might need to make this a lazy operation if this is slow and the same branch needs to be used multiple times; i.e. lazy build and GC at the end of the script
  pushd "$retVal"

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
  close_temp_worktree "$retVal"
  }

setup_repo_utils(){
  local self_path="$1"

  local retVal
  new_temp_worktree "$REPO_UTILS_BRANCH" #TODO might need to make this a lazy operation if this is slow and the same branch needs to be used multiple times; i.e. lazy build and GC at the end of the script
  pushd "$retVal"

    touch readme.adoc
    mkdir docs; touch docs/.keep
    script_template "activate"

    script_template "update_channels"
    #TODO idiosyncratic
    {
      echo "# defined in bootstrap.sh"
      echo "set -x"
      echo "#Load lib.sh functions"
      echo . '$(dirname "$(realpath "${BASH_SOURCE[0]}")")'/lib.sh
      type update_channels | grep -v "is a function"
      echo "update_channels"
      } >> "update_channels"

    cp "$self_path"/bootstrap.sh .
    git_commit_all "Created initial branch structure"

  popd
  close_temp_worktree "$retVal"
  }

script_template (){
  local name="$1"
  touch "$name"
  chmod +x "$name"
  echo "#! /usr/bin/env bash" >> "$name"
  echo "set -euo pipefail" >> "$name"
  }

setup_system(){
  local retVal
  new_temp_worktree "$SYSTEM_BRANCH" #TODO might need to make this a lazy operation if this is slow and the same branch needs to be used multiple times; i.e. lazy build and GC at the end of the script
  pushd "$retVal"

    git merge -X theirs --allow-unrelated-histories --no-edit "$CONFIGURATION_BRANCH" || true #TODO temporary hacks in case no changes
    git subtree add --prefix "channel s" "$CHANNELS_BRANCH" || true #TODO figure out how to --no-edit
    git_commit_all "Created initial branch structure"

  popd
  close_temp_worktree "$retVal"
  }

#///////////////////////////////////////////////////////////////////////////////
#/// Set up branches
#///////////////////////////////////////////////////////////////////////////////
