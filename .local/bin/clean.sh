#!/usr/bin/env bash

clean() {
  echo "== Before =="
  df -h / | tail -1

  # Ask for the sudo password once up front
  sudo -v || return 1

  echo "== Pacman: partial downloads and stale lock =="
  sudo rm -rf /var/cache/pacman/pkg/download-*
  # Only remove the lock if pacman isn't actually running
  pgrep -x pacman >/dev/null || sudo rm -f /var/lib/pacman/db.lck

  echo "== Pacman: package cache =="
  # paccache comes from pacman-contrib; install it if missing
  command -v paccache >/dev/null || sudo pacman -S --needed --noconfirm pacman-contrib
  sudo paccache -rk1    # keep 1 cached version of each installed package
  sudo paccache -ruk0   # remove all cached versions of uninstalled packages

  echo "== Orphaned packages =="
  orphans=$(pacman -Qdtq)
  if [ -n "$orphans" ]; then
    echo "$orphans"
    # Left unquoted on purpose so each package name becomes its own argument.
    # No --noconfirm: pacman asks before removing anything.
    sudo pacman -Rns $orphans
  else
    echo "None"
  fi

  echo "== User caches (skipping dotnet/nuget) =="
  find ~/.cache -mindepth 1 -maxdepth 1 \
    -not -iname '*dotnet*' -not -iname '*nuget*' \
    -exec rm -rf {} +

  echo "== Logs and crash dumps =="
  sudo journalctl --vacuum-size=100M
  sudo rm -rf /var/lib/systemd/coredump/*

  if command -v flatpak >/dev/null; then
    echo "== Flatpak unused runtimes =="
    flatpak uninstall --unused -y
  fi

  echo "== After =="
  df -h / | tail -1
}

clean "$@"
