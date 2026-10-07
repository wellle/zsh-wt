# zsh-wt - jump between git worktrees by branch name, see them in git log,
# and clean up merged ones.
#
# https://github.com/wellle/zsh-wt
#
# Install:
#   source /path/to/zsh-wt/wt.plugin.zsh
#   (or load it with your plugin manager, see README.md)
#
# Optional prompt hint:
#   Put $(git_worktree_hint) at the start of PROMPT to show [wt] in linked worktrees.
#   Example:
#
#     PROMPT='$(git_worktree_hint)${vcs_info_msg_0_}%f%F{yellow}%1~%F{magenta}:%f '
#     PROMPT2='%F{yellow}%_ %f%f '
#
# Commands:
#   wt <branch>    Jump to the worktree for that branch; a unique
#                  case-insensitive substring works too (fzf picks on ties)
#   wt             Jump to the main worktree for the current repo
#   wt -l          List worktrees (* = current, [wt] = linked)
#   wt -ll         List worktrees with uncommitted changes and upstream status
#   wt -p          Delete local branches whose upstream is gone (after a
#                  confirmation), removing their linked worktrees too
#   wt -d <branch> Remove the linked worktree for that branch
#   wt -D <branch> Remove the linked worktree and delete the branch
#   wt -h          Show a brief usage message
#   wtpath <b>     Print the linked worktree path for branch <b>
#   wtmainpath     Print the main worktree path for the current repo
#   wtlog          `git log` that tags linked worktree branches with [wt]
#                  in the ref decorations, e.g.
#                    alias gl='wtlog --graph --pretty=format:"%C(auto)%h%d %s"'
#
# Notes:
#   - Completion offers only branches that are currently attached to a worktree.
#   - Detached worktrees are not addressable by branch name.
#   - wt -d / wt -D need the exact branch name and refuse to remove the main worktree.
#   - wt -D deletes the branch with `git branch -D` after removing its worktree.
#   - wt -p never forces: worktrees with uncommitted or untracked files are kept.

# This file is intended for zsh.
[[ -n "$ZSH_VERSION" ]] || return 0

# Needed if the user wants to embed $(git_worktree_hint) in PROMPT.
setopt PROMPT_SUBST

__wt_abspath() {
  (
    builtin cd -- "$1" 2>/dev/null || exit 1
    builtin pwd -P
  )
}

wtmainpath() {
  local common_dir

  common_dir="$(command git rev-parse --git-common-dir 2>/dev/null)" || {
    print -u2 -- "Not in a git repository"
    return 1
  }

  [[ "$common_dir" = /* ]] || common_dir="$(__wt_abspath "$common_dir")" || {
    print -u2 -- "Could not resolve main worktree path"
    return 1
  }

  print -r -- "${common_dir:h}"
}

wtpath() {
  local target_branch="$1"
  local line current_wt found_branch

  if [[ -z "$target_branch" ]]; then
    wtmainpath
    return
  fi

  while IFS= read -r line; do
    if [[ "$line" == worktree\ * ]]; then
      current_wt="${line#worktree }"
    elif [[ "$line" == branch\ refs/heads/* ]]; then
      found_branch="${line#branch refs/heads/}"
      if [[ "$found_branch" == "$target_branch" ]]; then
        print -r -- "$current_wt"
        return 0
      fi
    fi
  done < <(command git worktree list --porcelain 2>/dev/null)

  return 1
}

# Print usage to stderr, or to stdout with $1 = 1 (for wt -h).
__wt_usage() {
  local fd=2
  [[ "$1" == 1 ]] && fd=1
  print -u$fd -- "usage: wt [-h | -l | -ll | -p | -d|-D] [branch]"
  print -u$fd -- "  wt              jump to main worktree"
  print -u$fd -- "  wt <branch>     jump to worktree for branch (unique substring works too)"
  print -u$fd -- "  wt -l           list worktrees (* = current, [wt] = linked)"
  print -u$fd -- "  wt -ll          list worktrees with changes and upstream status"
  print -u$fd -- "  wt -p           delete branches whose upstream is gone, and their worktrees"
  print -u$fd -- "  wt -d <branch>  remove linked worktree for branch"
  print -u$fd -- "  wt -D <branch>  remove linked worktree and delete branch"
  print -u$fd -- "  wt -h           show this help"
}

__wt_remove() {
  local target_branch="$1"
  local delete_branch="$2"
  local dest main here

  [[ -n "$target_branch" ]] || {
    __wt_usage
    return 1
  }

  dest="$(wtpath "$target_branch")" || {
    print -u2 -- "No worktree found for branch: $target_branch"
    return 1
  }

  main="$(wtmainpath)" || return 1

  if [[ "$dest" == "$main" ]]; then
    print -u2 -- "Refusing to remove the main worktree: $dest"
    return 1
  fi

  here="$(__wt_abspath "$PWD")" || here="$PWD"
  if [[ "$here" == "$dest" || "$here" == "$dest"/* ]]; then
    print -u2 -- "You are inside that worktree. cd elsewhere first."
    return 1
  fi

  print -r -- "remove -> ${dest/#$HOME/~}"
  command git worktree remove -- "$dest" || return 1

  if [[ "$delete_branch" == 1 ]]; then
    print -- "delete branch -> $target_branch"
    command git -C "$main" branch -D -- "$target_branch" || return 1
  fi
}

# Print one "path<TAB>branch<TAB>head" line per worktree, main worktree first.
# branch is empty for detached worktrees.
__wt_records() {
  local line wt_path="" branch="" head=""

  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        wt_path="${line#worktree }"
        ;;
      HEAD\ *)
        head="${line#HEAD }"
        ;;
      branch\ refs/heads/*)
        branch="${line#branch refs/heads/}"
        ;;
      "")
        [[ -n "$wt_path" ]] && print -r -- "$wt_path"$'\t'"$branch"$'\t'"$head"
        wt_path="" branch="" head=""
        ;;
    esac
  done < <(command git worktree list --porcelain 2>/dev/null)

  if [[ -n "$wt_path" ]]; then
    print -r -- "$wt_path"$'\t'"$branch"$'\t'"$head"
  fi
}

# Print the branches checked out in linked (non-main) worktrees.
__wt_linked_branches() {
  local -a records fields
  local rec

  records=("${(@f)$(__wt_records)}")
  for rec in "${(@)records[2,-1]}"; do
    fields=("${(@ps:\t:)rec}")
    [[ -n "${fields[2]}" ]] && print -r -- "${fields[2]}"
  done
  return 0
}

# Print the worktree branches containing $1, ignoring case.
__wt_match() {
  local -a records fields
  local rec query="${(L)1}"

  records=("${(@f)$(__wt_records)}")
  for rec in "${records[@]}"; do
    fields=("${(@ps:\t:)rec}")
    [[ -n "${fields[2]}" && "${(L)fields[2]}" == *"$query"* ]] && print -r -- "${fields[2]}"
  done
  return 0
}

# Print the worktree path for a partial branch name. With several matches,
# pick one with fzf when available, otherwise list them.
__wt_resolve() {
  local -a matches
  local pick

  matches=("${(@f)$(__wt_match "$1")}")
  matches=("${(@)matches:#}")

  case ${#matches} in
    0)
      print -u2 -- "No worktree found for branch: $1"
      return 1
      ;;
    1)
      pick="${matches[1]}"
      ;;
    *)
      if [[ -t 0 ]] && (( $+commands[fzf] )); then
        pick="$(print -rl -- "${matches[@]}" | fzf --height=40% --reverse --prompt="wt $1> ")" || return 1
      else
        print -u2 -- "Multiple worktrees match '$1':"
        print -u2 -l -- "  ${^matches[@]}"
        return 1
      fi
      ;;
  esac

  wtpath "$pick"
}

# Summarize the worktree at $1: uncommitted changes and upstream tracking.
__wt_state() {
  local line upstream="" ab="" ahead behind
  local -a parts
  local -i changes=0

  while IFS= read -r line; do
    case "$line" in
      "# branch.upstream "*)
        upstream="${line#\# branch.upstream }"
        ;;
      "# branch.ab "*)
        ab="${line#\# branch.ab }"
        ;;
      "#"*)
        ;;
      *)
        changes+=1
        ;;
    esac
  done < <(command git -C "$1" status --porcelain=v2 --branch 2>/dev/null)

  (( changes )) && parts+=("$changes changed")
  if [[ -z "$upstream" ]]; then
    parts+=("no upstream")
  elif [[ -z "$ab" ]]; then
    parts+=("upstream gone")
  else
    ahead="${${ab%% *}#+}"
    behind="${${ab##* }#-}"
    (( ahead )) && parts+=("ahead $ahead")
    (( behind )) && parts+=("behind $behind")
  fi
  (( ${#parts} )) || parts=("up to date")

  print -r -- "${(j:, :)parts}"
}

# List worktrees. With $1 = 1, also show changes and upstream status.
__wt_list() {
  setopt localoptions extendedglob
  local long="$1"
  local -a records fields labels tags marks paths states
  local here label tag st cyan="" yellow="" reset=""
  local i width=0 swidth=0 len

  records=("${(@f)$(__wt_records)}")
  [[ -n "${records[1]}" ]] || {
    print -u2 -- "Not in a git repository"
    return 1
  }

  here="$(command git rev-parse --show-toplevel 2>/dev/null)"
  if [[ -t 1 ]]; then
    cyan=$'\e[36m'
    yellow=$'\e[33m'
    reset=$'\e[m'
  fi

  for (( i = 1; i <= ${#records}; i++ )); do
    fields=("${(@ps:\t:)records[i]}")
    label="${fields[2]:-(detached ${fields[3][1,10]})}"
    tag=""
    (( i > 1 )) && tag=" [wt]"
    labels+=("$label")
    tags+=("$tag")
    paths+=("${fields[1]/#$HOME/~}")
    if [[ "${fields[1]}" == "$here" ]]; then
      marks+=("*")
    else
      marks+=(" ")
    fi
    len=$(( ${#label} + ${#tag} ))
    (( len > width )) && width=$len
    if [[ "$long" == 1 ]]; then
      st="$(__wt_state "${fields[1]}")"
      states+=("$st")
      (( ${#st} > swidth )) && swidth=${#st}
    fi
  done

  for (( i = 1; i <= ${#records}; i++ )); do
    len=$(( ${#labels[i]} + ${#tags[i]} ))
    printf '%s %s%s%*s  ' "${marks[i]}" "${labels[i]}" \
      "${tags[i]:+ ${cyan}[wt]${reset}}" $(( width - len )) ""
    if [[ "$long" == 1 ]]; then
      st="${states[i]}"
      printf '%s%*s  ' "${st//(#m)([0-9]## changed|upstream gone)/${yellow}${MATCH}${reset}}" \
        $(( swidth - ${#st} )) ""
    fi
    print -r -- "${paths[i]}"
  done
}

# Count the commits on $2 that have no patch-equivalent commit in $1.
__wt_unmatched() {
  command git cherry "$1" "$2" 2>/dev/null | grep -c '^+'
}

# Find local branches whose upstream is gone (merged and deleted on the
# remote), list them, and after confirmation delete them together with their
# linked worktrees.
#
# A branch counts as verified when all its commits are in the remote's
# default branch (by patch, so rebases are fine), or when none are missing
# from the last known remote tip. Remote tips are remembered in
# <git-common-dir>/wt-gone-tips, because the fetch deletes them. Branches
# flagged with ! are only deleted when picked by number: unverified or
# unpushed commits, uncommitted changes, or the current worktree.
__wt_prune() {
  local main here tips_file ref sha branch upstream track wt_path when note answer
  local remote default cyan="" yellow="" reset="" sep=$'\x1f'
  local -A old_tips
  local -a branches paths whens notes risky picks keep_tips
  local i n m width=0 len

  main="$(wtmainpath)" || return 1
  here="$(command git rev-parse --show-toplevel 2>/dev/null)"
  if [[ -t 1 ]]; then
    cyan=$'\e[36m'
    yellow=$'\e[33m'
    reset=$'\e[m'
  fi

  tips_file="$(command git rev-parse --path-format=absolute --git-common-dir)/wt-gone-tips"

  # Remember the remote tips, so branches pruned by this fetch can still be
  # checked for commits that never made it to the remote.
  if [[ -r "$tips_file" ]]; then
    while IFS=' ' read -r ref sha; do
      old_tips[$ref]="$sha"
    done < "$tips_file"
  fi
  while IFS=' ' read -r ref sha; do
    old_tips[$ref]="$sha"
  done < <(command git for-each-ref --format='%(refname) %(objectname)' refs/remotes)

  print -- "fetching and pruning remotes..."
  command git fetch --all --prune --quiet ||
    print -u2 -- "fetch failed, using the remote-tracking refs as they are"
  command git worktree prune

  while IFS="$sep" read -r branch upstream track wt_path when; do
    [[ "$track" == "[gone]" ]] || continue
    # The main worktree cannot be removed, so neither can its branch.
    [[ "$wt_path" == "$main" ]] && continue

    remote="${${upstream#refs/remotes/}%%/*}"
    default="$(command git symbolic-ref -q "refs/remotes/$remote/HEAD")"
    n=1
    m=-1
    [[ -n "$default" ]] && m=$(__wt_unmatched "$default" "refs/heads/$branch")
    if (( m == 0 )); then
      note="all commits in ${default#refs/remotes/}"
      n=0
    elif [[ -n "${old_tips[$upstream]}" ]]; then
      keep_tips+=("$upstream ${old_tips[$upstream]}")
      n=$(__wt_unmatched "${old_tips[$upstream]}" "refs/heads/$branch")
      if (( n )); then
        note="$n unpushed commit(s)"
      else
        note="nothing unpushed"
      fi
    elif (( m > 0 )); then
      note="$m commit(s) not in ${default#refs/remotes/}, remote tip unknown"
    else
      note="cannot verify, remote tip unknown"
    fi
    if [[ -n "$wt_path" ]]; then
      if [[ "$wt_path" == "$here" ]]; then
        note="you are in this worktree"
        n=1
      elif [[ -n "$(command git -C "$wt_path" status --porcelain 2>/dev/null)" ]]; then
        note="${note:+$note, }uncommitted changes"
        n=1
      fi
    fi

    branches+=("$branch")
    paths+=("$wt_path")
    whens+=("$when")
    notes+=("$note")
    risky+=($(( n > 0 )))
    len=${#branch}
    [[ -n "$wt_path" ]] && (( len += 5 ))
    (( len > width )) && width=$len
  done < <(command git for-each-ref \
    --format="%(refname:short)%1f%(upstream)%1f%(upstream:track)%1f%(worktreepath)%1f%(committerdate:relative)" \
    refs/heads)

  # Keep only the tips still needed: those of branches listed now.
  if (( ${#keep_tips} )); then
    print -rl -- "${keep_tips[@]}" > "$tips_file"
  else
    rm -f -- "$tips_file"
  fi

  if (( ! ${#branches} )); then
    print -- "No local branches with a gone upstream."
    return 0
  fi

  print -- "Local branches whose upstream is gone:"
  for (( i = 1; i <= ${#branches}; i++ )); do
    len=${#branches[i]}
    [[ -n "${paths[i]}" ]] && (( len += 5 ))
    printf '  %2d  %s%s%*s  %-14s  ' $i "${branches[i]}" \
      "${paths[i]:+ ${cyan}[wt]${reset}}" $(( width - len )) "" "${whens[i]}"
    if (( risky[i] )); then
      print -r -- "${yellow}! ${notes[i]}${reset}"
    else
      print -r -- "${notes[i]}"
    fi
  done

  print
  read -r "answer?Delete? [y = all without !, numbers like '1 3', Enter = none]: "
  case "$answer" in
    [yY]|[yY][eE][sS])
      for (( i = 1; i <= ${#branches}; i++ )); do
        (( risky[i] )) || picks+=($i)
      done
      ;;
    "")
      print -- "Nothing deleted."
      return 0
      ;;
    *)
      for i in ${=answer}; do
        if [[ "$i" != <-> ]] || (( i < 1 || i > ${#branches} )); then
          print -u2 -- "Not a listed number: $i. Nothing deleted."
          return 1
        fi
        picks+=($i)
      done
      ;;
  esac

  for i in "${(@u)picks}"; do
    if [[ -n "${paths[i]}" ]]; then
      if [[ "${paths[i]}" == "$here" ]]; then
        print -u2 -- "skip ${branches[i]}: you are inside its worktree, cd elsewhere first"
        continue
      fi
      print -- "remove worktree -> ${paths[i]/#$HOME/~}"
      command git -C "$main" worktree remove -- "${paths[i]}" || {
        print -u2 -- "skip ${branches[i]}: worktree not removed (git worktree remove --force to discard changes)"
        continue
      }
    fi
    command git -C "$main" branch -D -- "${branches[i]}"
  done
}

# Highlight [wt] after colored local branch decorations named in $1
# (newline-separated). With $2 set, strip all colors afterwards.
__wt_mark_branches() {
  WT_BRANCHES="$1" WT_STRIP="$2" command perl -pe '
    BEGIN {
      $| = 1;
      my $alt = join "|", map { quotemeta } split /\n/, $ENV{WT_BRANCHES};
      $re = qr/(\e\[[0-9;]*m(?:$alt)\e\[m)/;
    }
    s/$re/$1 \e[36m[wt]\e[m/g;
    s/\e\[[0-9;]*m//g if $ENV{WT_STRIP};
  '
}

# `git log` that appends a cyan [wt] to local branch decorations (%d / %D)
# whose branch is checked out in a linked worktree, so `wt <branch>` works.
wtlog() {
  local -a branches decorate
  local pager

  branches=("${(@f)$(__wt_linked_branches)}")
  branches=("${(@)branches:#}")
  if (( ! ${#branches} )); then
    command git log "$@"
    return
  fi

  if [[ -t 1 ]]; then
    # git decorates by default only when it writes to a terminal, which it
    # no longer does here. Arguments after this one still override it.
    case "$(command git config --get log.decorate)" in
      ""|auto) decorate=(--decorate) ;;
    esac
    pager="$(command git var GIT_PAGER)"
    command git log --color=always "${decorate[@]}" "$@" |
      __wt_mark_branches "${(F)branches}" |
      LESS="${LESS-FRX}" LV="${LV--c}" sh -c "$pager"
  else
    command git log --color=always "$@" |
      __wt_mark_branches "${(F)branches}" 1
  fi
}

wt() {
  local mode="jump"
  local target_branch="$1"
  local dest

  case "$1" in
    -h|--help)
      __wt_usage 1
      return
      ;;
    -l|-ll|-p)
      (( $# == 1 )) || {
        __wt_usage
        return 1
      }
      case "$1" in
        -l) __wt_list 0 ;;
        -ll) __wt_list 1 ;;
        -p) __wt_prune ;;
      esac
      return
      ;;
    -d)
      mode="remove"
      shift
      ;;
    -D)
      mode="remove-and-branch"
      shift
      ;;
  esac

  if [[ "$mode" == "remove" ]]; then
    (( $# == 1 )) || {
      __wt_usage
      return 1
    }
    __wt_remove "$1" 0
    return
  fi

  if [[ "$mode" == "remove-and-branch" ]]; then
    (( $# == 1 )) || {
      __wt_usage
      return 1
    }
    __wt_remove "$1" 1
    return
  fi

  (( $# <= 1 )) || {
    __wt_usage
    return 1
  }

  dest="$(wtpath "$1")" || {
    [[ -n "$1" ]] || return 1
    dest="$(__wt_resolve "$1")" || return 1
  }

  print -r -- "cd -> ${dest/#$HOME/~}"
  builtin cd -- "$dest"
}

__git_is_linked_worktree() {
  local git_dir common_dir

  git_dir="$(command git rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  common_dir="$(command git rev-parse --git-common-dir 2>/dev/null)" || return 1

  [[ "$git_dir" = /* ]] || git_dir="$(__wt_abspath "$git_dir")" || return 1
  [[ "$common_dir" = /* ]] || common_dir="$(__wt_abspath "$common_dir")" || return 1

  [[ "$git_dir" != "$common_dir" ]]
}

git_worktree_hint() {
  __git_is_linked_worktree || return
  print -n -- "%F{cyan}[wt]%f "
}

# Completion lives in functions/_wt. Adding it to fpath lets a later
# compinit find it; if compinit already ran, register it directly.
fpath=("${${(%):-%x}:A:h}/functions" "${fpath[@]:#${${(%):-%x}:A:h}/functions}")
if (( $+functions[compdef] )); then
  autoload -Uz _wt
  compdef _wt wt
fi
