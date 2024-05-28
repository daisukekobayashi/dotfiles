PYTHON3_VERSION=3.11.9
PYTHON2_VERSION=2.7.18

export VIRTUAL_ENV_DISABLE_PROMPT=1
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
pyenv shell python${PYTHON3_VERSION}
