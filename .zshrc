HISTFILE=~/.zsh_history      # where history is saved
HISTSIZE=10000               # how many commands are kept in memory
SAVEHIST=10000               # how many are written to the file

setopt SHARE_HISTORY         # share history live between open terminals
setopt HIST_IGNORE_DUPS      # don't record a command if it repeats the previous one
setopt HIST_IGNORE_SPACE     # commands starting with a space are not saved

# Created by newuser for 5.9.2
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
eval "$(starship init zsh)"
# --- Transient prompt: collapse old prompts to a short one ---

# Save Starship's full prompt, and define the short one
_full_prompt="$PROMPT"
_short_prompt='%F{green}❯%f '

# Just before a command runs (Enter pressed), swap in the short prompt
# and redraw the current line with it
zle-line-finish() {
  PROMPT="$_short_prompt"
  zle .reset-prompt
}
zle -N zle-line-finish

# Before each new prompt appears, put the full prompt back
_restore_full_prompt() {
  PROMPT="$_full_prompt"
}
precmd_functions+=(_restore_full_prompt)
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# --- CUSTOM COMMANDS ---

alias rebar='killall waybar; setsid waybar >/dev/null 2>&1 &!'
alias rebind='micro ~/.config/hypr/hyprland.lua'
alias clean='~/.local/bin/clean.sh'
alias clean-cache='~/.local/bin/clean-caches'

# Full-screen recording -> ~/Videos/Screenclips/clip_<timestamp>.mp4
# Stop with Ctrl+C
# Shared helper: records to .mkv, then converts to .mp4 when you stop (Ctrl+C)
# Extra args (like -g "$(slurp)" or --audio) are passed through to wf-recorder
_clip_record() {
  # Make the trap below local to this function so it doesn't leak into your shell
  setopt localoptions localtraps

  mkdir -p ~/Videos/Screenclips
  local base=~/Videos/Screenclips/clip_$(date +%Y-%m-%d_%H-%M-%S)

  # Without this, Ctrl+C would also kill THIS function and the conversion
  # below would never run. A non-empty trap handler runs in the shell only;
  # wf-recorder still gets a normal Ctrl+C and stops cleanly.
  trap ':' INT

  wf-recorder -x yuv420p -f "$base.mkv" "$@"

  echo "Converting to mp4..."
  # -nostdin: stops ffmpeg from reading your keyboard
  # &&: only delete the mkv if the conversion succeeded
  ffmpeg -nostdin -loglevel error -i "$base.mkv" \
    -c:v copy -c:a aac -movflags +faststart "$base.mp4" \
    && rm "$base.mkv" \
    && echo "Saved: $base.mp4" \
    || echo "Conversion failed, your recording is kept at: $base.mkv"
}

# Full screen
srec() {
  _clip_record "$@"
}

# Region: drag a box with the mouse first
srecm() {
  _clip_record -g "$(slurp)" "$@"
}

y() {
  local tmp="$(mktemp -t yazi-cwd.XXXXXX)" cwd
  yazi "$@" --cwd-file="$tmp"
  cwd="$(command cat -- "$tmp")"
  [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}

# --- END OF CUSTOM COMMANDS ---

setopt interactive_comments

# Home / End / Delete / Ctrl+arrows
[[ -n "${terminfo[khome]}" ]] && bindkey "${terminfo[khome]}" beginning-of-line
[[ -n "${terminfo[kend]}"  ]] && bindkey "${terminfo[kend]}"  end-of-line
[[ -n "${terminfo[kdch1]}" ]] && bindkey "${terminfo[kdch1]}" delete-char
bindkey '^[[H'    beginning-of-line
bindkey '^[[F'    end-of-line
bindkey '^[[3~'   delete-char
bindkey '^[[1;5C' forward-word      # Ctrl+Right
bindkey '^[[1;5D' backward-word     # Ctrl+Left
bindkey '^[[3;5~' kill-word         # Ctrl+Delete


export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$HOME/.dotnet:$HOME/.dotnet/tools
# dotfiles bare repo: use `dot` instead of `git` for dotfiles
alias dot='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
alias dotlg='lazygit --git-dir=$HOME/.dotfiles --work-tree=$HOME'
