#!/usr/bin/env zsh
#
# Tests for zsh-wt, run against a fresh demo repo from demo/setup.sh.
#
# usage: test/run.sh

repo="${0:A:h:h}"
tmp="$(mktemp -d)"
tmp="${tmp:A}"
trap 'rm -rf -- "$tmp"' EXIT

# Isolate from the user's environment and git config.
export HOME="$tmp/home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
unset GIT_PAGER LESS
mkdir -p "$HOME"
git config --global user.name "Test"
git config --global user.email "test@example.com"

demo="$tmp/demo"
"$repo/demo/setup.sh" "$demo" >/dev/null || {
  print -u2 -- "demo setup failed"
  exit 1
}

integer checks=0 failures=0

pass() {
  (( ++checks ))
  print -r -- "ok   $1"
}

fail() {
  (( ++checks, ++failures ))
  print -r -- "FAIL $1"
  print -r -- "${2//$demo/\$DEMO}" | sed 's/^/     | /'
}

# expect_contains <name> <text> <substring>
expect_contains() {
  if [[ "$2" == *"$3"* ]]; then
    pass "$1"
  else
    fail "$1" "expected to contain: $3"$'\n'"got:"$'\n'"$2"
  fi
}

# expect_not_contains <name> <text> <substring>
expect_not_contains() {
  if [[ "$2" != *"$3"* ]]; then
    pass "$1"
  else
    fail "$1" "expected not to contain: $3"$'\n'"got:"$'\n'"$2"
  fi
}

# expect_eq <name> <actual> <expected>
expect_eq() {
  if [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    fail "$1" "expected: $3"$'\n'"got:     $2"
  fi
}

# in_tty <command>: run a command with the plugin loaded in the demo repo,
# under a pseudo-terminal, and print its output without colors.
in_tty() {
  local cmd="source ${(q)repo}/wt.plugin.zsh; cd ${(q)demo}/shop; $1"
  if script --version >/dev/null 2>&1; then
    script -qec "zsh -c ${(q)cmd}" /dev/null </dev/null
  else
    script -q /dev/null zsh -c "$cmd" </dev/null
  fi | perl -pe 's/\e\[[0-9;]*m//g; s/\r//g'
}

has_branch() {
  command git -C "$demo/shop" show-ref --verify --quiet "refs/heads/$1"
}

# --- loading

out="$(source "$repo/wt.plugin.zsh" 2>&1)"
expect_eq "sourcing without compinit prints nothing" "$out" ""

source "$repo/wt.plugin.zsh"
cd "$demo/shop"

# --- help

out="$(wt -h)"
expect_eq "wt -h exits 0" "$?" "0"
expect_contains "wt -h prints usage to stdout" "$out" "usage: wt"
out="$(wt a b 2>&1 >/dev/null)"
expect_contains "wrong usage prints usage to stderr" "$out" "usage: wt"

# --- jumping

wt feature/search >/dev/null
expect_eq "wt <exact branch> jumps" "$PWD" "$demo/worktrees/search"
wt >/dev/null
expect_eq "wt jumps to the main worktree" "$PWD" "$demo/shop"
wt CHECKOUT >/dev/null
expect_eq "wt <substring> ignores case" "$PWD" "$demo/worktrees/checkout-v2"
cd "$demo/shop"

out="$(wt feature </dev/null 2>&1)"
expect_eq "ambiguous substring fails without a tty" "$?" "1"
expect_contains "ambiguous substring lists the matches" "$out" "  feature/coupons"
expect_eq "ambiguous substring stays put" "$PWD" "$demo/shop"
out="$(wt nope 2>&1)"
expect_contains "unknown branch reports it" "$out" "No worktree found for branch: nope"
out="$(wt -d search 2>&1)"
expect_contains "wt -d needs the exact branch" "$out" "No worktree found for branch: search"

# --- listing

out="$(wt -l)"
expect_contains "wt -l marks the current worktree" "$out" "* main "
expect_contains "wt -l tags linked worktrees" "$out" "  feature/search [wt]"
expect_not_contains "wt -l has no colors without a tty" "$out" $'\e['

out="$(wt -ll)"
expect_contains "wt -ll shows changes and ahead" "$out" "fix/rate-limit [wt]       1 changed, ahead 1"
expect_contains "wt -ll shows behind" "$out" "feature/search [wt]       behind 1"
expect_contains "wt -ll shows up to date" "$out" "feature/checkout-v2 [wt]  up to date"

# --- wtlog

out="$(wtlog --branches --remotes --pretty='%C(auto)%h%d %s')"
expect_contains "wtlog tags worktree branches" "$out" "(fix/rate-limit [wt])"
expect_contains "wtlog keeps the other refs" "$out" "origin/feature/checkout-v2, feature/checkout-v2 [wt])"
expect_contains "wtlog does not tag the main worktree" "$out" "(HEAD -> main, origin/main, origin/HEAD)"
expect_contains "wtlog does not tag branches without worktree" "$out" "(origin/feature/dark-mode, feature/dark-mode)"
expect_not_contains "wtlog strips colors without a tty" "$out" $'\e['
out="$(in_tty "GIT_PAGER=cat wtlog -1 fix/rate-limit")"
expect_contains "wtlog decorates the default format in a terminal" "$out" "(fix/rate-limit [wt])"
out="$(in_tty "GIT_PAGER=cat wtlog -1 --no-decorate fix/rate-limit")"
expect_not_contains "wtlog respects --no-decorate" "$out" "fix/rate-limit [wt]"
out="$(in_tty "wt -l")"
expect_contains "wt -l in a terminal shows [wt]" "$out" "feature/search [wt]"

# --- pruning

out="$(print '' | wt -p 2>&1)"
expect_contains "wt -p verifies squash merges by remote tip" "$out" "feature/coupons [wt]     "
expect_contains "wt -p: squash merge verdict" "$out" "nothing unpushed"
expect_contains "wt -p flags unpushed commits" "$out" "! 1 unpushed commit(s)"
expect_contains "wt -p verifies rebase merges by patch" "$out" "all commits in origin/main"
expect_not_contains "wt -p skips open branches" "$out" "dark-mode"
expect_contains "wt -p with Enter deletes nothing" "$out" "Nothing deleted."
[[ -e "$demo/shop/.git/wt-gone-tips" ]]
expect_eq "wt -p remembers pruned remote tips" "$?" "0"

out="$(print 'x' | wt -p 2>&1)"
expect_contains "wt -p rejects bad input" "$out" "Not a listed number: x. Nothing deleted."

print untracked > "$demo/worktrees/coupons/notes.txt"
out="$(print 1 | wt -p 2>&1)"
expect_contains "wt -p keeps dirty worktrees" "$out" "skip feature/coupons: worktree not removed"
has_branch feature/coupons
expect_eq "wt -p keeps the branch of a dirty worktree" "$?" "0"
rm "$demo/worktrees/coupons/notes.txt"

cd "$demo/worktrees/coupons"
out="$(print 1 | wt -p 2>&1)"
expect_contains "wt -p flags the current worktree" "$out" "! you are in this worktree"
expect_contains "wt -p refuses to remove the current worktree" "$out" "skip feature/coupons: you are inside its worktree"
cd "$demo/shop"

out="$(print y | wt -p 2>&1)"
expect_contains "wt -p y still knows the unpushed commit" "$out" "! 1 unpushed commit(s)"
has_branch feature/coupons
expect_eq "wt -p y deletes verified branches" "$?" "1"
has_branch fix/typo-header
expect_eq "wt -p y deletes branches without worktree" "$?" "1"
[[ -d "$demo/worktrees/coupons" ]]
expect_eq "wt -p y removes their worktrees" "$?" "1"
has_branch feature/export-csv
expect_eq "wt -p y keeps flagged branches" "$?" "0"

out="$(print 1 | wt -p 2>&1)"
has_branch feature/export-csv
expect_eq "wt -p deletes a flagged branch picked by number" "$?" "1"

out="$(print '' | wt -p 2>&1)"
expect_contains "wt -p reports when nothing is left" "$out" "No local branches with a gone upstream."
[[ -e "$demo/shop/.git/wt-gone-tips" ]]
expect_eq "wt -p drops the tips file when unused" "$?" "1"

# --- removing

wt -d feature/search >/dev/null
[[ -d "$demo/worktrees/search" ]]
expect_eq "wt -d removes the worktree" "$?" "1"
has_branch feature/search
expect_eq "wt -d keeps the branch" "$?" "0"

wt -D feature/checkout-v2 >/dev/null
has_branch feature/checkout-v2
expect_eq "wt -D deletes the branch" "$?" "1"

out="$(wt -d main 2>&1)"
expect_contains "wt -d refuses the main worktree" "$out" "Refusing to remove the main worktree"

cd "$demo/worktrees/rate-limit"
out="$(wt -d fix/rate-limit 2>&1)"
expect_contains "wt -d refuses the current worktree" "$out" "You are inside that worktree"

print
print -- "$checks checks, $failures failed"
(( failures == 0 ))
