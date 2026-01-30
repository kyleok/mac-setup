# mac-setup

Automated Mac setup scripts using Syncthing for config sync and 1Password for secrets.

## How It Works

1. **bootstrap.sh** - Installs Homebrew, 1Password CLI, and Syncthing. Gets hub device ID from 1Password (or prompts manually)
2. Hub device (your always-on server) shares your config folder via Syncthing
3. **mac-setup.sh** - Installs apps, configures macOS settings, links personal configs from memex

The hub should have **introducer** enabled in Syncthing, so all other devices are discovered automatically.

## 1Password Integration

### Benefits
- **SSH keys in 1Password**: No private keys on disk, keys stay in your vault
- **Auto-retrieve Syncthing hub ID**: No manual copy-paste during bootstrap
- **Secure across devices**: Sign into 1Password once, SSH works everywhere

### Setup (One-Time)

1. **Store Syncthing hub device ID** (optional but convenient):
   ```bash
   op item create --category=login --title="Syncthing Hub" device_id="YOUR-HUB-DEVICE-ID"
   ```

2. **Add SSH keys to 1Password**:
   - Open 1Password app
   - Create new item > SSH Key
   - Import your existing key or generate a new one
   - Enable Settings > Developer > "Use SSH Agent"

3. **Add to your SSH config** (`~/.ssh/config`):
   ```
   Host *
       IdentityAgent ~/.1password/agent.sock
   ```

## Usage

### On Fresh Mac

```bash
# Download and run bootstrap (must download first, not pipe, for interactive prompts)
curl -fsSL https://raw.githubusercontent.com/kyleok/mac-setup/main/bootstrap.sh -o /tmp/bootstrap.sh
bash /tmp/bootstrap.sh
```

If signed into 1Password CLI, hub device ID is retrieved automatically. Otherwise, paste it when prompted.

### After Syncthing Syncs Your Config

```bash
~/Codebases/memex/scripts/mac-setup.sh
```

## Hub Setup (One-Time)

On your always-on server (e.g., homeserver):

1. In Syncthing GUI, edit the device and enable **Introducer**
2. Share your config folder with new devices
3. New devices will auto-discover all other devices via introducer

## Expected Folder Structure

The scripts expect your synced folder at `~/Codebases/memex` with:

```
memex/
├── .ssh/
│   ├── config              # SSH config (symlinked)
│   ├── known_hosts         # SSH known hosts (symlinked, synced across devices)
│   ├── id_ed25519          # SSH private key (symlinked, optional if using 1Password)
│   └── id_ed25519.pub      # SSH public key (symlinked)
├── config/
│   ├── gitconfig           # Personal git config (name, email) - included via git config
│   ├── zshrc               # Shell config (copied to ~/.zshrc)
│   ├── ghostty/
│   │   └── config          # Ghostty terminal config (symlinked)
│   └── claude/
│       ├── settings.json   # Claude Code settings (copied)
│       └── statusline-command.sh
└── scripts/                # These setup scripts
```

### Example memex/config/gitconfig

```ini
[user]
    name = Your Name
    email = you@example.com

# Optional: GPG signing
# [commit]
#     gpgsign = true
# [user]
#     signingkey = YOUR_KEY_ID
```

> **Note**: With 1Password SSH agent, you no longer need `id_ed25519` files in the synced folder. Keys live in your 1Password vault.

## What Gets Installed

### Public (in this repo)

**Homebrew formulas:** git, gh, jq, tmux, tree, node, pnpm, mas, ffmpeg, wget, watch, cmake, gemini-cli

**Homebrew casks:** Visual Studio Code, Claude Code, Antigravity, Ghostty, Obsidian, Discord, Brave Browser, Google Chrome, Docker, Tailscale, Slack

**From GitHub releases:** CodexBar (latest version)

**Mac App Store:** Amphetamine, Magnet

**Other:** uv (Python package manager), 1Password CLI (in bootstrap)

**macOS settings:**
- Finder: show hidden files, path bar, status bar, list view, folders first
- Keyboard: fast key repeat, disable press-and-hold
- Trackpad: tap to click
- Dock: minimize to app icon, hide recent apps
- Disable: auto-correct, auto-caps, smart quotes, smart dashes

### Private (from memex)

- Git identity (name, email)
- SSH config, keys, and known_hosts (synced across all devices)
- Shell config (zshrc)
- Ghostty config
- Claude Code settings

## Legacy Mode (No 1Password)

If you don't use 1Password, the scripts fall back to the legacy behavior:
- Bootstrap prompts for hub device ID manually
- mac-setup.sh symlinks SSH keys from `memex/.ssh/` (if present)

## Customization

Fork this repo and modify:
- `FORMULAS` and `CASKS` arrays in mac-setup.sh
- Mac App Store app IDs
- macOS defaults settings
- Paths if your synced folder is elsewhere

## License

MIT
