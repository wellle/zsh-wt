# GIF of the fzf picker for an ambiguous `wt` substring. Needs fzf.
#
# Run from the repo root: vhs demo/picker.tape

Output assets/picker.gif

Require zsh
Require git
Require fzf

Set Shell zsh
Set FontSize 16
Set Width 1200
Set Height 420
Set Padding 20
Set TypingSpeed 80ms

Hide
Sleep 1s
Type "demo/setup.sh >/dev/null && source demo/zshrc && clear"
Enter
Wait+Screen@30s /shop:/
Show

Type "wt feature"
Sleep 500ms
Enter
Wait /wt feature>/
Sleep 1.5s
Type "sea"
Sleep 1s
Enter
Wait /search:/
Sleep 2s
