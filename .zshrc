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
  eval "$(~/.local/bin/mise activate zsh)"
elif [[ "${unamestr}" == 'Darwin' ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  eval "$(mise activate zsh)"
fi

eval "$(sheldon source)"
eval "$(gh copilot alias -- zsh)"

#if (which zprof > /dev/null 2>&1) ;then
#  zprof
#fi

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
