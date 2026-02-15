#zmodload zsh/zprof && zprof
typeset -U PATH

unamestr="$(uname)"
if [[ "${unamestr}" == 'MSYS_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MINGW64_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MINGW32_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MSYS_NT-10.0' ]] ||
   [[ "${unamestr}" == 'MINGW64_NT-10.0' ]] ||
   [[ "${unamestr}" == 'MINGW32_NT-10.0' ]]; then
  :
elif [[ "${unamestr}" == 'Linux' ]]; then
  export PATH="$HOME/.local/bin:$PATH"
  export XDG_CONFIG_HOME=$HOME/.config
elif [[ "${unamestr}" == 'Darwin' ]]; then
  export PATH="$HOME/.local/bin:$PATH"
  eval "$(/opt/homebrew/bin/brew shellenv)"
  export PATH="/Users/daisuke/.antigravity/antigravity/bin:$PATH"
fi

if [ "$ANTIGRAVITY_AGENT" = "1" ] || [ "$TERM_PROGRAM" = "vscode" ]; then
  return
fi

eval "$(sheldon source)"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

#if (which zprof > /dev/null 2>&1) ;then
#  zprof
#fi

#export ZELLIJ_AUTO_ATTACH=true
#export ZELLIJ_AUTO_EXIT=true
#eval "$(zellij setup --generate-auto-start zsh)"
