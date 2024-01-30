RUBY_VERSION=3.3.0

unamestr="$(uname)"
if [[ "${unamestr}" == 'MSYS_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MINGW64_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MINGW32_NT-6.1' ]] ||
   [[ "${unamestr}" == 'MSYS_NT-10.0' ]] ||
   [[ "${unamestr}" == 'MINGW64_NT-10.0' ]] ||
   [[ "${unamestr}" == 'MINGW32_NT-10.0' ]]; then
elif [[ "${unamestr}" == 'Linux' ]]; then
  # rbenv
  export PATH="$HOME/.rbenv/bin:$PATH"
  eval "$(rbenv init -)"
  rbenv shell ${RUBY_VERSION}
elif [[ "${unamestr}" == 'Darwin' ]]; then
  # rbenv
  eval "$(rbenv init -)"
  rbenv shell ${RUBY_VERSION}
  export PATH="${HOME}/.local/bin:$PATH"
fi
