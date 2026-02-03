if [ -f "$HOME/.dotfiles/.env" ]; then
  set -a
  . "$HOME/.dotfiles/.env"
  set +a
fi
