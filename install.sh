#!/usr/bin/env bash
#
# AI Config Installer
#
# Installs shell aliases so you can run ai-config from anywhere.
#
# Usage:
#   ./install.sh
#
# After installation:
#   ai-config --project=/path/to/project --with-all
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory (where ai-config is installed)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  AI Config Installer${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Detect shell
SHELL_NAME=$(basename "$SHELL")
case "$SHELL_NAME" in
  zsh)
    SHELL_RC="$HOME/.zshrc"
    ;;
  bash)
    if [[ -f "$HOME/.bash_profile" ]]; then
      SHELL_RC="$HOME/.bash_profile"
    else
      SHELL_RC="$HOME/.bashrc"
    fi
    ;;
  fish)
    SHELL_RC="$HOME/.config/fish/config.fish"
    ;;
  *)
    SHELL_RC="$HOME/.bashrc"
    echo -e "${YELLOW}Unknown shell: $SHELL_NAME. Defaulting to ~/.bashrc${NC}"
    ;;
esac

echo -e "${CYAN}Detected shell:${NC} $SHELL_NAME"
echo -e "${CYAN}Config file:${NC} $SHELL_RC"
echo ""

# Make scripts executable
echo -e "${CYAN}Making scripts executable...${NC}"
chmod +x "$SCRIPT_DIR/setup-project.sh"
chmod +x "$SCRIPT_DIR/serve-docs.sh"
[[ -f "$SCRIPT_DIR/install-vscode-extensions.sh" ]] && chmod +x "$SCRIPT_DIR/install-vscode-extensions.sh"
echo -e "  ${GREEN}✓${NC} Scripts are executable"
echo ""

# Check if aliases already exist
if grep -q "alias ai-config=" "$SHELL_RC" 2>/dev/null; then
  echo -e "${YELLOW}Aliases already exist in $SHELL_RC${NC}"
  echo ""
  read -p "Update aliases to point to this installation? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Remove old aliases
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' '/# AI Config/d' "$SHELL_RC"
      sed -i '' '/alias ai-config=/d' "$SHELL_RC"
      sed -i '' '/alias ai-config-docs=/d' "$SHELL_RC"
      sed -i '' '/export AI_CONFIG_REPO=/d' "$SHELL_RC"
    else
      sed -i '/# AI Config/d' "$SHELL_RC"
      sed -i '/alias ai-config=/d' "$SHELL_RC"
      sed -i '/alias ai-config-docs=/d' "$SHELL_RC"
      sed -i '/export AI_CONFIG_REPO=/d' "$SHELL_RC"
    fi
    echo -e "  ${GREEN}✓${NC} Removed old aliases"
  else
    echo -e "${YELLOW}Skipping alias installation${NC}"
    echo ""
    echo -e "${CYAN}You can manually add these to your shell config:${NC}"
    echo ""
    echo "  # AI Config"
    echo "  export AI_CONFIG_REPO=\"$SCRIPT_DIR\""
    echo "  alias ai-config=\"\$AI_CONFIG_REPO/setup-project.sh\""
    echo "  alias ai-config-docs=\"\$AI_CONFIG_REPO/serve-docs.sh\""
    echo ""
    exit 0
  fi
fi

# Add aliases
echo -e "${CYAN}Adding aliases to $SHELL_RC...${NC}"

if [[ "$SHELL_NAME" == "fish" ]]; then
  # Fish shell syntax
  cat >> "$SHELL_RC" << EOF

# AI Config - Universal AI Coding Assistant Configuration
set -gx AI_CONFIG_REPO "$SCRIPT_DIR"
alias ai-config "\$AI_CONFIG_REPO/setup-project.sh"
alias ai-config-docs "\$AI_CONFIG_REPO/serve-docs.sh"
EOF
else
  # Bash/Zsh syntax
  cat >> "$SHELL_RC" << EOF

# AI Config - Universal AI Coding Assistant Configuration
export AI_CONFIG_REPO="$SCRIPT_DIR"
alias ai-config="\$AI_CONFIG_REPO/setup-project.sh"
alias ai-config-docs="\$AI_CONFIG_REPO/serve-docs.sh"
EOF
fi

echo -e "  ${GREEN}✓${NC} Aliases added"
echo ""

# Install global Claude config if directories exist
if [[ -d "$SCRIPT_DIR/stacks" ]] || [[ -f "$SCRIPT_DIR/global/CLAUDE.md" ]]; then
  echo -e "${CYAN}Installing global Claude configuration...${NC}"
  CLAUDE_DIR="$HOME/.claude"
  mkdir -p "$CLAUDE_DIR"

  # Install stacks
  if [[ -d "$SCRIPT_DIR/stacks" ]]; then
    mkdir -p "$CLAUDE_DIR/stacks"
    STACK_COUNT=0
    for file in "$SCRIPT_DIR/stacks"/*.md; do
      if [[ -f "$file" ]]; then
        cp "$file" "$CLAUDE_DIR/stacks/"
        ((STACK_COUNT++))
      fi
    done
    [[ $STACK_COUNT -gt 0 ]] && echo -e "  ${GREEN}✓${NC} Installed $STACK_COUNT stack knowledge files"
  fi

  # Install global CLAUDE.md (only if it doesn't exist)
  if [[ -f "$SCRIPT_DIR/global/CLAUDE.md" ]] && [[ ! -f "$CLAUDE_DIR/CLAUDE.md" ]]; then
    cp "$SCRIPT_DIR/global/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
    echo -e "  ${GREEN}✓${NC} Installed global CLAUDE.md"
  fi
  echo ""
fi

# Summary
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}To start using ai-config, run:${NC}"
echo ""
echo -e "  ${YELLOW}source $SHELL_RC${NC}"
echo ""
echo -e "Or open a new terminal window."
echo ""
echo -e "${CYAN}Then configure any project:${NC}"
echo ""
echo -e "  ${YELLOW}ai-config --project=/path/to/project --with-all${NC}"
echo ""
echo -e "${CYAN}Quick examples:${NC}"
echo "  ai-config --project=. --with-all          # Current directory"
echo "  ai-config --refresh --project=.           # Update existing"
echo "  ai-config --project=. --with-all --dry-run  # Preview changes"
echo ""
echo -e "${CYAN}Documentation:${NC}"
echo "  ai-config-docs                            # Start docs server"
echo ""
