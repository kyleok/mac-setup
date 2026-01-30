#!/bin/bash
#
# Bootstrap Script - Run on fresh Mac BEFORE memex exists
#
# This script:
#   1. Installs Homebrew
#   2. Installs 1Password CLI (optional, for auto-config)
#   3. Installs Syncthing + jq
#   4. Starts Syncthing
#   5. Gets hub device ID (from 1Password or manual entry)
#   6. Configures Syncthing with correct folder path
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/kyleok/mac-setup/main/bootstrap.sh -o /tmp/bootstrap.sh
#   bash /tmp/bootstrap.sh
#
# IMPORTANT: Hub (N100) must have folder with ID "memex" (exact match required)
#
# 1Password Setup (optional, but recommended):
#   Store your hub's Syncthing device ID in 1Password:
#     op item create --category=login --title="Syncthing Hub" device_id="YOUR-DEVICE-ID"
#

set -e

echo "=== Mac Bootstrap ==="
echo ""

# Ask for sudo password upfront and keep alive
echo "Requesting administrator access (one-time password prompt)..."
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# 1. Xcode CLI
echo "[1/7] Checking Xcode Command Line Tools..."
if ! xcode-select -p &>/dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
    echo ""
    echo "Waiting for Xcode Command Line Tools installation..."
    # Wait for installation to complete (not just dialog to open)
    while ! xcode-select -p &>/dev/null; do
        sleep 5
    done
fi
echo "OK"

# 2. Homebrew
echo "[2/7] Checking Homebrew..."
if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add to path for this session (Apple Silicon or Intel)
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    elif [ -f "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
    fi
fi
echo "OK"

# 3. 1Password (optional but enables auto-config)
echo "[3/7] Setting up 1Password..."
OP_AVAILABLE=false

echo "Installing 1Password app and CLI..."
brew install --cask 1password 2>/dev/null || echo "Note: 1Password app may already be installed"
brew install --cask 1password-cli 2>/dev/null || echo "Note: 1Password CLI may already be installed"

# Alert user with sound
afplay /System/Library/Sounds/Ping.aiff 2>/dev/null &

echo ""
echo "Please set up 1Password:"
echo "  1. Open 1Password app"
echo "  2. Sign in to your account"
echo "  3. Go to Settings > Developer > Enable 'Integrate with 1Password CLI'"
echo ""
open -a "1Password" 2>/dev/null || true
read -p "Press Enter when done (or 's' to skip): " op_setup </dev/tty

if [[ "$op_setup" =~ ^[Ss]$ ]]; then
    echo "Skipping 1Password setup..."
fi

if command -v op &>/dev/null; then
    echo "1Password CLI installed. Checking sign-in status..."
    # Try to verify we're signed in
    if op account list &>/dev/null 2>&1; then
        OP_AVAILABLE=true
        echo "1Password CLI ready"
    else
        echo ""
        echo "1Password CLI is installed but not signed in."
        echo "To enable automatic config retrieval, sign in with:"
        echo "  eval \$(op signin)"
        echo ""
        read -p "Sign in now? [y/N]: " signin_choice </dev/tty
        if [[ "$signin_choice" =~ ^[Yy]$ ]]; then
            if eval $(op signin); then
                OP_AVAILABLE=true
                echo "Signed in to 1Password"
            else
                echo "Sign-in failed, continuing with manual entry..."
            fi
        fi
    fi
else
    echo "1Password CLI not available, will use manual entry"
fi
echo "OK"

# 4. Syncthing + jq
echo "[4/7] Installing Syncthing and jq..."
brew install syncthing jq || { echo "Error: brew install failed"; exit 1; }
echo "OK"

# 5. Start Syncthing
echo "[5/7] Starting Syncthing..."
brew services start syncthing

# Wait for config to be created (with retry)
echo "Waiting for Syncthing to initialize..."
CONFIG="$HOME/Library/Application Support/Syncthing/config.xml"
for i in {1..30}; do
    [ -f "$CONFIG" ] && break
    sleep 1
done

if [ ! -f "$CONFIG" ]; then
    echo "Error: Syncthing config not found after 30s."
    echo "Try opening http://localhost:8384 manually."
    exit 1
fi

# Extract API key (try xmllint first, fall back to sed)
if command -v xmllint &>/dev/null; then
    API_KEY=$(xmllint --xpath "string(//configuration/gui/apikey)" "$CONFIG" 2>/dev/null)
fi
if [ -z "$API_KEY" ]; then
    API_KEY=$(sed -n "s/.*<apikey>\([^<]*\)<\/apikey>.*/\1/p" "$CONFIG")
fi

if [ -z "$API_KEY" ]; then
    echo "Error: Could not extract Syncthing API key"
    exit 1
fi

# Wait for API to be ready
for i in {1..10}; do
    MY_ID=$(curl -s -H "X-API-Key: $API_KEY" "http://localhost:8384/rest/system/status" 2>/dev/null | jq -r '.myID // empty')
    [ -n "$MY_ID" ] && break
    sleep 1
done

if [ -z "$MY_ID" ]; then
    echo "Error: Could not get device ID from Syncthing API."
    exit 1
fi

echo "OK"
echo ""
echo "This device's ID:"
echo "$MY_ID"
echo ""

# 6. Get hub device ID
echo "[6/7] Configure hub connection"
echo ""

HUB_ID=""

# Try to get from 1Password first
if [ "$OP_AVAILABLE" = true ]; then
    echo "Checking 1Password for Syncthing Hub device ID..."
    HUB_ID=$(op item get "Syncthing Hub" --fields device_id --reveal 2>/dev/null || true)
    if [ -n "$HUB_ID" ]; then
        echo "Found hub device ID in 1Password!"
    else
        echo "No 'Syncthing Hub' item found in 1Password."
        echo "To store it for next time:"
        echo "  op item create --category=login --title=\"Syncthing Hub\" device_id=\"YOUR-ID\""
        echo ""
    fi
fi

# Fall back to manual entry if not found
if [ -z "$HUB_ID" ]; then
    echo "Enter your hub device ID (e.g., N100 homeserver)."
    echo "This device will sync your config folder from the hub."
    echo ""
    read -p "Hub Device ID: " HUB_ID </dev/tty
fi

if [ -z "$HUB_ID" ]; then
    echo "No hub ID provided. Configure Syncthing manually at http://localhost:8384"
    exit 0
fi

# Validate format
if [[ ! "$HUB_ID" =~ ^[A-Z0-9]{7}-[A-Z0-9]{7}-[A-Z0-9]{7}-[A-Z0-9]{7}-[A-Z0-9]{7}-[A-Z0-9]{7}-[A-Z0-9]{7}-[A-Z0-9]{7}$ ]]; then
    echo "Warning: ID format looks unusual, but continuing anyway..."
fi

# Check if device already exists
existing_devices=$(curl -s -H "X-API-Key: $API_KEY" "http://localhost:8384/rest/config/devices" 2>/dev/null)
if echo "$existing_devices" | jq -e ".[] | select(.deviceID == \"$HUB_ID\")" &>/dev/null; then
    echo "Hub device already configured, skipping..."
else
    echo ""
    echo "Adding hub device..."

    # Add hub device (introducer so we discover other devices)
    response=$(curl -s -X POST -H "X-API-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        "http://localhost:8384/rest/config/devices" \
        -d "{
            \"deviceID\": \"$HUB_ID\",
            \"name\": \"Hub\",
            \"introducer\": true,
            \"autoAcceptFolders\": true
        }" 2>&1)

    if echo "$response" | jq -e '.error' &>/dev/null; then
        echo "Error adding device: $(echo "$response" | jq -r '.error')"
        exit 1
    fi
    echo "Hub device added."
fi

# 7. Pre-create memex folder config
echo "[7/7] Setting up memex folder..."

MEMEX_PATH="$HOME/Codebases/memex"
mkdir -p "$MEMEX_PATH"

# Check if folder already exists
existing_folders=$(curl -s -H "X-API-Key: $API_KEY" "http://localhost:8384/rest/config/folders" 2>/dev/null)
if echo "$existing_folders" | jq -e '.[] | select(.id == "memex")' &>/dev/null; then
    echo "Folder 'memex' already configured, skipping..."
else
    # Add folder config pointing to the correct path
    # IMPORTANT: folder ID must be "memex" to match hub's folder ID
    response=$(curl -s -X POST -H "X-API-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        "http://localhost:8384/rest/config/folders" \
        -d "{
            \"id\": \"memex\",
            \"label\": \"memex\",
            \"path\": \"$MEMEX_PATH\",
            \"devices\": [{\"deviceID\": \"$HUB_ID\"}],
            \"type\": \"sendreceive\"
        }" 2>&1)

    if echo "$response" | jq -e '.error' &>/dev/null; then
        echo "Error adding folder: $(echo "$response" | jq -r '.error')"
        exit 1
    fi
    echo "Folder configured at: $MEMEX_PATH"
fi

echo ""
echo "==========================================="
echo "BOOTSTRAP COMPLETE"
echo "==========================================="
echo ""
echo "Next step - FROM ANOTHER MAC (MBP/M4/M1), run:"
echo ""
echo "  ssh n100 '~/bin/syncthing-add-device.sh $MY_ID'"
echo ""
echo "Then wait for sync. Opening Syncthing UI..."
echo ""

# Open Syncthing web UI
open "http://localhost:8384" 2>/dev/null || true

# Optional: wait for sync
while true; do
    status=$(curl -s -H "X-API-Key: $API_KEY" "http://localhost:8384/rest/db/status?folder=memex" 2>/dev/null)

    # Check if response is valid JSON
    if ! echo "$status" | jq -e . >/dev/null 2>&1; then
        printf "\rWaiting for Syncthing API...                                        "
        sleep 3
        continue
    fi

    state=$(echo "$status" | jq -r '.state // "unknown"')
    need=$(echo "$status" | jq -r '.needFiles // 0')

    if [ "$state" = "idle" ] && [ "$need" = "0" ]; then
        global=$(echo "$status" | jq -r '.globalFiles // 0')
        if [ "$global" -gt "0" ]; then
            afplay /System/Library/Sounds/Ping.aiff 2>/dev/null &
            echo ""
            echo "Sync complete! ($global files)"
            echo ""
            echo "Now run:"
            echo "  ~/Codebases/memex/scripts/mac-setup.sh"
            break
        fi
    fi

    printf "\rStatus: %-12s Need: %-6s (waiting for hub to share folder...)" "$state" "$need"
    sleep 3
done
