# Still image of `wt -p` cleaning up merged branches.
#
# Run from the repo root: vhs demo/prune.tape

Output assets/prune.gif

Require zsh
Require git

Set Shell zsh
Set FontSize 16
Set Width 1200
Set Height 290
Set Padding 20
Set TypingSpeed 60ms

Hide
Sleep 1s
Type "demo/setup.sh >/dev/null && source demo/zshrc && clear"
Enter
Wait+Screen@30s /shop:/
Show

Type "wt -p"
Sleep 300ms
Enter
Wait /Delete\?/
Sleep 1s
Type "y"
Sleep 500ms
Enter
Wait /shop:/
Sleep 500ms
Screenshot assets/prune.png
Sleep 500ms
