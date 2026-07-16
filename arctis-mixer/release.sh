#!/usr/bin/env bash

# Exit immediately on uncaught non-zero command status
set -eo pipefail

# ANSI color codes for rich scannable console logs
BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

# Sibling path configuration
AUR_DIR="../arctis-mixer-aur"
AUR_REPO_URL="ssh://aur@aur.archlinux.org/arctis-mixer.git"

echo -e "${BOLD}${BLUE}=====================================================${RESET}"
echo -e "${BOLD}${BLUE}      SteelSeries ChatMix Release Orchestration      ${RESET}"
echo -e "${BOLD}${BLUE}=====================================================${RESET}\n"

# ==============================================================================
# ONBOARDING GATE: Walks through first-time setups if AUR folder is missing
# ==============================================================================
if [ ! -d "$AUR_DIR" ]; then
    echo -e "${YELLOW}${BOLD}ℹ️ First-Run Detected! Sibling directory '$AUR_DIR' is missing.${RESET}"
    echo -e "This orchestrator will configure your AUR workspace now.\n"
    
    echo -e "${BOLD}Before proceeding, make sure you have:${RESET}"
    echo -e " 1. Registered an account on ${BLUE}https://aur.archlinux.org/${RESET}"
    echo -e " 2. Uploaded your public SSH key to your AUR profile settings."
    echo -e " 3. Added the corresponding private key to your local SSH agent.\n"
    
    read -p "Would you like to walk through the workspace setup now? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Aborting setup. Please resolve workspaces manually.${RESET}"
        exit 1
    fi

    echo -e "\n${BOLD}--- Checking local SSH Identity ---${RESET}"
    if ! ssh-add -l &>/dev/null; then
        echo -e "${YELLOW}⚠️ Your ssh-agent is running but has no loaded keys.${RESET}"
        echo -e "Attempting to add your default keys (ssh-add)..."
        ssh-add || {
            echo -e "${RED}Failed to load SSH keys. Please run 'ssh-add /path/to/key' manually before attempting again.${RESET}"
            exit 1
        }
    fi
    
    echo -e "\n${BOLD}--- Cloning AUR Repository ---${RESET}"
    echo -e "Cloning into: ${BLUE}$AUR_DIR${RESET}"
    
    # Run interactive clone. If it fails, give clean instructions.
    if ! git clone "$AUR_REPO_URL" "$AUR_DIR"; then
        echo -e "\n${RED}❌ Error: Failed to clone git repository from AUR.${RESET}"
        echo -e "This is usually due to missing AUR SSH registrations or incorrect repository names."
        echo -e "If you haven't submitted the package name on the AUR web UI yet, clone may fail."
        echo -e "We will initialize an empty, pre-configured repository for you instead."
        
        read -p "Initialize a local fallback repository workspace? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            mkdir -p "$AUR_DIR"
            cd "$AUR_DIR"
            git init
            git remote add origin "$AUR_REPO_URL"
            git checkout -b master
            cd - > /dev/null
            echo -e "${GREEN}Created local fallback at $AUR_DIR pointing to upstream $AUR_REPO_URL.${RESET}"
        else
            exit 1
        fi
    fi
    
    # Verify or copy default templates to local AUR workspace
    if [ ! -f "$AUR_DIR/PKGBUILD" ]; then
        echo -e "\n${YELLOW}Setting up default build templates inside the new AUR workspace...${RESET}"
        mkdir -p "$AUR_DIR"
        
        # Pull template files from upstream contrib directory
        if [ -d "contrib" ]; then
            cp contrib/arctis-mixer.service "$AUR_DIR/" 2>/dev/null || true
            cp contrib/99-arctis-mixer.rules "$AUR_DIR/" 2>/dev/null || true
            cp contrib/99-arctis-mixer.preset "$AUR_DIR/" 2>/dev/null || true
        fi
        
        # Write basic PKGBUILD boilerplate to build from source
        cat << 'EOF' > "$AUR_DIR/PKGBUILD"
# Maintainer: Raimo Geisel <your-email@domain.com>
pkgname=arctis-mixer
pkgver=0.1.0
pkgrel=1
pkgdesc="A zero-configuration native Rust utility for SteelSeries ChatMix dials on PipeWire"
arch=('x86_64')
url="https://github.com/yourusername/arctis-mixer"
license=('GPL3')
depends=('pipewire' 'libusb' 'hidapi')
makedepends=('cargo')
source=("git+https://github.com/yourusername/arctis-mixer.git"
        "arctis-mixer.service"
        "99-arctis-mixer.rules"
        "99-arctis-mixer.preset")
sha256sums=('SKIP' 'SKIP' 'SKIP' 'SKIP')

prepare() {
  cd "$srcdir/$pkgname"
  cargo fetch --locked --target "$CARCH-unknown-linux-gnu"
}

build() {
  cd "$srcdir/$pkgname"
  CARGO_TARGET_DIR=target cargo build --release --frozen
}

package() {
  install -Dm755 "$srcdir/$pkgname/target/release/arctis-mixer" "$pkgdir/usr/bin/arctis-mixer"
  install -Dm644 "$srcdir/arctis-mixer.service" "$pkgdir/usr/lib/systemd/user/arctis-mixer.service"
  install -Dm644 "$srcdir/99-arctis-mixer.preset" "$pkgdir/usr/lib/systemd/user-preset/99-arctis-mixer.preset"
  install -Dm644 "$srcdir/99-arctis-mixer.rules" "$pkgdir/usr/lib/udev/rules.d/99-arctis-mixer.rules"
}
EOF
        echo -e "${GREEN}Default local package configurations created inside the target AUR repository.${RESET}"
    fi
    
    echo -e "\n${GREEN}🎉 Workspace initialization complete! Ready to run your first release.${RESET}"
    echo -e "=====================================================\n"
fi

# ==============================================================================
# PIPELINE PHASE 1: PRE-FLIGHT CHECKS & COMPILING
# ==============================================================================
echo -e "${BOLD}--- [1/3] Running Cargo Verifications ---${RESET}"

echo -e "${YELLOW}Checking Cargo Formatting...${RESET}"
cargo fmt -- --check || {
    echo -e "${RED}Error: Code formatting check failed! Run 'cargo fmt' to fix.${RESET}"
    exit 1
}

echo -e "${YELLOW}Running Clippy Linters...${RESET}"
cargo clippy -- -D warnings || {
    echo -e "${RED}Error: Lints failed with errors. Aborting release pipeline.${RESET}"
    exit 1
}

echo -e "${YELLOW}Running tests...${RESET}"
cargo test || {
    echo -e "${RED}Error: Unit tests failed! Fix source code bugs before release.${RESET}"
    exit 1
}

echo -e "${YELLOW}Compiling optimized release binary...${RESET}"
cargo build --release

BINARY_PATH="target/release/arctis-mixer"
if [ -f "$BINARY_PATH" ]; then
    SIZE=$(du -h "$BINARY_PATH" | cut -f1)
    echo -e "${GREEN}✔ Release binary successfully generated! (${SIZE})${RESET}"
else
    echo -e "${RED}Error: Failed to find target binary at $BINARY_PATH.${RESET}"
    exit 1
fi

# Extract current version from Cargo.toml safely
CURRENT_VERSION=$(cargo metadata --no-deps --format-version 1 | grep -oP '"version":"\K[^"]+' | head -n1)
echo -e "\n${GREEN}Project version targeted for release: ${BOLD}${CURRENT_VERSION}${RESET}\n"

# Check Git clean state in our main working directory
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}Warning: You have uncommitted files in your project directory.${RESET}"
    read -p "Do you want to ignore this and proceed with publishing? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ==============================================================================
# PIPELINE PHASE 2: CRATES.IO PUBLISHING
# ==============================================================================
echo -e "\n${BOLD}--- [2/3] Crates.io Deployment ---${RESET}"
read -p "Publish version ${CURRENT_VERSION} to crates.io? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Publishing to crates.io registry...${RESET}"
    cargo publish || {
        echo -e "${RED}Error: Crates.io publication failed! Check network, API tokens, or package name uniqueness.${RESET}"
        exit 1
    }
    echo -e "${GREEN}✔ Crate successfully pushed!${RESET}"
else
    echo -e "${YELLOW}Skipping crates.io registry upload.${RESET}"
fi

# ==============================================================================
# PIPELINE PHASE 3: AUR PKGBUILD GENERATION & PUSH
# ==============================================================================
echo -e "\n${BOLD}--- [3/3] AUR Deployment ---${RESET}"
read -p "Sync code & push pkgver=${CURRENT_VERSION} to the AUR? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Ensure system configurations exist inside upstream repo contrib to copy them over
    if [ -d "contrib" ]; then
        echo "Copying configuration rules to AUR build-root..."
        cp contrib/arctis-mixer.service "$AUR_DIR/" 2>/dev/null || true
        cp contrib/99-arctis-mixer.rules "$AUR_DIR/" 2>/dev/null || true
        cp contrib/99-arctis-mixer.preset "$AUR_DIR/" 2>/dev/null || true
    fi

    echo "Updating pkgver inside build schema..."
    sed -i "s/^pkgver=.*/pkgver=${CURRENT_VERSION}/" "$AUR_DIR/PKGBUILD"

    # Step into AUR workspace
    cd "$AUR_DIR"

    # Update integrity checksum hashes on PKGBUILD using native Arch tool
    echo "Regenerating package hashes..."
    updpkgsums

    # Generate the updated metadata index needed by the AUR
    echo "Generating .SRCINFO metadata..."
    makepkg --printsrcinfo > .SRCINFO

    # Display changes for verification
    echo -e "\n${BOLD}AUR Workspace Status:${RESET}"
    git status -s

    read -p "Commit changes and push tag ${CURRENT_VERSION} directly to master? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git add PKGBUILD .SRCINFO 2>/dev/null || true
        git add arctis-mixer.service 99-arctis-mixer.rules 99-arctis-mixer.preset 2>/dev/null || true
        
        if git diff-index --quiet HEAD --; then
            echo -e "${YELLOW}Nothing has changed in the AUR build. Skipping Git push.${RESET}"
        else
            git commit -m "Release version ${CURRENT_VERSION}"
            echo -e "${YELLOW}Pushing upstream to AUR...${RESET}"
            git push origin master
            echo -e "${GREEN}✔ AUR package live at version ${CURRENT_VERSION}!${RESET}"
        fi
    else
        echo -e "${YELLOW}AUR git commit/push skipped.${RESET}"
    fi

    # Step back out to original project folder
    cd - > /dev/null
else
    echo -e "${YELLOW}Pipeline ended. AUR package unmodified.${RESET}"
fi

echo -e "\n${BOLD}${GREEN}=====================================================${RESET}"
echo -e "${BOLD}${GREEN}        Release Automation Finished Successfully!     ${RESET}"
echo -e "${BOLD}${GREEN}=====================================================${RESET}"