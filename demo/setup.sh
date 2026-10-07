#!/usr/bin/env bash
#
# Build a demo repo with history, branches and worktrees, for recording the
# zsh-wt screenshots and for the tests.
#
# usage: demo/setup.sh [root]    (default root: ~/wt-demo)
#
# Layout:
#   <root>/remote.git          bare repo standing in for GitHub
#   <root>/shop                main worktree, on main
#   <root>/worktrees/<name>    linked worktrees
#
# Branches:
#   feature/checkout-v2  [wt]  active work, up to date with its upstream
#   fix/rate-limit       [wt]  one local commit plus uncommitted changes
#   feature/search       [wt]  a teammate pushed a commit, local is behind 1
#   feature/dark-mode          no worktree, still open upstream
#   feature/coupons      [wt]  squash-merged, upstream deleted
#   feature/export-csv   [wt]  squash-merged, upstream deleted, but one more
#                              local commit that was never pushed
#   fix/typo-header            rebase-merged, upstream deleted
#
# The merged branches were deleted on the remote only, so `wt -p` sees them
# disappear on its fetch. Rerun this script to reset everything.

set -euo pipefail

root="${1:-$HOME/wt-demo}"
marker="$root/.zsh-wt-demo"

if [[ -e "$root" ]]; then
  if [[ ! -e "$marker" ]]; then
    echo "refusing to replace $root: it was not created by $0" >&2
    exit 1
  fi
  rm -rf "$root"
fi
mkdir -p "$root"
touch "$marker"
root="$(cd "$root" && pwd -P)"

# Keep the user's git config out of the demo.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$root/.gitconfig"
git config --global init.defaultBranch main
git config --global user.name "Demo"
git config --global user.email "demo@example.com"
git config --global advice.detachedHead false

now="$(date +%s)"
authors=("Alex Kim" "Sam Rivera" "Jordan Lee" "Taylor Brooks")

# at <hours ago> <author index> <command...>: run a git command as that
# author at that time.
at() {
  local when="$(( now - $1 * 3600 )) +0000"
  local name="${authors[$2]}"
  local email
  email="$(echo "$name" | tr 'A-Z ' 'a-z.')@example.com"
  shift 2
  GIT_AUTHOR_NAME="$name" GIT_AUTHOR_EMAIL="$email" GIT_AUTHOR_DATE="$when" \
    GIT_COMMITTER_NAME="$name" GIT_COMMITTER_EMAIL="$email" GIT_COMMITTER_DATE="$when" \
    "$@"
}

# commit <hours ago> <author index> <message>
commit() {
  at "$1" "$2" git commit -q -m "$3"
}

# edit <file> <line>: append a line and stage the file.
edit() {
  mkdir -p "$(dirname "$1")"
  echo "$2" >> "$1"
  git add "$1"
}

branch() {
  git checkout -q -b "$1" main
}

publish() {
  git push -q -u origin "$(git rev-parse --abbrev-ref HEAD)"
  git checkout -q main
}

git init -q --bare "$root/remote.git"
git clone -q "$root/remote.git" "$root/shop" 2>/dev/null
cd "$root/shop"

edit README.md "# shop"
edit cmd/shop/main.go "package main"
commit 400 0 "Initial shop skeleton"
edit catalog/catalog.go "package catalog"
commit 380 1 "Add product catalog"
edit cart/cart.go "package cart"
commit 350 2 "Add cart service"
edit web/orders.html "<h1>Orders</h1>"
commit 300 3 "Add order history page"
git push -q -u origin main
git remote set-head origin main >/dev/null

branch feature/search
edit search/search.go "package search"
commit 230 2 "Add product search index"
edit search/search.go "// fuzzy matching"
commit 200 2 "Support fuzzy search terms"
edit search/search.go "// tags"
commit 26 1 "Index product tags"
publish
# Local is one behind: the last commit was pushed by a teammate.
git branch -q -f feature/search feature/search~1

edit cart/cart.go "// round prices to cents"
commit 220 1 "Fix price rounding in cart"
edit go.mod "go 1.25"
commit 180 3 "Update dependencies"

branch fix/typo-header
edit web/header.html "<h1>Welcome</h1>"
commit 172 3 "Fix typo in page header"
publish

branch feature/coupons
edit coupons/coupons.go "package coupons"
commit 170 1 "Add coupon model"
edit coupons/coupons.go "// validate codes"
commit 160 1 "Validate coupon codes"
edit cart/cart.go "// apply coupons"
commit 150 1 "Apply coupons in cart"
publish

# Rebase merge on GitHub: same patch, new commit.
at 140 3 git cherry-pick fix/typo-header >/dev/null

branch feature/export-csv
edit export/csv.go "package export"
commit 130 0 "Add CSV export for orders"
edit export/csv.go "// stream rows"
commit 120 0 "Stream CSV rows"
publish

edit web/server.go "package web"
commit 110 3 "Log slow checkout requests"
git merge -q --squash feature/coupons >/dev/null 2>&1
commit 100 1 "Add coupon codes (#42)"
git merge -q --squash feature/export-csv >/dev/null 2>&1
commit 90 0 "Add CSV export for orders (#45)"

branch feature/checkout-v2
edit checkout/v2.go "package checkout"
commit 70 0 "Start checkout v2 flow"
edit checkout/v2.go "// address step"
commit 50 0 "Add address step"
edit checkout/v2.go "// payment step"
commit 20 2 "Add payment step"
publish

branch fix/rate-limit
edit web/ratelimit.go "package web"
commit 40 2 "Rate limit login attempts"
publish

branch feature/dark-mode
edit web/theme.css "body { background: #111; }"
commit 30 3 "Add dark mode theme"
publish

edit web/health.go "package web"
commit 28 1 "Add health check endpoint"
edit db/pool.go "package db"
commit 8 3 "Tune database pool size"
git push -q origin main

for b in feature/checkout-v2 fix/rate-limit feature/search feature/coupons feature/export-csv; do
  git worktree add -q "$root/worktrees/${b#*/}" "$b"
done

cd "$root/worktrees/rate-limit"
edit web/ratelimit.go "// allow a burst of 5"
commit 10 2 "Allow short bursts of login attempts"
echo "// TODO: per-IP limits" >> web/ratelimit.go

cd "$root/worktrees/export-csv"
edit export/csv.go "// taxes column"
commit 60 0 "Include taxes column in export"

# Merged on GitHub: delete the branches there only, so the local
# remote-tracking refs go stale until the next fetch.
for b in feature/coupons feature/export-csv fix/typo-header; do
  git -C "$root/remote.git" update-ref -d "refs/heads/$b"
done

echo "demo repo ready: $root/shop"
