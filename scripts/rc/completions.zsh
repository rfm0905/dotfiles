test -r "~/.dir_colors" && eval $(dircolors ~/.dir_colors)

##### Completion system #####
bindkey '  ' autosuggest-accept
FPATH="$HOME/.docker/completions:$FPATH"
autoload -Uz +X compinit && compinit
autoload -Uz +X bashcompinit && bashcompinit
autoload -Uz +X promptinit && promptinit


zstyle ':completion:*' menu select
zstyle ':completion:*' insert-unambiguous true # If only one prefix auto-insert
zstyle ':completion:*' group-name '' # group names
zstyle ':completion:*' descriptions yes # command descriptions
zstyle ':completion:*' verbose yes # Option Descriptions
zstyle ':completion:*:descriptions' format '%F{213}%B%d%b%f' # colors

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*' # case doesn't matter
zstyle ':completion:*' completer _complete _approximate # 1-off errors
zstyle ':completion:*:approximate:*' max-errors 1

# cache
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache

# colors
eval "$(gdircolors -b)"
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# history
setopt HIST_IGNORE_DUPS
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt EXTENDED_HISTORY
setopt SHARE_HISTORY
setopt HIST_FIND_NO_DUPS
ZSH_AUTOSUGGEST_HISTORY_IGNORE="gpg *|getpass *|getykw *"


source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
eval "$(fclones complete zsh)"
if output="$(mole completion zsh 2>/dev/null)"; then eval "$output"; fi
