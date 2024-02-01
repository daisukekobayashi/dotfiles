alias ls='ls --color=auto'

unamestr="$(uname)"
if [[ "${unamestr}" == 'MSYS_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MINGW64_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MINGW32_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MSYS_NT-10.0' ]] ||
   [[ "${unamestr}" == 'MINGW64_NT-10.0' ]] ||
   [[ "${unamestr}" == 'MINGW32_NT-10.0' ]]; then
  alias nvm=${WIN_HOME}/scoop/apps/nvm/current/nvm.exe
elif [[ "${unamestr}" == 'Linux' ]]; then
  alias pbcopy='xclip -selection clipboard'
  alias pbpaste='xclip -selection clipboard -o'
  #alias pbcopy='xsel --clipboard --input'
  #alias pbpaste='xsel --clipboard --output'
elif [[ "${unamestr}" == 'Darwin' ]]; then
  :
fi
