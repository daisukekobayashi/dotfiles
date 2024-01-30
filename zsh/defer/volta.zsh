NODEJS_VERSION=20.11.0

export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"
volta install node@v${NODEJS_VERSION}
