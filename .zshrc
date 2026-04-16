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

# SSH agent / key setup
export SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
export SSH_FALLBACK_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"

setup_ssh_agent() {
  local agent_status
  local managed_agent=0

  # Reuse an already reachable agent.
  # This also preserves forwarded agents from remote SSH sessions when
  # they already have a usable identity loaded.
  ssh-add -l >/dev/null 2>&1
  agent_status=$?

  if [[ "${SSH_AUTH_SOCK:-}" == "$SSH_FALLBACK_AUTH_SOCK" ]]; then
    managed_agent=1
  fi

  if [[ $agent_status -ne 0 ]] && [[ $managed_agent -eq 0 ]]; then
    if [[ "$unamestr" == "Linux" ]] && command -v keychain >/dev/null 2>&1; then
      # Reuse or start a long-lived agent via keychain.
      eval "$(keychain --eval --quiet --agents ssh "$SSH_KEY_PATH")"
      managed_agent=1

      ssh-add -l >/dev/null 2>&1
      agent_status=$?
    fi

    if [[ $agent_status -ne 0 ]]; then
      # Fallback: keep the agent on a fixed socket so tmux panes can share it.
      export SSH_AUTH_SOCK="$SSH_FALLBACK_AUTH_SOCK"
      managed_agent=1

      if [[ ! -S "$SSH_AUTH_SOCK" ]]; then
        rm -f "$SSH_AUTH_SOCK"
        eval "$(ssh-agent -a "$SSH_AUTH_SOCK")" >/dev/null
      else
        ssh-add -l >/dev/null 2>&1
        if [[ $? -eq 2 ]]; then
          rm -f "$SSH_AUTH_SOCK"
          eval "$(ssh-agent -a "$SSH_AUTH_SOCK")" >/dev/null
        fi
      fi
    fi
  fi
}

setup_ssh_agent

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

alias claude-mem='"$HOME/.bun/bin/bun" "$HOME/.claude/plugins/cache/thedotmack/claude-mem/10.4.3/scripts/worker-service.cjs"'
