#!/usr/bin/env bash
# bootstrap.sh — minimal Debian 13 (trixie) dev box
# Prereq: netinst with NO desktop selected, your user in the sudo group.
# Usage:  WM=sway ./bootstrap.sh      (or WM=hyprland)
# Safe to re-run.
set -euo pipefail

WM="${WM:-sway}"                      # sway | hyprland
DOTNET_CHANNEL="${DOTNET_CHANNEL:-10.0}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] && { echo "Run as your normal user, not root."; exit 1; }
sudo -v
. /etc/os-release                      # gives VERSION_ID (13) and VERSION_CODENAME (trixie)

# ---------------------------------------------------------------- base
log "Base packages"
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  ca-certificates curl wget gpg git unzip \
  network-manager \
  pipewire pipewire-pulse wireplumber \
  foot fuzzel mako-notifier waybar \
  grim slurp wl-clipboard brightnessctl \
  xwayland xdg-desktop-portal xdg-user-dirs \
  fonts-noto-core fonts-jetbrains-mono \
  chromium

# NOTE: if the installer set up wifi in /etc/network/interfaces,
# remove that stanza or NetworkManager will ignore the interface.
sudo systemctl enable --now NetworkManager
xdg-user-dirs-update

# ---------------------------------------------------------------- window manager
case "$WM" in
  sway)
    log "Sway"
    sudo apt-get install -y --no-install-recommends \
      sway swaybg swayidle swaylock xdg-desktop-portal-wlr
    mkdir -p ~/.config/sway
    if [[ ! -f ~/.config/sway/config ]]; then
      cp /etc/sway/config ~/.config/sway/config
      sed -i 's/^set \$menu .*/set $menu fuzzel/' ~/.config/sway/config
    fi
    WM_CMD=sway
    ;;
  hyprland)
    log "Hyprland (trixie-backports)"
    echo "deb http://deb.debian.org/debian ${VERSION_CODENAME}-backports main" \
      | sudo tee /etc/apt/sources.list.d/backports.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y -t "${VERSION_CODENAME}-backports" \
      hyprland xdg-desktop-portal-hyprland hyprpolkitagent
    # newer Hyprland ships a start-hyprland wrapper; fall back if absent
    if command -v start-hyprland >/dev/null; then WM_CMD=start-hyprland; else WM_CMD=Hyprland; fi
    ;;
  *) echo "Unknown WM: $WM"; exit 1 ;;
esac

# ---------------------------------------------------------------- extra repos
log "VSCodium repo"
wget -qO- https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg \
  | gpg --dearmor | sudo tee /usr/share/keyrings/vscodium-archive-keyring.gpg >/dev/null
sudo tee /etc/apt/sources.list.d/vscodium.sources >/dev/null <<EOF
Types: deb
URIs: https://download.vscodium.com/debs
Suites: vscodium
Components: main
Architectures: amd64 arm64
Signed-By: /usr/share/keyrings/vscodium-archive-keyring.gpg
EOF

log "Microsoft repo (.NET)"
if ! dpkg -s packages-microsoft-prod >/dev/null 2>&1; then
  wget -q "https://packages.microsoft.com/config/debian/${VERSION_ID}/packages-microsoft-prod.deb" -O /tmp/ms.deb
  sudo dpkg -i /tmp/ms.deb
  rm -f /tmp/ms.deb
fi

log "VSCodium + .NET SDK ${DOTNET_CHANNEL}"
sudo apt-get update
sudo apt-get install -y codium "dotnet-sdk-${DOTNET_CHANNEL}"

# ---------------------------------------------------------------- opencode
log "opencode"
command -v opencode >/dev/null || curl -fsSL https://opencode.ai/install | bash

# ---------------------------------------------------------------- yazi (terminal file manager)
log "yazi"
sudo apt-get install -y --no-install-recommends \
  fd-find ripgrep fzf zoxide jq poppler-utils ffmpegthumbnailer 7zip
mkdir -p ~/.local/bin                    # Debian's ~/.profile adds this to PATH if it exists
ln -sf /usr/bin/fdfind ~/.local/bin/fd   # Debian renames fd to fdfind; yazi looks for fd
if [[ ! -x ~/.local/bin/yazi ]]; then
  arch="$(uname -m)"                     # x86_64 or aarch64
  wget -qO /tmp/yazi.zip \
    "https://github.com/sxyazi/yazi/releases/latest/download/yazi-${arch}-unknown-linux-gnu.zip"
  unzip -qo /tmp/yazi.zip -d /tmp
  cp "/tmp/yazi-${arch}-unknown-linux-gnu/"{yazi,ya} ~/.local/bin/
  rm -rf /tmp/yazi.zip "/tmp/yazi-${arch}-unknown-linux-gnu"
fi

# `y` wrapper: quitting yazi leaves your shell in the last visited directory
if ! grep -q '# >>> yazi wrapper >>>' ~/.bashrc 2>/dev/null; then
  cat >> ~/.bashrc <<'EOF'

# >>> yazi wrapper >>>
function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}
# <<< yazi wrapper <<<
EOF
fi

# keybind: $mod+y opens yazi ($mod+e is already "layout toggle split" in sway's default config)
if [[ "$WM" == sway ]] && ! grep -q 'exec foot yazi' ~/.config/sway/config; then
  printf '\n# file manager\nbindsym $mod+y exec foot yazi\n' >> ~/.config/sway/config
fi

# ---------------------------------------------------------------- shell / session
log "Session autostart on tty1"
add_line() { grep -qxF "$1" ~/.profile 2>/dev/null || echo "$1" >> ~/.profile; }
add_line 'export DOTNET_CLI_TELEMETRY_OPTOUT=1'
add_line 'export ELECTRON_OZONE_PLATFORM_HINT=auto   # native Wayland for VSCodium'
add_line "[ -z \"\$WAYLAND_DISPLAY\" ] && [ \"\$(tty)\" = /dev/tty1 ] && exec $WM_CMD"

# ---------------------------------------------------------------- dotfiles (your stuff goes here)
# git clone https://github.com/<you>/dotfiles ~/.dotfiles && ~/.dotfiles/link.sh

log "Done. Reboot, log in on tty1, and $WM_CMD starts automatically."
