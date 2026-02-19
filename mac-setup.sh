#!/bin/bash
#
# Mac Setup Script
# Run AFTER memex has synced via Syncthing
#
# Prerequisites:
#   1. Run bootstrap.sh first (installs brew, syncthing, connects to hub)
#   2. Syncthing has synced memex to ~/Codebases/memex
#   3. Sign into Mac App Store (for mas installs)
#
# Usage:
#   ~/Codebases/memex/scripts/mac-setup.sh
#

set -e

# Prevent sleep for 2 hours during setup
caffeinate -d -t 7200 &
CAFFEINATE_PID=$!

# Ask for sudo password upfront and keep alive
echo "Requesting administrator access (one-time password prompt)..."
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Ensure Homebrew is in PATH (Apple Silicon or Intel)
if [ -f "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

MEMEX_DIR="$HOME/Codebases/memex"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }

# Check memex exists
if [ ! -d "$MEMEX_DIR" ]; then
    error "memex not found at $MEMEX_DIR. Run bootstrap.sh first and wait for sync."
fi

echo "=== Mac Setup ==="
echo ""

#######################################
# 0. Rosetta 2 (for Apple Silicon)
#######################################
if [[ "$(uname -m)" == "arm64" ]]; then
    if ! /usr/bin/pgrep -q oahd; then
        log "Installing Rosetta 2..."
        softwareupdate --install-rosetta --agree-to-license || warn "Rosetta 2 installation failed"
    else
        log "Rosetta 2 already installed"
    fi
fi
echo ""

#######################################
# 1. Homebrew Packages
#######################################
log "Installing Homebrew formulas..."

FORMULAS=(
    git
    gh
    jq
    tmux
    tree
    node
    pnpm
    mas
    ffmpeg
    wget
    watch
    cmake
    gemini-cli
    dockutil
    tectonic
)

for formula in "${FORMULAS[@]}"; do
    if ! brew list "$formula" &>/dev/null; then
        brew install "$formula" || warn "Failed to install $formula"
    fi
done

log "Installing Homebrew casks..."

CASKS=(
    visual-studio-code
    claude-code
    antigravity
    ghostty
    obsidian
    discord
    brave-browser
    google-chrome
    docker
    tailscale
    slack
)

for cask in "${CASKS[@]}"; do
    if ! brew list --cask "$cask" &>/dev/null 2>&1; then
        brew install --cask "$cask" || warn "Failed to install $cask"
    fi
done

#######################################
# 2. CodexBar (latest from GitHub)
#######################################
log "Installing CodexBar (latest from GitHub)..."

if [ -d "/Applications/CodexBar.app" ]; then
    log "CodexBar already installed, checking for updates..."
fi

# Get latest release info from GitHub API
CODEXBAR_RELEASE=$(curl -s "https://api.github.com/repos/steipete/CodexBar/releases/latest" 2>/dev/null || \
                   curl -s "https://api.github.com/repos/steipete/CodexBar/releases" | jq -r '.[0]')
CODEXBAR_VERSION=$(echo "$CODEXBAR_RELEASE" | jq -r '.tag_name // empty')
CODEXBAR_URL=$(echo "$CODEXBAR_RELEASE" | jq -r '.assets[] | select(.name | endswith(".zip") and (contains("dSYM") | not)) | .url' | head -1)

if [ -n "$CODEXBAR_URL" ] && [ -n "$CODEXBAR_VERSION" ]; then
    log "Found CodexBar $CODEXBAR_VERSION"

    # Download and install
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    curl -sL -H "Accept: application/octet-stream" "$CODEXBAR_URL" -o codexbar.zip
    unzip -q codexbar.zip

    # Remove old version if exists
    [ -d "/Applications/CodexBar.app" ] && rm -rf "/Applications/CodexBar.app"

    # Move to Applications
    mv CodexBar.app /Applications/

    # Cleanup
    cd - >/dev/null
    rm -rf "$TEMP_DIR"

    log "CodexBar $CODEXBAR_VERSION installed"
else
    warn "Could not fetch CodexBar release, install manually from https://github.com/steipete/CodexBar/releases"
fi

#######################################
# 3. macOS Settings
#######################################
log "Configuring macOS settings..."

# Finder: Show hidden files
defaults write com.apple.finder AppleShowAllFiles -bool true

# Finder: Show path bar
defaults write com.apple.finder ShowPathbar -bool true

# Finder: Show status bar
defaults write com.apple.finder ShowStatusBar -bool true

# Finder: Default to list view
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Finder: Keep folders on top when sorting by name
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# Disable press-and-hold for keys (enables key repeat)
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Fast key repeat rate
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Trackpad: Enable tap to click
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# Dock: Minimize windows into application icon
defaults write com.apple.dock minimize-to-application -bool true

# Dock: Don't show recent applications
defaults write com.apple.dock show-recents -bool false

# Dock: Remove unwanted default apps
log "Cleaning up Dock..."
REMOVE_FROM_DOCK=(
    "Maps"
    "Photos"
    "FaceTime"
    "Phone"
    "Contacts"
    "TV"
    "News"
    "Freeform"
    "iPhone Mirroring"
)

for app in "${REMOVE_FROM_DOCK[@]}"; do
    dockutil --remove "$app" --no-restart 2>/dev/null || true
done

# Screenshots: Save to Desktop
defaults write com.apple.screencapture location -string "$HOME/Desktop"

# Screenshots: Save as PNG
defaults write com.apple.screencapture type -string "png"

# Disable auto-correct
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# Disable auto-capitalization
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

# Disable smart quotes
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

# Disable smart dashes
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# Apply Finder changes
killall Finder 2>/dev/null || true

# Apply Dock changes
killall Dock 2>/dev/null || true

log "macOS settings configured"

#######################################
# 4. Mac App Store Apps
#######################################
log "Installing Mac App Store apps..."

mas_install() {
    local id=$1
    local name=$2
    if mas install "$id" 2>/dev/null; then
        log "Installed $name"
    else
        warn "Could not install $name (ID: $id) - install manually from App Store"
    fi
}

mas_install 937984704 "Amphetamine"
mas_install 441258766 "Magnet"

#######################################
# 5. uv (Python package manager)
#######################################
log "Checking uv..."
if ! command -v uv &>/dev/null; then
    log "Installing uv..."
    if ! curl -LsSf https://astral.sh/uv/install.sh | sh; then
        warn "Failed to install uv"
    else
        # Add to PATH for current script (verify check)
        . "$HOME/.local/bin/env" 2>/dev/null || true
    fi
fi

#######################################
# 6. Create directories
#######################################
mkdir -p ~/Codebases

#######################################
# 7. Git Configuration (from memex)
#######################################
log "Setting up Git..."

# Generic git settings (public)
git config --global init.defaultBranch main
git config --global push.autoSetupRemote true

# Personal git config from memex (private - name, email, signing, etc.)
if [ -f "$MEMEX_DIR/config/gitconfig" ]; then
    # Include memex gitconfig for personal settings
    git config --global include.path "$MEMEX_DIR/config/gitconfig"
    log "Linked personal Git config from memex"
else
    warn "No personal gitconfig at $MEMEX_DIR/config/gitconfig"
    warn "Create one with your name/email:"
    warn "  [user]"
    warn "      name = Your Name"
    warn "      email = you@example.com"
fi

#######################################
# 8. GitHub CLI Authentication
#######################################
log "Checking GitHub CLI..."

if ! gh auth status &>/dev/null 2>&1; then
    echo ""
    afplay /System/Library/Sounds/Ping.aiff 2>/dev/null &
    warn "GitHub CLI not authenticated"
    read -p "Authenticate GitHub CLI now? [Y/n]: " gh_auth </dev/tty
    if [[ ! "$gh_auth" =~ ^[Nn]$ ]]; then
        gh auth login
    else
        warn "Skipping GitHub auth - run 'gh auth login' later"
    fi
else
    log "GitHub CLI already authenticated"
fi

#######################################
# 9. SSH Setup (from memex)
#######################################
log "Setting up SSH..."

mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Symlink SSH config from memex
if [ -f "$MEMEX_DIR/.ssh/config" ]; then
    if [ ! -L ~/.ssh/config ] || [ "$(readlink ~/.ssh/config)" != "$MEMEX_DIR/.ssh/config" ]; then
        [ -f ~/.ssh/config ] && [ ! -L ~/.ssh/config ] && mv ~/.ssh/config ~/.ssh/config.bak
        ln -sf "$MEMEX_DIR/.ssh/config" ~/.ssh/config
        log "Symlinked SSH config from memex"
    fi
else
    warn "No SSH config at $MEMEX_DIR/.ssh/config"
fi

# Symlink SSH keys from memex (if not using 1Password SSH agent)
if [ -f "$MEMEX_DIR/.ssh/id_ed25519" ]; then
    chmod 600 "$MEMEX_DIR/.ssh/id_ed25519"

    if [ ! -L ~/.ssh/id_ed25519 ] || [ "$(readlink ~/.ssh/id_ed25519)" != "$MEMEX_DIR/.ssh/id_ed25519" ]; then
        [ -f ~/.ssh/id_ed25519 ] && [ ! -L ~/.ssh/id_ed25519 ] && mv ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.bak
        ln -sf "$MEMEX_DIR/.ssh/id_ed25519" ~/.ssh/id_ed25519
        log "Symlinked SSH private key from memex"
    fi

    if [ -f "$MEMEX_DIR/.ssh/id_ed25519.pub" ]; then
        if [ ! -L ~/.ssh/id_ed25519.pub ] || [ "$(readlink ~/.ssh/id_ed25519.pub)" != "$MEMEX_DIR/.ssh/id_ed25519.pub" ]; then
            ln -sf "$MEMEX_DIR/.ssh/id_ed25519.pub" ~/.ssh/id_ed25519.pub
            log "Symlinked SSH public key from memex"
        fi
    fi
else
    warn "No SSH key at $MEMEX_DIR/.ssh/id_ed25519 (OK if using 1Password SSH agent)"
fi

# Symlink authorized_keys from memex
if [ -f "$MEMEX_DIR/.ssh/authorized_keys" ]; then
    chmod 600 "$MEMEX_DIR/.ssh/authorized_keys"

    if [ ! -L ~/.ssh/authorized_keys ] || [ "$(readlink ~/.ssh/authorized_keys)" != "$MEMEX_DIR/.ssh/authorized_keys" ]; then
        [ -f ~/.ssh/authorized_keys ] && [ ! -L ~/.ssh/authorized_keys ] && mv ~/.ssh/authorized_keys ~/.ssh/authorized_keys.bak
        ln -sf "$MEMEX_DIR/.ssh/authorized_keys" ~/.ssh/authorized_keys
        log "Symlinked authorized_keys from memex"
    fi
else
    warn "No authorized_keys at $MEMEX_DIR/.ssh/authorized_keys"
fi

# Symlink known_hosts from memex (synced across all devices)
if [ -f "$MEMEX_DIR/.ssh/known_hosts" ]; then
    chmod 600 "$MEMEX_DIR/.ssh/known_hosts"

    if [ ! -L ~/.ssh/known_hosts ] || [ "$(readlink ~/.ssh/known_hosts)" != "$MEMEX_DIR/.ssh/known_hosts" ]; then
        [ -f ~/.ssh/known_hosts ] && [ ! -L ~/.ssh/known_hosts ] && mv ~/.ssh/known_hosts ~/.ssh/known_hosts.bak
        ln -sf "$MEMEX_DIR/.ssh/known_hosts" ~/.ssh/known_hosts
        log "Symlinked SSH known_hosts from memex"
    fi
else
    warn "No SSH known_hosts at $MEMEX_DIR/.ssh/known_hosts (will be created on first connection)"
fi

#######################################
# 10. Shell Configuration (from memex)
#######################################
log "Setting up shell..."

ZSHRC="$HOME/.zshrc"
[ -f "$ZSHRC" ] && [ ! -L "$ZSHRC" ] && cp "$ZSHRC" "$ZSHRC.bak"

if [ -f "$MEMEX_DIR/config/zshrc" ]; then
    cp "$MEMEX_DIR/config/zshrc" "$ZSHRC"
    log "Copied zshrc from memex"
else
    # Create minimal zshrc
    cat > "$ZSHRC" << 'EOF'
# PATH
export PATH="$HOME/.local/bin:$PATH"

# Homebrew (Apple Silicon or Intel)
if [ -f "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# uv
. "$HOME/.local/bin/env" 2>/dev/null || true

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# Aliases
alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
EOF
    log "Created minimal ~/.zshrc (customize in memex/config/zshrc)"
fi

#######################################
# 11. Claude Code Setup (from memex)
#######################################
log "Setting up Claude Code..."

mkdir -p ~/.claude

if [ -f "$MEMEX_DIR/config/claude/settings.json" ]; then
    cp "$MEMEX_DIR/config/claude/settings.json" ~/.claude/settings.json
    log "Copied Claude settings from memex"
fi

if [ -f "$MEMEX_DIR/config/claude/statusline-command.sh" ]; then
    cp "$MEMEX_DIR/config/claude/statusline-command.sh" ~/.claude/statusline-command.sh
    chmod +x ~/.claude/statusline-command.sh
    log "Copied Claude statusline script from memex"
fi

#######################################
# 12. Ghostty Configuration (from memex)
#######################################
log "Setting up Ghostty..."

mkdir -p ~/.config/ghostty

if [ -f "$MEMEX_DIR/config/ghostty/config" ]; then
    ln -sf "$MEMEX_DIR/config/ghostty/config" ~/.config/ghostty/config
    log "Symlinked Ghostty config from memex"
else
    warn "No Ghostty config at $MEMEX_DIR/config/ghostty/config"
fi

#######################################
# 13. Remote Access (optional)
#######################################
echo ""
afplay /System/Library/Sounds/Ping.aiff 2>/dev/null &
read -p "Enable SSH and Screen Sharing? [y/N]: " enable_remote </dev/tty
if [[ "$enable_remote" =~ ^[Yy]$ ]]; then
    log "Enabling SSH (Remote Login)..."
    if ! sudo systemsetup -setremotelogin on 2>/dev/null; then
        warn "CLI method failed (needs Full Disk Access)"
        warn "Opening System Settings > General > Sharing..."
        open "x-apple.systempreferences:com.apple.Sharing-Settings.extension" 2>/dev/null || true
        echo "  Please enable 'Remote Login' and 'Screen Sharing' manually"
        read -p "Press Enter when done..." </dev/tty
    else
        log "Enabling Screen Sharing (VNC)..."
        sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || warn "Failed to enable Screen Sharing"
        log "Remote access enabled"
    fi
fi

#######################################
# 14. Tailscale Setup
#######################################
echo ""
log "Setting up Tailscale..."

open -a "Tailscale" 2>/dev/null || true
sleep 2

if /Applications/Tailscale.app/Contents/MacOS/Tailscale status &>/dev/null 2>&1; then
    log "Tailscale already connected"
else
    afplay /System/Library/Sounds/Ping.aiff 2>/dev/null &
    read -p "Connect to Tailscale now? [Y/n]: " ts_auth </dev/tty
    if [[ ! "$ts_auth" =~ ^[Nn]$ ]]; then
        /Applications/Tailscale.app/Contents/MacOS/Tailscale up
    else
        warn "Skipping Tailscale - run 'tailscale up' later"
    fi
fi

#######################################
# 15. Hostname (optional)
#######################################
echo ""
afplay /System/Library/Sounds/Ping.aiff 2>/dev/null &
current_hostname=$(scutil --get ComputerName 2>/dev/null || hostname)
echo "Current hostname: $current_hostname"
read -p "Set new hostname? (e.g., M4, MBP) [press Enter to skip]: " new_hostname </dev/tty
if [ -n "$new_hostname" ]; then
    sudo scutil --set ComputerName "$new_hostname"
    sudo scutil --set HostName "$new_hostname"
    sudo scutil --set LocalHostName "$new_hostname"
    log "Hostname set to: $new_hostname"
fi

#######################################
# 16. Verification
#######################################
echo ""
log "Verifying setup..."

verify() {
    local name=$1
    local cmd=$2
    if eval "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $name"
        return 0
    else
        echo -e "  ${RED}✗${NC} $name"
        return 1
    fi
}

verify "Homebrew" "command -v brew"
verify "Git" "command -v git"
verify "GitHub CLI" "command -v gh"
verify "GitHub CLI auth" "gh auth status"
verify "1Password CLI" "command -v op"
verify "uv" "command -v uv"
verify "dockutil" "command -v dockutil"
verify "Syncthing" "brew services list | grep -q syncthing"
verify "CodexBar" "[ -d '/Applications/CodexBar.app' ]"
verify "SSH config" "[ -f ~/.ssh/config ]"
verify "zshrc" "[ -f ~/.zshrc ]"
verify "Ghostty config" "[ -f ~/.config/ghostty/config ] || [ -L ~/.config/ghostty/config ]"
verify "Tailscale" "/Applications/Tailscale.app/Contents/MacOS/Tailscale status"

if ssh -o BatchMode=yes -o ConnectTimeout=3 n100 'echo ok' &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} SSH to n100"
else
    echo -e "  ${YELLOW}?${NC} SSH to n100 (may need Tailscale)"
fi

#######################################
# Done
#######################################
echo ""
afplay /System/Library/Sounds/Ping.aiff 2>/dev/null &
log "==========================================="
log "Setup complete!"
log "==========================================="
echo ""

warn "Manual installs needed:"
echo "  - Microsoft Office"
echo "  - Any other apps"
echo ""
echo "Then:"
echo "  - Restart terminal or: source ~/.zshrc"
echo ""

kill $CAFFEINATE_PID 2>/dev/null || true
open -a "Amphetamine" 2>/dev/null || true
