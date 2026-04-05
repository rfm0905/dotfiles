# favs
alias c="clear"
alias lsa="lsd -a"
alias home="z ~/"
alias ..="z .."

# gpg
alias getpass="keepassxc-cli clip ~/Passwords.kdbx"
alias getykw="getpass ykw"
alias getgit="getpass rfm0905"
alias gpgd="gpg -d"
alias gpga="gpg --armor"

# utils
zedit() {
  z "${1:-.}"
  zed "${2:-.}"
}
tedit() {
  z "${1:-.}"
  hx "${2:-.}"
}

alias firefox="/Applications/Firefox.app/Contents/MacOS/firefox"
alias cptemp="python3 ~/scripts/rc/cptemp.py"

# better tools
alias cd="z"
alias ogcd="\cd"
alias ls="lsd"
alias ogls="\ls"
alias htop='btop'
alias oghtop='\htop'
alias cat='bat --paging=never'
alias ogcat='\cat'
alias dumbcat='\cat'
alias pipeit='\cat'

# files
alias lsl="lsd -l"
alias lsla="lsd -l -a"
alias tree="tree -a"

# help pages
alias -g -- -h='-h 2>&1 | bat --paging=never --language=help --style=plain --theme="tokyonight"'
alias -g -- --help='--help 2>&1 | bat --paging=never --language=help --style=plain --theme="tokyonight"'

batman() {
  BAT_THEME="tokyonight" command batman "$@"
  return $?
}
alias man='batman'
alias ogman='\man'

# memes
alias fish='asciiquarium'
alias train="sl"

cows() {
  local msg="${1:-hello}"
  for cow in $(cowsay -l | tr ' ' '\n'); do
    cowsay -f "$cow" "$msg from $cow"
  done
}
