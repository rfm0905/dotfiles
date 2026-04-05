# memes
alias fish='asciiquarium'
alias train="sl"

cows() {
  local msg="${1:-hello}"
  for cow in $(cowsay -l | tr ' ' '\n'); do
    cowsay -f "$cow" "$msg from $cow"
  done
}
