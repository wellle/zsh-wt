# Still image of `wt -ll`.
#
# Run from the repo root: vhs demo/list.tape

Output assets/list.gif

Require zsh
Require git

Set Shell zsh
Set FontSize 16
Set Width 1200
Set Height 220
Set Padding 20
Set TypingSpeed 60ms

Hide
Sleep 1s
Type "demo/setup.sh >/dev/null && source demo/zshrc && clear"
Enter
Wait+Screen@30s /shop:/
Show

Type "wt -ll"
Sleep 300ms
Enter
Wait /shop:/
Sleep 500ms
Screenshot assets/list.png
Sleep 500ms
