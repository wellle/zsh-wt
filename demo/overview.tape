# Overview GIF: worktree branches in the log, then jump into one by substring.
#
# Run from the repo root: vhs demo/overview.tape

Output assets/overview.gif

Require zsh
Require git

Set Shell zsh
Set FontSize 16
Set Width 1000
Set Height 960
Set Padding 20
Set TypingSpeed 60ms

Hide
Sleep 1s
Type "demo/setup.sh >/dev/null && source demo/zshrc && clear"
Enter
Wait+Screen@30s /shop:/
Show

Type "# wtlog marks branches that have a worktree with [wt]"
Sleep 800ms
Enter
Type "wtlog --graph --oneline --branches --remotes"
Sleep 500ms
Enter
Wait /shop:/
Sleep 4s

Type "# jump to one by branch name, a substring is enough"
Sleep 800ms
Enter
Type "wt check"
Sleep 500ms
Enter
Wait /checkout-v2:/
Sleep 3s
