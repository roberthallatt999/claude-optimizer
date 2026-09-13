#!/bin/bash
#
# setup-project.sh
# Deploy AI coding assistant configuration to any project
#
# Usage:
#   ./setup-project.sh --project=/path/to/project [options]
#   ./setup-project.sh --stack=expressionengine --project=/path/to/project [options]
#
# Options:
#   --stack       Stack template (auto-detected if not specified)
#   --project     Target project directory
#   --name        Human-readable project name (optional, derived from directory if not provided)
#   --slug        Project slug for templates (optional, derived from directory if not provided)
#   --dry-run     Show what would be done without making changes
#   --force       Overwrite existing configuration without prompting
#   --clean       Remove existing Claude/AI config before deploying
#   --refresh     Regenerate CLAUDE.md and merge settings.local.json (preserves .claude/ customizations)
#   --analyze           Generate analysis prompt for AI to build custom config
#   --discover          AI-powered analysis mode for unknown/custom stacks
#   --no-response-style Skip the concise Response Style block in CLAUDE.md
#   --eager-libraries   Keep @imports of .claude/libraries (default: on-demand references)
#   --effort=<level>    Set effortLevel in settings.local.json
#   --okf-memory        Project memory as an Open Knowledge Format bundle (.okf/)
#   --doctor            Read-only prerequisite and health check of a deployed project
#   --install-deps      Install missing tools via the system package manager before deploying
#   --shared-policy     Also write the safety policy to committed .claude/settings.json
#   --uninstall         Remove ai-config from a project (additive-safe, backed up)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory (where claude-optimizer repo lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cross-platform sed in-place editing (macOS uses -i '', Linux uses -i)
sed_inplace() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Default values
STACK=""
PROJECT_DIR=""
PROJECT_NAME=""
PROJECT_SLUG=""
DRY_RUN=false
FORCE=false
CLEAN=false
REFRESH=false
ANALYZE=false
DISCOVER=false
SKIP_VSCODE=false
INSTALL_EXTENSIONS=false
WITH_SUPERPOWERS=true          # Enabled by default
WITH_OPENAI=false              # Disabled by default; use --with-openai to enable
WITH_ORCHESTRATOR=false        # Disabled by default; use --orchestrator to enable
SKIP_SUPERPOWERS_UPDATE=false  # Auto-update the superpowers subtree before deploy; --skip-superpowers-update opts out
NO_RESPONSE_STYLE=false        # Concise Response Style block is appended by default; --no-response-style opts out
EAGER_LIBRARIES=false          # Library references are on-demand by default; --eager-libraries keeps @imports
APPLY_PENDING=false            # --apply-pending adopts staged new versions of edited files (with backups)
OKF_MEMORY=false               # --okf-memory records project memory as an OKF bundle in .okf/ (sticky)
DOCTOR=false                   # --doctor runs the read-only prerequisite and health check, then exits
INSTALL_DEPS=false             # --install-deps installs missing tools via the system package manager (and npm)
SHARED_POLICY=false            # --shared-policy also writes the safety policy to committed .claude/settings.json (sticky)
UNINSTALL=false                # --uninstall removes ai-config from the project (everything removed is backed up)
RUN_MODE=deploy                # deploy | refresh | uninstall — recorded in .claude/ai-config/version
EFFORT_LEVEL=""                # Optional --effort=<low|medium|high|xhigh|max> → effortLevel in settings.local.json
SUPERPOWERS_MODE=""            # all, core, minimal, custom
SUPERPOWERS_CUSTOM_SKILLS=""   # comma-separated skill names

# Detected values (populated during analysis)
DDEV_NAME=""
DDEV_DOCROOT=""
DDEV_PHP=""
DDEV_DB_TYPE=""
DDEV_DB_VERSION=""
TEMPLATE_GROUP=""
HAS_TAILWIND=false
HAS_ALPINE=false
HAS_FOUNDATION=false
HAS_SCSS=false
HAS_VANILLA_JS=false
HAS_STASH=false
HAS_STRUCTURE=false
HAS_BILINGUAL=false
# Modern web tooling detection
HAS_TYPESCRIPT=false
HAS_ZUSTAND=false
HAS_TANSTACK_QUERY=false
HAS_PRISMA=false
HAS_SUPABASE=false
HAS_TRPC=false
HAS_VITEST=false
HAS_PLAYWRIGHT=false
HAS_FRAMER_MOTION=false
HAS_SHADCN=false
HAS_ZOD=false
HAS_PINIA=false
HAS_TINA=false
# Front-end libraries with reference docs in libraries/ (set from detect-frontend.sh)
HAS_BOOTSTRAP=false
HAS_BULMA=false
HAS_JQUERY=false
HAS_MUI=false
FRONTEND_RECORDS=""      # detect-frontend.sh output (lib / custom records)
FRONTEND_BLOCK_FILE=""   # generated Front-End Stack block for CLAUDE.md / AGENTS.md
FRONTEND_TMP_DIR=""

# Brand colors (set manually; unset ones render as readable "not set" text)
# shellcheck disable=SC2034  # read indirectly by render_template via ${!var}
BRAND_GREEN="" BRAND_BLUE="" BRAND_ORANGE="" BRAND_LIGHT_GREEN=""

# Git branch detection
GIT_MAIN_BRANCH=""
GIT_INTEGRATION_BRANCH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --stack=*)
      STACK="${1#*=}"
      shift
      ;;
    --project=*)
      PROJECT_DIR="${1#*=}"
      shift
      ;;
    --name=*)
      PROJECT_NAME="${1#*=}"
      shift
      ;;
    --slug=*)
      PROJECT_SLUG="${1#*=}"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --clean)
      CLEAN=true
      shift
      ;;
    --refresh)
      REFRESH=true
      shift
      ;;
    --analyze)
      ANALYZE=true
      shift
      ;;
    --discover)
      DISCOVER=true
      shift
      ;;
    --skip-vscode)
      SKIP_VSCODE=true
      shift
      ;;
    --install-extensions)
      INSTALL_EXTENSIONS=true
      shift
      ;;
    --with-superpowers)
      WITH_SUPERPOWERS=true
      shift
      ;;
    --superpowers-all)
      WITH_SUPERPOWERS=true
      SUPERPOWERS_MODE="all"
      shift
      ;;
    --superpowers-core)
      WITH_SUPERPOWERS=true
      SUPERPOWERS_MODE="core"
      shift
      ;;
    --superpowers-minimal)
      WITH_SUPERPOWERS=true
      SUPERPOWERS_MODE="minimal"
      shift
      ;;
    --superpowers-skill=*)
      WITH_SUPERPOWERS=true
      SUPERPOWERS_MODE="custom"
      SUPERPOWERS_CUSTOM_SKILLS="${1#*=}"
      shift
      ;;
    --no-superpowers)
      WITH_SUPERPOWERS=false
      shift
      ;;
    --with-openai)
      WITH_OPENAI=true
      shift
      ;;
    --orchestrator)
      WITH_ORCHESTRATOR=true
      shift
      ;;
    --skip-superpowers-update)
      SKIP_SUPERPOWERS_UPDATE=true
      shift
      ;;
    --no-response-style)
      NO_RESPONSE_STYLE=true
      shift
      ;;
    --eager-libraries)
      EAGER_LIBRARIES=true
      shift
      ;;
    --effort=*)
      EFFORT_LEVEL="${1#*=}"
      shift
      ;;
    --apply-pending)
      APPLY_PENDING=true
      shift
      ;;
    --okf-memory)
      OKF_MEMORY=true
      shift
      ;;
    --doctor)
      DOCTOR=true
      shift
      ;;
    --install-deps)
      INSTALL_DEPS=true
      shift
      ;;
    --shared-policy)
      SHARED_POLICY=true
      shift
      ;;
    --uninstall)
      UNINSTALL=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 --project=<path> [options]"
      echo ""
      echo "Options:"
      echo "  --stack=<n>       Stack template (auto-detected if not specified)"
      echo "  --project=<path>  Target project directory (required)"
      echo "  --discover        AI-powered mode: analyze codebase and generate custom config"
      echo "  --name=<n>        Human-readable project name"
      echo "  --slug=<slug>     Project slug for templates"
      echo "  --dry-run         Preview changes without applying"
      echo "  --force           Overwrite existing config without prompting"
      echo "  --clean           Remove existing config before deploying (fresh start)"
      echo "  --refresh         Update config files (auto-detects stack from CLAUDE.md)"
      echo "                    Additive: edited files are kept, new versions staged in"
      echo "                    .claude/ai-config/pending/, modified files backed up"
      echo "  --apply-pending   Adopt staged new versions of files you edited (backs up first)"
      echo "  --doctor          Check prerequisites and verify the deployed config works (read-only)"
      echo "  --install-deps    Install missing tools first (jq, git, …; Intelephense for PHP stacks)"
      echo "                    via brew/apt-get/dnf/yum/pacman/zypper/apk; asks first unless --force"
      echo "  --shared-policy   Also put the safety policy in committed .claude/settings.json for teammates"
      echo "  --uninstall       Remove ai-config from the project (edited files kept; all removals backed up)"
      echo ""
      echo "Superpowers Skills (enabled by default):"
      echo "  --no-superpowers        Disable Superpowers skills system"
      echo "  --superpowers-all       Deploy all skills (default when enabled)"
      echo "  --superpowers-core      Deploy core skills only (TDD, debugging, brainstorming)"
      echo "  --superpowers-minimal   Deploy only the bootstrap skill"
      echo "  --superpowers-skill=X   Deploy specific skills (comma-separated)"
      echo "  --skip-superpowers-update  Don't pull the latest superpowers subtree before deploying"
      echo ""
      echo "OpenAI / API tools:"
      echo "  --with-openai           Deploy AGENTS.md for OpenAI Codex and API tools"
      echo ""
      echo "Model orchestration:"
      echo "  --orchestrator          Opus orchestrator + Sonnet implementer setup:"
      echo "                          pins the main session to Opus, forces all subagents"
      echo "                          to Sonnet, and deploys an 'implementer' subagent"
      echo ""
      echo "Token & cost:"
      echo "  --no-response-style     Don't add the concise Response Style block to CLAUDE.md"
      echo "  --eager-libraries       Keep @imports of .claude/libraries (loads them every session)"
      echo "  --effort=<level>        Set effortLevel (low|medium|high|xhigh|max) in settings.local.json"
      echo "  --okf-memory            Record project memory as an OKF bundle in .okf/ instead of MEMORY.md"
      echo ""
      echo "VSCode:"
      echo "  --skip-vscode           Skip VSCode settings deployment"
      echo "  --install-extensions    Auto-install recommended VSCode extensions"
      echo ""
      echo "Other:"
      echo "  --analyze         Generate analysis prompt for Claude"
      echo ""
      echo "Available stacks:"
      ls -1 "$SCRIPT_DIR/projects/" 2>/dev/null | sed 's/^/  - /'
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

# Validation and auto-detection
if [[ -z "$PROJECT_DIR" ]]; then
  echo -e "${RED}Error: --project is required${NC}"
  exit 1
fi

if [[ -n "$EFFORT_LEVEL" ]] && [[ ! "$EFFORT_LEVEL" =~ ^(low|medium|high|xhigh|max)$ ]]; then
  echo -e "${RED}Error: --effort must be one of: low, medium, high, xhigh, max${NC}"
  exit 1
fi

# Resolve project directory to absolute path
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || {
  echo -e "${RED}Error: Project directory does not exist: $PROJECT_DIR${NC}"
  exit 1
}

# Auto-detect stack if not specified
if [[ -z "$STACK" ]]; then
  # First try: Check existing CLAUDE.md (for --refresh)
  if [[ -f "$PROJECT_DIR/CLAUDE.md" ]]; then
    DETECTED_STACK=$(grep '@~/.claude/stacks/' "$PROJECT_DIR/CLAUDE.md" 2>/dev/null | head -1 | sed -E 's|.*@~/.claude/stacks/([^.]+)\.md.*|\1|')
    if [[ -n "$DETECTED_STACK" ]]; then
      STACK="$DETECTED_STACK"
      echo -e "${CYAN}Auto-detected stack from CLAUDE.md: ${GREEN}$STACK${NC}"
    fi
  fi

  # Second try: Detect from project files
  if [[ -z "$STACK" ]]; then
    # ExpressionEngine (check for headless Coilpack + Next.js first)
    if [[ -d "$PROJECT_DIR/system/ee" ]] || [[ -f "$PROJECT_DIR/system/user/config/config.php" ]]; then
      if [[ -f "$PROJECT_DIR/composer.json" ]] && grep -q "laravel/framework" "$PROJECT_DIR/composer.json" 2>/dev/null; then
        if [[ -f "$PROJECT_DIR/frontend/next.config.js" ]] || [[ -f "$PROJECT_DIR/frontend/next.config.mjs" ]] || [[ -f "$PROJECT_DIR/frontend/next.config.ts" ]]; then
          STACK="ee-nextjs"
        else
          STACK="coilpack"
        fi
      else
        STACK="expressionengine"
      fi
    # Craft CMS (check for headless variants first)
    elif [[ -f "$PROJECT_DIR/craft" ]] && [[ -f "$PROJECT_DIR/composer.json" ]] && grep -q "craftcms/cms" "$PROJECT_DIR/composer.json" 2>/dev/null; then
      if [[ -f "$PROJECT_DIR/frontend/nuxt.config.ts" ]] || [[ -f "$PROJECT_DIR/frontend/nuxt.config.js" ]]; then
        STACK="craftcms-nuxt"
      elif [[ -f "$PROJECT_DIR/frontend/next.config.js" ]] || [[ -f "$PROJECT_DIR/frontend/next.config.mjs" ]] || [[ -f "$PROJECT_DIR/frontend/next.config.ts" ]]; then
        STACK="craftcms-nextjs"
      else
        STACK="craftcms"
      fi
    # WordPress Bedrock/Roots (web/app structure or roots/bedrock in composer)
    elif [[ -d "$PROJECT_DIR/web/app/mu-plugins" ]] || [[ -d "$PROJECT_DIR/web/app/plugins" ]]; then
      STACK="wordpress-roots"
    elif [[ -f "$PROJECT_DIR/composer.json" ]] && grep -qE '"roots/bedrock"|"roots/wordpress"' "$PROJECT_DIR/composer.json" 2>/dev/null; then
      STACK="wordpress-roots"
    # Standard WordPress (root, public/, or web/ docroot)
    elif [[ -f "$PROJECT_DIR/wp-config.php" ]] || [[ -d "$PROJECT_DIR/wp-content" ]]; then
      STACK="wordpress"
    elif [[ -f "$PROJECT_DIR/public/wp-config.php" ]] || [[ -d "$PROJECT_DIR/public/wp-content" ]]; then
      STACK="wordpress"
    elif [[ -f "$PROJECT_DIR/web/wp-config.php" ]] || [[ -d "$PROJECT_DIR/web/wp-content" ]]; then
      STACK="wordpress"
    # SvelteKit (svelte.config.js/ts is the canonical indicator)
    elif [[ -f "$PROJECT_DIR/svelte.config.js" ]] || [[ -f "$PROJECT_DIR/svelte.config.ts" ]]; then
      STACK="sveltekit"
    # Nuxt 3 standalone (nuxt.config.* without a CMS backend)
    elif [[ -f "$PROJECT_DIR/nuxt.config.ts" ]] || [[ -f "$PROJECT_DIR/nuxt.config.js" ]]; then
      STACK="nuxt"
    # T3 Stack: Next.js + tRPC + Prisma — check BEFORE generic nextjs
    # Canonical signals: next.config.* AND prisma schema AND @trpc/server
    elif ([[ -f "$PROJECT_DIR/next.config.js" ]] || [[ -f "$PROJECT_DIR/next.config.mjs" ]] || [[ -f "$PROJECT_DIR/next.config.ts" ]]) \
      && [[ -f "$PROJECT_DIR/prisma/schema.prisma" ]] \
      && [[ -f "$PROJECT_DIR/package.json" ]] && grep -q '"@trpc/server"' "$PROJECT_DIR/package.json" 2>/dev/null; then
      STACK="t3-stack"
    # Remix / React Router v7 (app/root.tsx or remix.config.js are canonical)
    elif [[ -f "$PROJECT_DIR/remix.config.js" ]] || [[ -f "$PROJECT_DIR/remix.config.ts" ]] \
      || ([[ -f "$PROJECT_DIR/app/root.tsx" ]] && [[ -f "$PROJECT_DIR/package.json" ]] \
        && grep -q '"@remix-run/react"\|"react-router"' "$PROJECT_DIR/package.json" 2>/dev/null); then
      STACK="remix"
    # Astro (check for CMS integrations first, then standalone)
    elif [[ -f "$PROJECT_DIR/astro.config.mjs" ]] || [[ -f "$PROJECT_DIR/astro.config.ts" ]]; then
      if [[ -f "$PROJECT_DIR/sanity.config.ts" ]] || [[ -f "$PROJECT_DIR/sanity.config.js" ]]; then
        STACK="astro-sanity"
      elif [[ -d "$PROJECT_DIR/backend" ]] && [[ -f "$PROJECT_DIR/backend/package.json" ]] && grep -q '"@strapi' "$PROJECT_DIR/backend/package.json" 2>/dev/null; then
        STACK="astro-strapi"
      elif [[ -f "$PROJECT_DIR/tina/config.ts" ]] || [[ -f "$PROJECT_DIR/tina/config.js" ]]; then
        STACK="astro-tina"
      elif [[ -f "$PROJECT_DIR/package.json" ]] && grep -q '"tinacms"' "$PROJECT_DIR/package.json" 2>/dev/null; then
        STACK="astro-tina"
      else
        STACK="astro"
      fi
    # Astro (frontend/ subdirectory layout — check Strapi, then standalone)
    elif [[ -f "$PROJECT_DIR/frontend/astro.config.mjs" ]] || [[ -f "$PROJECT_DIR/frontend/astro.config.ts" ]]; then
      if [[ -d "$PROJECT_DIR/backend" ]] && [[ -f "$PROJECT_DIR/backend/package.json" ]] && grep -q '"@strapi' "$PROJECT_DIR/backend/package.json" 2>/dev/null; then
        STACK="astro-strapi"
      else
        STACK="astro"
      fi
    # Next.js (standalone)
    elif [[ -f "$PROJECT_DIR/next.config.js" ]] || [[ -f "$PROJECT_DIR/next.config.mjs" ]] || [[ -f "$PROJECT_DIR/next.config.ts" ]]; then
      STACK="nextjs"
    # Docusaurus
    elif [[ -f "$PROJECT_DIR/docusaurus.config.js" ]] || [[ -f "$PROJECT_DIR/docusaurus.config.ts" ]]; then
      STACK="docusaurus"
    # package.json fallback detection
    elif [[ -f "$PROJECT_DIR/package.json" ]]; then
      if grep -q '"next"' "$PROJECT_DIR/package.json" 2>/dev/null; then
        STACK="nextjs"
      elif grep -q '"@docusaurus' "$PROJECT_DIR/package.json" 2>/dev/null; then
        STACK="docusaurus"
      elif grep -q '"@sveltejs/kit"' "$PROJECT_DIR/package.json" 2>/dev/null; then
        STACK="sveltekit"
      elif grep -q '"nuxt"' "$PROJECT_DIR/package.json" 2>/dev/null; then
        STACK="nuxt"
      elif grep -q '"@remix-run/react"\|"react-router"' "$PROJECT_DIR/package.json" 2>/dev/null; then
        STACK="remix"
      elif grep -q '"astro"' "$PROJECT_DIR/package.json" 2>/dev/null; then
        if grep -q '"@sanity' "$PROJECT_DIR/package.json" 2>/dev/null; then
          STACK="astro-sanity"
        elif grep -q '"@strapi' "$PROJECT_DIR/package.json" 2>/dev/null; then
          STACK="astro-strapi"
        elif grep -q '"tinacms"' "$PROJECT_DIR/package.json" 2>/dev/null; then
          STACK="astro-tina"
        else
          STACK="astro"
        fi
      fi
    fi

    if [[ -n "$STACK" ]]; then
      echo -e "${CYAN}Auto-detected stack from project files: ${GREEN}$STACK${NC}"
    fi
  fi
fi

# If still no stack and --discover mode, use custom/generic stack
if [[ -z "$STACK" ]] && [[ "$DISCOVER" == true ]]; then
  STACK="custom"
  echo -e "${CYAN}Discovery mode: Will generate custom configuration${NC}"
fi

# --uninstall doesn't need a stack
if [[ "$UNINSTALL" == true && -z "$STACK" ]]; then
  STACK="custom"
fi

# Validate stack is specified or detected
if [[ -z "$STACK" ]]; then
  echo -e "${YELLOW}Could not auto-detect stack.${NC}"
  echo ""
  echo "Options:"
  echo "  1. Specify a stack:  --stack=<stack>"
  echo "  2. Use discovery mode:  --discover"
  echo ""
  echo "Available stacks:"
  ls -1 "$SCRIPT_DIR/projects/" 2>/dev/null | sed 's/^/  - /'
  echo "  - custom (use --discover for AI-powered setup)"
  exit 1
fi

# Check stack exists (or is custom)
STACK_DIR="$SCRIPT_DIR/projects/$STACK"
if [[ "$STACK" != "custom" ]] && [[ ! -d "$STACK_DIR" ]]; then
  echo -e "${RED}Error: Stack '$STACK' not found${NC}"
  echo "Available stacks:"
  ls -1 "$SCRIPT_DIR/projects/" 2>/dev/null | sed 's/^/  - /'
  echo "  - custom (use --discover for AI-powered setup)"
  exit 1
fi

# Derive project name and slug if not provided
if [[ -z "$PROJECT_NAME" ]]; then
  PROJECT_NAME="$(basename "$PROJECT_DIR")"
fi

if [[ -z "$PROJECT_SLUG" ]]; then
  PROJECT_SLUG="$(basename "$PROJECT_DIR" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
fi

# ============================================================================
# Project Detection Functions
# ============================================================================

detect_ddev_config() {
  local config_file="$PROJECT_DIR/.ddev/config.yaml"
  if [[ -f "$config_file" ]]; then
    DDEV_NAME=$(grep -E "^name:" "$config_file" 2>/dev/null | head -1 | sed 's/name:[[:space:]]*//' | tr -d '"' || echo "")
    DDEV_DOCROOT=$(grep -E "^docroot:" "$config_file" 2>/dev/null | head -1 | sed 's/docroot:[[:space:]]*//' | tr -d '"' || echo "public")
    DDEV_PHP=$(grep -E "^php_version:" "$config_file" 2>/dev/null | head -1 | sed 's/php_version:[[:space:]]*//' | tr -d '"' || echo "8.1")
    
    # TLD detection (default: ddev.site)
    DDEV_TLD=$(grep -E "^project_tld:" "$config_file" 2>/dev/null | head -1 | sed 's/project_tld:[[:space:]]*//' | tr -d '"' || echo "ddev.site")
    
    # Get all additional FQDNs
    local fqdns
    fqdns=$(grep -A10 "additional_fqdns:" "$config_file" 2>/dev/null | grep -E "^\s+-" | sed 's/.*-[[:space:]]*//' | tr -d '"')
    
    # Try to find an FQDN that contains the DDEV name (prefer English/primary domain)
    DDEV_PRIMARY_FQDN=""
    if [[ -n "$fqdns" ]]; then
      # First, try to find one that contains the DDEV name
      DDEV_PRIMARY_FQDN=$(echo "$fqdns" | grep -i "$DDEV_NAME" | head -1 || true)
      # If no match, use the first FQDN
      if [[ -z "$DDEV_PRIMARY_FQDN" ]]; then
        DDEV_PRIMARY_FQDN=$(echo "$fqdns" | head -1)
      fi
    fi
    
    # Build primary URL
    if [[ -n "$DDEV_PRIMARY_FQDN" ]]; then
      # Check if FQDN already has a TLD (contains a dot after the hostname)
      if [[ "$DDEV_PRIMARY_FQDN" == *.*.* ]]; then
        # Already a full FQDN (e.g., www.example-project.test)
        DDEV_PRIMARY_URL="https://$DDEV_PRIMARY_FQDN"
      else
        # Partial FQDN (e.g., www.example-project) - append the project TLD
        DDEV_PRIMARY_URL="https://${DDEV_PRIMARY_FQDN}.${DDEV_TLD}"
      fi
    elif [[ -n "$DDEV_TLD" ]] && [[ "$DDEV_TLD" != "ddev.site" ]]; then
      DDEV_PRIMARY_URL="https://${DDEV_NAME}.${DDEV_TLD}"
    else
      DDEV_PRIMARY_URL="https://${DDEV_NAME}.ddev.site"
    fi
    
    # Database detection (more complex due to nested structure)
    if grep -q "type: mariadb" "$config_file" 2>/dev/null; then
      DDEV_DB_TYPE="MariaDB"
      DDEV_DB_VERSION=$(grep -A1 "database:" "$config_file" 2>/dev/null | grep "version:" | sed 's/.*version:[[:space:]]*//' | tr -d '"' || echo "10.11")
    elif grep -q "type: mysql" "$config_file" 2>/dev/null; then
      DDEV_DB_TYPE="MySQL"
      DDEV_DB_VERSION=$(grep -A1 "database:" "$config_file" 2>/dev/null | grep "version:" | sed 's/.*version:[[:space:]]*//' | tr -d '"' || echo "8.0")
    else
      DDEV_DB_TYPE="MariaDB"
      DDEV_DB_VERSION="10.11"
    fi
    return 0
  fi
  return 1
}

detect_template_group() {
  local templates_dir="$PROJECT_DIR/system/user/templates"
  if [[ -d "$templates_dir" ]]; then
    # Find the first non-underscore directory (the main template group)
    TEMPLATE_GROUP=$(find "$templates_dir" -mindepth 1 -maxdepth 1 ! -name '_*' -exec basename {} \; 2>/dev/null | LC_ALL=C sort | head -1 || true)
  fi
  return 0
}

# frontend_has <id> — true when detect-frontend.sh found that library.
frontend_has() {
  printf '%s\n' "$FRONTEND_RECORDS" | awk -F'\t' -v id="$1" '$1 == "lib" && $2 == id { found = 1 } END { exit !found }'
}

# frontend_has_category <category-regex> — true when any detected library is in those categories.
frontend_has_category() {
  printf '%s\n' "$FRONTEND_RECORDS" | awk -F'\t' -v re="$1" '$1 == "lib" && $4 ~ re { found = 1 } END { exit !found }'
}

# frontend_group <category-regex> — "Label 1.2 (evidence); Label (evidence)" for one group.
frontend_group() {
  printf '%s\n' "$FRONTEND_RECORDS" | awk -F'\t' -v re="$1" '
    $1 == "lib" && $4 ~ re { out = out (out == "" ? "" : "; ") $3 ($5 != "" ? " " $5 : "") " (" $6 ")" }
    END { print out }'
}

# frontend_custom <js|css> <framework-category-regex> <noun> — first-party code phrase, or nothing.
frontend_custom() {
  local line count folder
  line=$(printf '%s\n' "$FRONTEND_RECORDS" | awk -F'\t' -v k="$1" '$1 == "custom" && $2 == k { print $3 "\t" $4; exit }')
  [[ -n "$line" ]] || return 0
  count="${line%%$'\t'*}"
  folder="${line#*$'\t'}"
  if frontend_has_category "$2"; then
    printf 'plus %s first-party %s file(s), mainly in %s/' "$count" "$3" "$folder"
  else
    printf 'custom %s, no framework detected (%s file(s), mainly in %s/)' "$3" "$count" "$folder"
  fi
}

# frontend_report — "Heading<TAB>text" lines: CSS, UI components, JavaScript, Build, Language.
frontend_report() {
  local css ui js build lang custom_css custom_js
  css=$(frontend_group '^(css|css-tool)$')
  custom_css=$(frontend_custom css '^css$' CSS)
  ui=$(frontend_group '^ui$')
  js=$(frontend_group '^(js-framework|js-lib)$')
  custom_js=$(frontend_custom js '^(js-framework|js-lib|ui)$' JavaScript)
  build=$(frontend_group '^build$')
  lang=$(frontend_group '^lang$')
  if [[ -n "$css" && -n "$custom_css" ]]; then css="$css; $custom_css"; else css="$css$custom_css"; fi
  if [[ -n "$js" && -n "$custom_js" ]]; then js="$js; $custom_js"; else js="$js$custom_js"; fi
  if [[ -n "$css" ]]; then printf 'CSS\t%s\n' "$css"; fi
  if [[ -n "$ui" ]]; then printf 'UI components\t%s\n' "$ui"; fi
  if [[ -n "$js" ]]; then printf 'JavaScript\t%s\n' "$js"; fi
  if [[ -n "$build" ]]; then printf 'Build\t%s\n' "$build"; fi
  if [[ -n "$lang" ]]; then printf 'Language\t%s\n' "$lang"; fi
  return 0
}

# Front-End Stack block for CLAUDE.md / AGENTS.md, so Claude follows the project's actual stack
# instead of assuming one. Deterministic: it only changes when the detected stack changes.
write_frontend_block() {
  local lines heading text
  FRONTEND_BLOCK_FILE=""
  lines=$(frontend_report)
  [[ -n "$lines" ]] || return 0
  FRONTEND_TMP_DIR=$(mktemp -d)
  trap 'rm -rf "$FRONTEND_TMP_DIR"' EXIT
  FRONTEND_BLOCK_FILE="$FRONTEND_TMP_DIR/frontend-stack.md"
  {
    echo "<!-- BEGIN FRONTEND STACK (managed by ai-config; regenerated on refresh) -->"
    echo "## Front-End Stack (detected)"
    echo ""
    while IFS=$'\t' read -r heading text; do
      echo "- **$heading:** $text"
    done <<< "$lines"
    echo ""
    echo "Detected from package.json files, template tags, and asset files. Work within this stack;"
    echo "ask before introducing another CSS or JavaScript framework."
    echo "<!-- END FRONTEND STACK -->"
  } > "$FRONTEND_BLOCK_FILE"
}

detect_frontend_tools() {
  # Front-end stack from every package.json (theme folders included), vendored asset names,
  # template CDN/enqueue references, and markup attributes — see projects/common/detect-frontend.sh.
  FRONTEND_RECORDS=$(bash "$SCRIPT_DIR/projects/common/detect-frontend.sh" "$PROJECT_DIR" 2>/dev/null || true)
  if frontend_has tailwind; then HAS_TAILWIND=true; fi
  if frontend_has foundation; then HAS_FOUNDATION=true; fi
  if frontend_has scss; then HAS_SCSS=true; fi
  if frontend_has alpine; then HAS_ALPINE=true; fi
  if frontend_has bootstrap; then HAS_BOOTSTRAP=true; fi
  if frontend_has bulma; then HAS_BULMA=true; fi
  if frontend_has jquery; then HAS_JQUERY=true; fi
  if frontend_has mui; then HAS_MUI=true; fi

  # Check for bilingual content patterns (EE user_language, Twig lang, Blade @lang)
  if grep -rq --include="*.html" "user_language" "$PROJECT_DIR/system/user/templates" 2>/dev/null; then
    HAS_BILINGUAL=true
  elif grep -rq --include="*.twig" --include="*.blade.php" '{%.*lang\|@lang\|__(' "$PROJECT_DIR" 2>/dev/null; then
    HAS_BILINGUAL=true
  fi

  # Vanilla JS: the project has its own scripts and no JS framework, library, or UI kit.
  if printf '%s\n' "$FRONTEND_RECORDS" | grep -q "^custom	js	" && ! frontend_has_category '^(js-framework|js-lib|ui)$'; then
    HAS_VANILLA_JS=true
  fi

  # Modern web tooling detection (used for smarter library @-import injection)
  [[ -f "$PROJECT_DIR/tsconfig.json" ]] && HAS_TYPESCRIPT=true

  if [[ -f "$PROJECT_DIR/package.json" ]]; then
    grep -q '"zustand"' "$PROJECT_DIR/package.json" 2>/dev/null           && HAS_ZUSTAND=true
    grep -q '"@tanstack/react-query"' "$PROJECT_DIR/package.json" 2>/dev/null && HAS_TANSTACK_QUERY=true
    grep -q '"@trpc/server"' "$PROJECT_DIR/package.json" 2>/dev/null      && HAS_TRPC=true
    grep -q '"vitest"' "$PROJECT_DIR/package.json" 2>/dev/null            && HAS_VITEST=true
    grep -q '"zod"' "$PROJECT_DIR/package.json" 2>/dev/null               && HAS_ZOD=true
    grep -q '"pinia"' "$PROJECT_DIR/package.json" 2>/dev/null             && HAS_PINIA=true
    grep -q '"@supabase/supabase-js"\|"@supabase/ssr"' "$PROJECT_DIR/package.json" 2>/dev/null && HAS_SUPABASE=true
    grep -q '"framer-motion"\|"\"motion\""' "$PROJECT_DIR/package.json" 2>/dev/null && HAS_FRAMER_MOTION=true
    grep -q '"@playwright/test"' "$PROJECT_DIR/package.json" 2>/dev/null  && HAS_PLAYWRIGHT=true
  fi

  # Prisma: schema file is canonical indicator
  if [[ -f "$PROJECT_DIR/prisma/schema.prisma" ]]; then
    HAS_PRISMA=true
  elif [[ -f "$PROJECT_DIR/package.json" ]] && grep -q '"@prisma/client"' "$PROJECT_DIR/package.json" 2>/dev/null; then
    HAS_PRISMA=true
  fi

  # Playwright: config file is canonical indicator
  if [[ -f "$PROJECT_DIR/playwright.config.ts" ]] || [[ -f "$PROJECT_DIR/playwright.config.js" ]]; then
    HAS_PLAYWRIGHT=true
  fi

  # shadcn/ui: components/ui directory is canonical indicator
  if [[ -d "$PROJECT_DIR/components/ui" ]] || [[ -d "$PROJECT_DIR/src/components/ui" ]] || [[ -d "$PROJECT_DIR/app/components/ui" ]]; then
    HAS_SHADCN=true
  fi

  # Tina CMS: tina/config.ts/js is the canonical indicator
  if [[ -f "$PROJECT_DIR/tina/config.ts" ]] || [[ -f "$PROJECT_DIR/tina/config.js" ]]; then
    HAS_TINA=true
  elif [[ -f "$PROJECT_DIR/package.json" ]] && grep -q '"tinacms"' "$PROJECT_DIR/package.json" 2>/dev/null; then
    HAS_TINA=true
  fi

  return 0
}

detect_addons() {
  local addons_dir="$PROJECT_DIR/system/user/addons"
  if [[ -d "$addons_dir" ]]; then
    [[ -d "$addons_dir/stash" ]] && HAS_STASH=true
    [[ -d "$addons_dir/structure" ]] && HAS_STRUCTURE=true
  fi
  return 0
}

detect_git_branches() {
  # Check if project is a Git repository
  if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    GIT_MAIN_BRANCH="main"
    GIT_INTEGRATION_BRANCH="main"
    return 0
  fi

  # Get all local and remote branches (deduplicated)
  local branches
  branches=$(git -C "$PROJECT_DIR" branch -a 2>/dev/null | sed 's/[* ]*//' | sed 's|remotes/origin/||' | grep -v '^HEAD' | sort -u)

  # Detect main branch (priority: main > master)
  if echo "$branches" | grep -qx "main"; then
    GIT_MAIN_BRANCH="main"
  elif echo "$branches" | grep -qx "master"; then
    GIT_MAIN_BRANCH="master"
  else
    GIT_MAIN_BRANCH="main"  # Default
  fi

  # Detect integration branch (priority: staging > develop > dev > main branch)
  if echo "$branches" | grep -qx "staging"; then
    GIT_INTEGRATION_BRANCH="staging"
  elif echo "$branches" | grep -qx "develop"; then
    GIT_INTEGRATION_BRANCH="develop"
  elif echo "$branches" | grep -qx "dev"; then
    GIT_INTEGRATION_BRANCH="dev"
  else
    GIT_INTEGRATION_BRANCH="$GIT_MAIN_BRANCH"
  fi

  return 0
}

# Detect additional technologies for discovery report
detect_all_technologies() {
  DETECTED_TECHNOLOGIES=()

  # Package managers
  [[ -f "$PROJECT_DIR/package.json" ]] && DETECTED_TECHNOLOGIES+=("npm/Node.js")
  [[ -f "$PROJECT_DIR/yarn.lock" ]] && DETECTED_TECHNOLOGIES+=("Yarn")
  [[ -f "$PROJECT_DIR/pnpm-lock.yaml" ]] && DETECTED_TECHNOLOGIES+=("pnpm")
  [[ -f "$PROJECT_DIR/bun.lockb" ]] && DETECTED_TECHNOLOGIES+=("Bun")
  [[ -f "$PROJECT_DIR/composer.json" ]] && DETECTED_TECHNOLOGIES+=("Composer/PHP")
  [[ -f "$PROJECT_DIR/Gemfile" ]] && DETECTED_TECHNOLOGIES+=("Ruby/Bundler")
  [[ -f "$PROJECT_DIR/requirements.txt" ]] || [[ -f "$PROJECT_DIR/pyproject.toml" ]] && DETECTED_TECHNOLOGIES+=("Python")
  [[ -f "$PROJECT_DIR/go.mod" ]] && DETECTED_TECHNOLOGIES+=("Go")
  [[ -f "$PROJECT_DIR/Cargo.toml" ]] && DETECTED_TECHNOLOGIES+=("Rust")

  # Frameworks (from package.json)
  if [[ -f "$PROJECT_DIR/package.json" ]]; then
    grep -q '"react"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("React")
    grep -q '"vue"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Vue.js")
    grep -q '"svelte"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Svelte")
    grep -q '"angular"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Angular")
    grep -q '"express"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Express.js")
    grep -q '"fastify"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Fastify")
    grep -q '"astro"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Astro")
    grep -q '"nuxt"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Nuxt.js")
    grep -q '"gatsby"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Gatsby")
    grep -q '"remix"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Remix")
    grep -q '"vite"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Vite")
    grep -q '"webpack"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Webpack")
    grep -q '"esbuild"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("esbuild")
    grep -q '"typescript"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("TypeScript")
    grep -q '"tailwindcss"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Tailwind CSS")
    grep -q '"alpinejs"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Alpine.js")
    grep -q '"sass"\|"node-sass"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Sass/SCSS")
    grep -q '"jest"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Jest")
    grep -q '"vitest"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Vitest")
    grep -q '"playwright"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Playwright")
    grep -q '"cypress"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Cypress")
    grep -q '"prisma"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Prisma")
    grep -q '"drizzle"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Drizzle ORM")
    grep -q '"eslint"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("ESLint")
    grep -q '"prettier"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Prettier")
    grep -q '"storybook"' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Storybook")
    grep -q '"@sanity' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Sanity")
    grep -q '"@strapi' "$PROJECT_DIR/package.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Strapi")
  fi

  # PHP frameworks (from composer.json)
  if [[ -f "$PROJECT_DIR/composer.json" ]]; then
    grep -q '"laravel/framework"' "$PROJECT_DIR/composer.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Laravel")
    grep -q '"symfony/' "$PROJECT_DIR/composer.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Symfony")
    grep -q '"craftcms/cms"' "$PROJECT_DIR/composer.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Craft CMS")
    grep -q '"expressionengine/' "$PROJECT_DIR/composer.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("ExpressionEngine")
    grep -q '"phpunit/' "$PROJECT_DIR/composer.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("PHPUnit")
    grep -q '"pestphp/' "$PROJECT_DIR/composer.json" 2>/dev/null && DETECTED_TECHNOLOGIES+=("Pest PHP")
  fi

  # Config files detection
  [[ -f "$PROJECT_DIR/tailwind.config.js" ]] || [[ -f "$PROJECT_DIR/tailwind.config.ts" ]] && DETECTED_TECHNOLOGIES+=("Tailwind CSS")
  [[ -f "$PROJECT_DIR/tsconfig.json" ]] && DETECTED_TECHNOLOGIES+=("TypeScript")
  [[ -f "$PROJECT_DIR/.eslintrc.js" ]] || [[ -f "$PROJECT_DIR/.eslintrc.json" ]] || [[ -f "$PROJECT_DIR/eslint.config.js" ]] && DETECTED_TECHNOLOGIES+=("ESLint")
  [[ -f "$PROJECT_DIR/.prettierrc" ]] || [[ -f "$PROJECT_DIR/prettier.config.js" ]] && DETECTED_TECHNOLOGIES+=("Prettier")
  [[ -f "$PROJECT_DIR/sanity.config.ts" ]] || [[ -f "$PROJECT_DIR/sanity.config.js" ]] && DETECTED_TECHNOLOGIES+=("Sanity Studio")
  [[ -f "$PROJECT_DIR/docker-compose.yml" ]] || [[ -f "$PROJECT_DIR/docker-compose.yaml" ]] && DETECTED_TECHNOLOGIES+=("Docker Compose")
  [[ -f "$PROJECT_DIR/Dockerfile" ]] && DETECTED_TECHNOLOGIES+=("Docker")
  [[ -d "$PROJECT_DIR/.ddev" ]] && DETECTED_TECHNOLOGIES+=("DDEV")
  [[ -f "$PROJECT_DIR/.github/workflows" ]] && DETECTED_TECHNOLOGIES+=("GitHub Actions")
  [[ -f "$PROJECT_DIR/.gitlab-ci.yml" ]] && DETECTED_TECHNOLOGIES+=("GitLab CI")

  # Database indicators
  [[ -f "$PROJECT_DIR/prisma/schema.prisma" ]] && DETECTED_TECHNOLOGIES+=("Prisma ORM")
  [[ -d "$PROJECT_DIR/migrations" ]] || [[ -d "$PROJECT_DIR/database/migrations" ]] && DETECTED_TECHNOLOGIES+=("Database Migrations")

  # Front-end stack found by detect-frontend.sh (theme package.json files, CDN tags, vendored assets)
  local label
  while IFS= read -r label; do
    if [[ -n "$label" ]]; then DETECTED_TECHNOLOGIES+=("$label"); fi
  done < <(printf '%s\n' "$FRONTEND_RECORDS" | awk -F'\t' '$1 == "lib" { print $3 }')

  # Remove duplicates (line-based, so names with spaces like "Tailwind CSS" stay whole)
  local deduped=() tech
  while IFS= read -r tech; do
    if [[ -n "$tech" ]]; then deduped+=("$tech"); fi
  done < <(printf '%s\n' "${DETECTED_TECHNOLOGIES[@]}" | LC_ALL=C sort -u)
  DETECTED_TECHNOLOGIES=("${deduped[@]}")
}

# ============================================================================
# Helper Functions
# ============================================================================

# ============================================================================
# Additive Update Primitives
# ============================================================================
# Every file ai-config ships goes through do_copy / install_rendered, which never discard
# a developer's work:
#   missing                              → added
#   identical to the shipped version     → left alone
#   unedited since ai-config wrote it    → updated (previous copy backed up)
#   edited by the developer              → kept; the new version is staged in
#                                          .claude/ai-config/pending/ for review
# "Unedited" means the file's hash matches .claude/ai-config/manifest.tsv (what this script
# last wrote) or — for projects deployed before the manifest existed — matches a version of
# the source file somewhere in this repo's git history.
# Files changed in place (settings.local.json, .gitignore, managed CLAUDE.md blocks) are
# backed up once per run to .claude/ai-config/backups/<run>/ and only written on a real
# change. CLAUDE.md, MEMORY.md and .claude/ are usually gitignored, so these backups are the
# only history those files have. --apply-pending adopts staged versions (with backups).

AI_CONFIG_DIR="$PROJECT_DIR/.claude/ai-config"
MANIFEST_FILE="$AI_CONFIG_DIR/manifest.tsv"
PENDING_DIR="$AI_CONFIG_DIR/pending"
RUN_STAMP="$(date +%Y%m%d-%H%M%S)-$$"
BACKUP_DIR="$AI_CONFIG_DIR/backups/$RUN_STAMP"
COUNT_ADDED=0
COUNT_UPDATED=0
COUNT_KEPT=0
COUNT_BACKED_UP=0
OWNED_RENDERED=()   # generated files this run fully owns; hashed into the manifest at the end
CREATED_THIS_RUN=$'\n'   # newline-delimited paths this run created — no prior version to back up

file_sha() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

rel_path() { printf '%s' "${1#"$PROJECT_DIR"/}"; }

manifest_get() {
  [[ -f "$MANIFEST_FILE" ]] || return 0
  awk -F'\t' -v k="$1" '$1 == k { h = $2 } END { if (h != "") print h }' "$MANIFEST_FILE"
}

# Appends "<rel>\t<sha>"; the last entry for a path wins until compact_manifest dedupes.
manifest_record() {
  if [[ "$DRY_RUN" == true || ! -f "$2" ]]; then return 0; fi
  mkdir -p "$AI_CONFIG_DIR"
  printf '%s\t%s\n' "$1" "$(file_sha "$2")" >> "$MANIFEST_FILE"
}

compact_manifest() {
  if [[ "$DRY_RUN" == true || ! -f "$MANIFEST_FILE" ]]; then return 0; fi
  awk -F'\t' '{ if (!($1 in h)) order[++n] = $1; h[$1] = $2 }
    END { for (i = 1; i <= n; i++) print order[i] "\t" h[order[i]] }' "$MANIFEST_FILE" > "$MANIFEST_FILE.tmp"
  mv "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"
}

# Copy a project file into this run's backup folder before it is modified (first copy wins).
backup_file() {
  local abs="$1" dest
  if [[ "$DRY_RUN" == true || ! -f "$abs" ]]; then return 0; fi
  case "$abs" in "$PROJECT_DIR"/*) ;; *) return 0 ;; esac
  case "$CREATED_THIS_RUN" in *$'\n'"$abs"$'\n'*) return 0 ;; esac
  dest="$BACKUP_DIR/$(rel_path "$abs")"
  if [[ -e "$dest" ]]; then return 0; fi
  mkdir -p "$(dirname "$dest")"
  cp -p "$abs" "$dest"
  COUNT_BACKED_UP=$((COUNT_BACKED_UP + 1))
}

# is_unedited_copy <project-file> [source-file] — true when ai-config shipped this exact
# content and the developer has not changed it since.
is_unedited_copy() {
  local abs="$1" src="${2:-}" recorded blob
  recorded=$(manifest_get "$(rel_path "$abs")")
  if [[ -n "$recorded" ]]; then
    [[ "$recorded" == "$(file_sha "$abs")" ]]
    return
  fi
  # No manifest entry (deployed by an older ai-config): accept any committed version of the source.
  [[ -n "$src" ]] || return 1
  case "$src" in "$SCRIPT_DIR"/*) ;; *) return 1 ;; esac
  command -v git &>/dev/null || return 1
  blob=$(git -C "$SCRIPT_DIR" hash-object "$abs" 2>/dev/null) || return 1
  git -C "$SCRIPT_DIR" log --all --pretty=format: --raw --no-abbrev -- "${src#"$SCRIPT_DIR"/}" 2>/dev/null \
    | awk 'NF >= 4 { print $3; print $4 }' | grep -qx "$blob"
}

stage_pending() {
  mkdir -p "$(dirname "$PENDING_DIR/$2")"
  cp "$1" "$PENDING_DIR/$2"
}

# install_file <src> <dest> [history-src] — the additive write for one shipped file (see header
# above). history-src is the repo file whose git history identifies legacy unedited copies when
# src is a rendered scratch file.
install_file() {
  local src="$1" dest="$2" history_src="${3:-$1}" rel
  rel=$(rel_path "$dest")

  if [[ ! -e "$dest" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      echo -e "  ${YELLOW}[DRY-RUN]${NC} Add $rel"
      return 0
    fi
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    if [[ -x "$src" ]]; then chmod +x "$dest"; fi
    manifest_record "$rel" "$dest"
    CREATED_THIS_RUN+="$dest"$'\n'
    COUNT_ADDED=$((COUNT_ADDED + 1))
    echo -e "  ${GREEN}✓${NC} Added $rel"
    return 0
  fi

  if cmp -s "$src" "$dest"; then
    if [[ "$DRY_RUN" != true ]]; then
      if [[ "$(manifest_get "$rel")" != "$(file_sha "$dest")" ]]; then manifest_record "$rel" "$dest"; fi
      rm -f "$PENDING_DIR/$rel"
    fi
    return 0
  fi

  if is_unedited_copy "$dest" "$history_src"; then
    if [[ "$DRY_RUN" == true ]]; then
      echo -e "  ${YELLOW}[DRY-RUN]${NC} Update $rel (unedited since it was deployed)"
      return 0
    fi
    backup_file "$dest"
    cp "$src" "$dest"
    if [[ -x "$src" ]]; then chmod +x "$dest"; fi
    manifest_record "$rel" "$dest"
    rm -f "$PENDING_DIR/$rel"
    COUNT_UPDATED=$((COUNT_UPDATED + 1))
    echo -e "  ${GREEN}✓${NC} Updated $rel"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Keep your edited $rel; stage the new version in .claude/ai-config/pending/"
    return 0
  fi
  stage_pending "$src" "$rel"
  COUNT_KEPT=$((COUNT_KEPT + 1))
  echo -e "  ${YELLOW}○${NC} Kept your edits to $rel — new version staged at .claude/ai-config/pending/$rel"
}

# install_rendered <template> <dest> — CLAUDE.md / AGENTS.md. A full render (template,
# detected library references, managed blocks) is built in a scratch copy, then:
#   missing, or unedited since ai-config wrote it → replaced (previous copy backed up)
#   edited by the developer (or deployed before the manifest existed) → kept; only the
#     managed blocks (between their BEGIN/END markers) are refreshed and newly detected
#     library references appended; the full render is staged in .claude/ai-config/pending/
install_rendered() {
  local template="$1" dest="$2" rel name
  rel=$(rel_path "$dest")
  name=$(basename "$dest")

  if [[ "$DRY_RUN" == true ]]; then
    if [[ ! -f "$dest" ]]; then
      echo -e "  ${YELLOW}[DRY-RUN]${NC} Create $rel from $(basename "$template")"
    elif [[ "$(manifest_get "$rel")" == "$(file_sha "$dest")" ]]; then
      echo -e "  ${YELLOW}[DRY-RUN]${NC} Regenerate $rel (unedited since it was deployed)"
    else
      echo -e "  ${YELLOW}[DRY-RUN]${NC} Keep your edited $rel; refresh its managed blocks; stage the new render"
    fi
    if [[ "$name" == "CLAUDE.md" ]]; then inject_detected_library_imports "$dest"; fi
    append_managed_policies "$dest"
    return 0
  fi

  local work render
  work=$(mktemp -d)
  render="$work/$name"
  render_template "$template" "$render"
  if [[ "$name" == "CLAUDE.md" ]]; then
    inject_detected_library_imports "$render" >/dev/null
    convert_library_imports "$render" >/dev/null
  fi
  append_managed_policies "$render" >/dev/null
  if [[ "$name" == "CLAUDE.md" && "$WITH_ORCHESTRATOR" == true ]]; then
    append_orchestrator_policy "$render" "$SCRIPT_DIR/projects/common/orchestrator/CLAUDE-orchestrator.md" >/dev/null
  fi

  if [[ ! -f "$dest" ]]; then
    cp "$render" "$dest"
    OWNED_RENDERED+=("$dest")
    CREATED_THIS_RUN+="$dest"$'\n'
    COUNT_ADDED=$((COUNT_ADDED + 1))
    echo -e "  ${GREEN}✓${NC} Created $rel from template"
  elif cmp -s "$render" "$dest"; then
    OWNED_RENDERED+=("$dest")
    rm -f "$PENDING_DIR/$rel"
    echo -e "  ${GREEN}✓${NC} $rel already current"
  elif [[ "$(manifest_get "$rel")" == "$(file_sha "$dest")" ]]; then
    backup_file "$dest"
    cp "$render" "$dest"
    OWNED_RENDERED+=("$dest")
    rm -f "$PENDING_DIR/$rel"
    COUNT_UPDATED=$((COUNT_UPDATED + 1))
    echo -e "  ${GREEN}✓${NC} Regenerated $rel (no local edits; previous copy backed up)"
  else
    if [[ "$name" == "CLAUDE.md" ]]; then inject_detected_library_imports "$dest"; fi
    append_managed_policies "$dest"
    stage_pending "$render" "$rel"
    COUNT_KEPT=$((COUNT_KEPT + 1))
    echo -e "  ${YELLOW}○${NC} Kept your edits to $rel (managed blocks refreshed) — full new render staged at .claude/ai-config/pending/$rel"
  fi
  rm -rf "$work"
}

# write_json_if_changed <dest> <json> — back up and write only when the JSON differs
# semantically (key order and formatting alone never trigger a rewrite). Returns 1 if unchanged.
write_json_if_changed() {
  local dest="$1" json="$2"
  if [[ -f "$dest" ]] && [[ "$(jq -S -c . "$dest" 2>/dev/null)" == "$(printf '%s' "$json" | jq -S -c .)" ]]; then
    return 1
  fi
  if [[ -f "$dest" ]]; then
    backup_file "$dest"
  else
    CREATED_THIS_RUN+="$dest"$'\n'
  fi
  mkdir -p "$(dirname "$dest")"
  printf '%s\n' "$json" > "$dest"
}

# --apply-pending: adopt every staged new version (each replaced file is backed up first).
apply_pending_updates() {
  if [[ "$APPLY_PENDING" != true || ! -d "$PENDING_DIR" ]]; then return 0; fi
  echo ""
  echo -e "${CYAN}Adopting staged updates (--apply-pending)...${NC}"
  local f rel dest
  while IFS= read -r f; do
    rel="${f#"$PENDING_DIR"/}"
    dest="$PROJECT_DIR/$rel"
    if [[ "$DRY_RUN" == true ]]; then
      echo -e "  ${YELLOW}[DRY-RUN]${NC} Replace $rel with its staged version"
      continue
    fi
    backup_file "$dest"
    mkdir -p "$(dirname "$dest")"
    cp "$f" "$dest"
    rm -f "$f"
    case "$rel" in
      CLAUDE.md|AGENTS.md) OWNED_RENDERED+=("$dest") ;;
      *) manifest_record "$rel" "$dest" ;;
    esac
    COUNT_UPDATED=$((COUNT_UPDATED + 1))
    echo -e "  ${GREEN}✓${NC} Adopted new version of $rel (previous copy backed up)"
  done < <(find "$PENDING_DIR" -type f | sort)
  find "$PENDING_DIR" -type d -empty -delete 2>/dev/null || true
}

# End of every run: record generated files this run owns, dedupe the manifest, report.
finish_additive_run() {
  local f
  if [[ "$DRY_RUN" != true ]]; then
    for f in "${OWNED_RENDERED[@]}"; do
      if [[ -f "$f" ]]; then manifest_record "$(rel_path "$f")" "$f"; fi
    done
    compact_manifest
    write_version_stamp
  fi
  echo ""
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${CYAN}Additive update summary:${NC} dry run — nothing was written (see the [DRY-RUN] lines above)"
    return 0
  fi
  echo -e "${CYAN}Additive update summary:${NC} ${COUNT_ADDED} added, ${COUNT_UPDATED} updated (unedited), ${COUNT_KEPT} kept with your edits"
  if [[ $COUNT_BACKED_UP -gt 0 ]]; then
    echo "  Previous versions of ${COUNT_BACKED_UP} modified file(s): .claude/ai-config/backups/$RUN_STAMP/"
  fi
  if [[ -d "$PENDING_DIR" ]] && [[ -n "$(find "$PENDING_DIR" -type f 2>/dev/null | head -1)" ]]; then
    echo "  New versions of files you edited: .claude/ai-config/pending/ — diff and merge by hand, or adopt all with --apply-pending"
  fi
}

# .claude/ai-config/version — which ai-config commit last deployed this project (read by --doctor
# and ai-config-fleet.sh).
ai_config_commit() {
  local sha
  sha=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null) || { echo "unknown"; return 0; }
  if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain 2>/dev/null | head -n 1)" ]]; then sha="$sha+dirty"; fi
  echo "$sha"
}

write_version_stamp() {
  mkdir -p "$AI_CONFIG_DIR"
  {
    echo "commit=$(ai_config_commit)"
    echo "deployed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "stack=$STACK"
    echo "mode=$RUN_MODE"
  } > "$AI_CONFIG_DIR/version"
}

# do_copy <src file|dir> <dest-dir/ | dest-file> — additive install (see install_file).
do_copy() {
  local src="$1" dest="$2" f
  if [[ "$dest" == */ ]]; then
    dest="${dest%/}/$(basename "$src")"
  fi
  if [[ -d "$src" ]]; then
    while IFS= read -r f; do
      install_shipped_file "$f" "$dest/${f#"$src"/}"
    done < <(find "$src" -type f ! -name '.DS_Store' | sort)
  else
    install_shipped_file "$src" "$dest"
  fi
}

# Stack files copied as-is (agents, rules, commands, skills) may contain {{VARIABLES}]. Render them
# into a scratch copy first so Claude never sees raw placeholders; legacy-copy detection still
# uses the original repo file's history.
install_shipped_file() {
  local src="$1" dest="$2" rendered
  case "$src" in
    "$SCRIPT_DIR"/projects/*)
      if grep -qE '\{\{[A-Z][A-Z0-9_]*\}\}' "$src" 2>/dev/null; then
        rendered=$(mktemp)
        render_template "$src" "$rendered"
        chmod 644 "$rendered"
        install_file "$rendered" "$dest" "$src"
        rm -f "$rendered"
        return 0
      fi
      ;;
  esac
  install_file "$src" "$dest"
}

do_mkdir() {
  local dir="$1"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} mkdir -p $dir"
  else
    mkdir -p "$dir"
  fi
}

# render_template <template> <out> — substitute {{VARIABLES}} and resolve {{#SUPERPOWERS}} sections.
render_template() {
  local src="$1"
  local dest="$2"
  # First pass: variable substitution
  sed -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
      -e "s/{{PROJECT_SLUG}}/$PROJECT_SLUG/g" \
      -e "s|{{PROJECT_PATH}}|${PROJECT_DIR}|g" \
      -e "s/{{DDEV_NAME}}/${DDEV_NAME:-$PROJECT_SLUG}/g" \
      -e "s/{{DDEV_DOCROOT}}/${DDEV_DOCROOT:-public}/g" \
      -e "s/{{DDEV_PHP}}/${DDEV_PHP:-8.1}/g" \
      -e "s/{{DDEV_DB_TYPE}}/${DDEV_DB_TYPE:-MariaDB}/g" \
      -e "s/{{DDEV_DB_VERSION}}/${DDEV_DB_VERSION:-10.11}/g" \
      -e "s/{{DDEV_TLD}}/${DDEV_TLD:-ddev.site}/g" \
      -e "s|{{DDEV_PRIMARY_URL}}|${DDEV_PRIMARY_URL:-https://${DDEV_NAME:-$PROJECT_SLUG}.ddev.site}|g" \
      -e "s/{{TEMPLATE_GROUP}}/${TEMPLATE_GROUP:-$PROJECT_SLUG}/g" \
      -e "s/{{GIT_MAIN_BRANCH}}/${GIT_MAIN_BRANCH:-main}/g" \
      -e "s/{{GIT_INTEGRATION_BRANCH}}/${GIT_INTEGRATION_BRANCH:-main}/g" \
      "$src" > "$dest"

  # Brand colors are substituted only when known — never guessed.
  local var value
  for var in BRAND_GREEN BRAND_BLUE BRAND_ORANGE BRAND_LIGHT_GREEN; do
    value="${!var}"
    if [[ -n "$value" ]]; then sed_inplace -e "s/{{$var}}/$value/g" "$dest"; fi
  done

  # Second pass: handle conditional {{#SUPERPOWERS}}...{{/SUPERPOWERS}} sections
  if [[ "$WITH_SUPERPOWERS" == true ]]; then
    # Remove only the markers, keep the content
    sed_inplace -e 's/{{#SUPERPOWERS}}//' -e 's/{{\/SUPERPOWERS}}//' "$dest"
  else
    # Remove the entire section including markers and content
    # Use perl for multi-line matching (more reliable than sed)
    perl -i -0pe 's/\{\{#SUPERPOWERS\}\}.*?\{\{\/SUPERPOWERS\}\}\n?//gs' "$dest"
  fi

  # Anything still unresolved becomes readable text, e.g. {{PROJECT_DOMAIN}} → "(project domain: not set)".
  perl -i -pe 's{\{\{([A-Z][A-Z0-9_]*)\}\}}{"(" . lc(join(" ", split(/_/, $1))) . ": not set)"}ge' "$dest"
}

# do_template <template> <dest> — create a file from a template (callers only use it for
# files that do not exist yet, e.g. MEMORY.md; CLAUDE.md/AGENTS.md use install_rendered).
do_template() {
  local src="$1"
  local dest="$2"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Template $src → $dest"
    echo -e "           Substitutions: {{PROJECT_NAME}}=$PROJECT_NAME, {{PROJECT_SLUG}}=$PROJECT_SLUG"
    return 0
  fi
  render_template "$src" "$dest"
  echo -e "  ${GREEN}✓${NC} Created $(basename "$dest") from template"
}

# jq helpers shared by every settings.local.json merge.
#   norm_rule   – treats the legacy "Bash(cmd:*)" and current "Bash(cmd *)" spellings as equal
#   hook_key    – identifies a hook by its script path, ignoring leading VAR=value assignments
#                 and a "$CLAUDE_PROJECT_DIR"/ prefix
#   union       – existing entries first (order kept), then new entries not already present
#   merge_hooks – appends hook groups whose command isn't registered yet; never removes
#                 or reorders hooks the project already has
JQ_SETTINGS_DEFS='
  def norm_rule: sub(":\\*\\)$"; " *)");
  def union($a; $b): reduce ($b // [])[] as $x (($a // []); if index([$x]) != null then . else . + [$x] end);
  def hook_key: sub("^([A-Za-z_][A-Za-z0-9_]*=(\"[^\"]*\"|[^ ]*) +)*"; "") | sub("^\"?\\$\\{?CLAUDE_PROJECT_DIR\\}?\"?/"; "");
  def merge_hooks($add):
    reduce (($add // {}) | to_entries[]) as $ev (.;
      .[$ev.key] = (
        (.[$ev.key] // []) as $cur
        | [$cur[].hooks[]?.command | hook_key] as $have
        | $cur + [$ev.value[] | select(([.hooks[]?.command | hook_key] - $have) | length > 0)]
      ));
'

merge_settings_json() {
  local template_file="$1"
  local target_file="$2"

  # If target doesn't exist yet, just copy
  if [[ ! -f "$target_file" ]]; then
    do_copy "$template_file" "$(dirname "$target_file")/"
    return
  fi

  if ! command -v jq &>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC}  jq not found — skipping settings merge (install jq to enable)"
    return
  fi

  # Validate both files are valid JSON before attempting merge
  if ! jq empty "$target_file" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC}  Existing settings.local.json is invalid JSON — skipping merge"
    return
  fi
  if ! jq empty "$template_file" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC}  Template settings.local.json is invalid JSON — skipping merge"
    return
  fi

  local before_deny before_allow
  before_deny=$(jq '.permissions.deny | length' "$target_file")
  before_allow=$(jq '.permissions.allow | length' "$target_file")

  if [[ "$DRY_RUN" == true ]]; then
    local preview_deny preview_allow
    preview_deny=$(jq -s '
      (.[0].permissions.deny // []) as $existing |
      (.[1].permissions.deny // []) as $template |
      ($template + $existing | unique | length)
    ' "$target_file" "$template_file")
    preview_allow=$(jq -s '
      (.[0].permissions.allow // []) as $existing |
      (.[1].permissions.allow // []) as $template |
      ($template + $existing | unique | length)
    ' "$target_file" "$template_file")
    local added_deny=$((preview_deny - before_deny))
    local added_allow=$((preview_allow - before_allow))
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Merge settings.local.json (+${added_allow} allow, +${added_deny} deny)"
    return
  fi

  # Merge strategy:
  #   - Scalar fields: existing value wins (project customizations preserved)
  #   - allow / ask / deny / enabledMcpjsonServers: union — existing entries keep their order,
#     template entries not yet present are appended; nothing is removed
  #   - hooks: template hook groups are appended only if their command isn't registered
  #   - Top-level keys only in template are added; keys only in existing are kept
  local merged
  if ! merged=$(jq -s "$JQ_SETTINGS_DEFS"'
    .[0] as $existing |
    .[1] as $template |
    ($template * $existing) |
    .permissions.allow = union($existing.permissions.allow; $template.permissions.allow) |
    .permissions.deny = union($existing.permissions.deny; $template.permissions.deny) |
    if ($template.permissions.ask != null or $existing.permissions.ask != null) then
      .permissions.ask = union($existing.permissions.ask; $template.permissions.ask)
    else . end |
    if ($template.enabledMcpjsonServers != null or $existing.enabledMcpjsonServers != null) then
      .enabledMcpjsonServers = union($existing.enabledMcpjsonServers; $template.enabledMcpjsonServers)
    else . end |
    if $template.hooks != null then
      .hooks = (($existing.hooks // {}) | merge_hooks($template.hooks))
    else . end
  ' "$target_file" "$template_file"); then
    echo -e "  ${RED}✗${NC}  Failed to merge settings.local.json — skipping"
    return
  fi

  if ! write_json_if_changed "$target_file" "$merged"; then
    echo -e "  ${GREEN}✓${NC} settings.local.json already up to date"
    return 0
  fi

  local after_deny after_allow
  after_deny=$(echo "$merged" | jq '.permissions.deny | length')
  after_allow=$(echo "$merged" | jq '.permissions.allow | length')
  local added_deny=$((after_deny - before_deny))
  local added_allow=$((after_allow - before_allow))

  # Plain if-blocks: a trailing `[[ … ]] && echo` would return 1 and abort the caller under set -e.
  if [[ $added_deny -gt 0 || $added_allow -gt 0 ]]; then
    echo -e "  ${GREEN}✓${NC} Merged settings.local.json"
    if [[ $added_allow -gt 0 ]]; then echo -e "       ${GREEN}+${added_allow}${NC} allow rule(s) added"; fi
    if [[ $added_deny -gt 0 ]]; then echo -e "       ${GREEN}+${added_deny}${NC} deny rule(s) added"; fi
  else
    echo -e "  ${GREEN}✓${NC} settings.local.json already up to date"
  fi
  return 0
}

# Shared, stack-agnostic safety policy, applied to EVERY project on deploy and --refresh.
# Source of truth: projects/common/security.settings.local.json + hooks/safety-guard.sh
# Additive only — nothing the project already has is removed:
#   permissions.deny / ask      policy entries appended (existing entries and order kept)
#   hooks                       PreToolUse safety-guard.sh registered once; other hooks kept; the
#                               managed entry's matcher follows the policy (e.g. MCP tools)
#   enableAllProjectMcpServers  set to false only when the project hasn't set it
# Existing allow rules that overlap an ask/deny rule are kept: Claude Code evaluates
# deny → ask → allow, so the policy still blocks or prompts. With --shared-policy the same rules
# also go into the committed .claude/settings.json so teammates are protected. The policy file
# itself is never copied into the project.
SECURITY_POLICY_FILE="$SCRIPT_DIR/projects/common/security.settings.local.json"

apply_security_policy() {
  local guard_src="$SCRIPT_DIR/projects/common/hooks/safety-guard.sh"
  local guard_dest="$PROJECT_DIR/.claude/hooks/safety-guard.sh"

  echo ""
  echo -e "${CYAN}Applying shared safety policy (deny/ask rules + safety-guard hook)...${NC}"

  if [[ ! -f "$SECURITY_POLICY_FILE" || ! -f "$guard_src" ]]; then
    echo -e "  ${RED}✗${NC}  Safety policy templates missing from $SCRIPT_DIR/projects/common — policy NOT applied"
    return 0
  fi

  do_copy "$guard_src" "$PROJECT_DIR/.claude/hooks/"
  if [[ "$DRY_RUN" != true && -f "$guard_dest" ]]; then chmod +x "$guard_dest"; fi
  if [[ "$DRY_RUN" != true && -f "$guard_dest" ]] && ! cmp -s "$guard_src" "$guard_dest"; then
    echo -e "  ${YELLOW}⚠${NC}  Your edited safety-guard.sh was kept — merge the staged version so new protections apply"
  fi

  # Stack templates carry no deny/ask rules, so skipping silently here would leave the
  # project with no secret-read protection at all.
  if ! command -v jq &>/dev/null; then
    echo -e "  ${RED}✗${NC}  jq not installed — deny/ask rules and hook registration were NOT applied."
    echo -e "      Install jq (brew install jq) and re-run with --refresh."
    return 0
  fi

  merge_security_policy "$PROJECT_DIR/.claude/settings.local.json"
  if [[ "$SHARED_POLICY" == true ]]; then
    merge_security_policy "$PROJECT_DIR/.claude/settings.json"
  fi
}

# merge_security_policy <settings-file> — merge the policy into one settings file (additive).
merge_security_policy() {
  local target_file="$1" label existing="{}" merged
  label=$(rel_path "$target_file")

  if [[ -f "$target_file" ]]; then
    if ! jq empty "$target_file" 2>/dev/null; then
      echo -e "  ${RED}✗${NC}  $label is invalid JSON — fix it and re-run; policy NOT applied"
      return 0
    fi
    existing=$(cat "$target_file")
  fi

  if ! merged=$(printf '%s' "$existing" | jq -s "$JQ_SETTINGS_DEFS"'
    .[0] as $e | .[1] as $p |
    ($p.hooks.PreToolUse[0].matcher // null) as $matcher |
    ((if ($e | has("$schema")) then {} else {"$schema": $p["$schema"]} end) + $e)
    | .enableAllProjectMcpServers = ($e.enableAllProjectMcpServers // false)
    | .permissions = (($e.permissions // {})
        | .deny = union($e.permissions.deny; $p.permissions.deny)
        | .ask = union($e.permissions.ask; $p.permissions.ask))
    | .hooks = ((.hooks // {}) | merge_hooks($p.hooks))
    | if $matcher then
        .hooks.PreToolUse |= map(if ([.hooks[]?.command | hook_key] | index([".claude/hooks/safety-guard.sh"])) != null then .matcher = $matcher else . end)
      else . end
  ' - "$SECURITY_POLICY_FILE"); then
    echo -e "  ${RED}✗${NC}  Failed to merge the safety policy — $label left unchanged"
    return 0
  fi

  local added_deny added_ask added_hooks overlapping matcher_changed
  IFS=$'\t' read -r added_deny added_ask added_hooks overlapping matcher_changed < <(
    jq -rn --argjson a "$existing" --argjson b "$merged" --slurpfile p "$SECURITY_POLICY_FILE" "$JQ_SETTINGS_DEFS"'
      def n(x): (x // []) | length;
      def guard_matcher(s): ([(s | .hooks.PreToolUse[]?) | select(([.hooks[]?.command | hook_key] | index([".claude/hooks/safety-guard.sh"])) != null) | .matcher] | first) // "";
      [(($p[0].permissions.ask // []) + ($p[0].permissions.deny // []))[] | norm_rule] as $pol |
      [ n($b.permissions.deny) - n($a.permissions.deny),
        n($b.permissions.ask) - n($a.permissions.ask),
        n($b.hooks.PreToolUse) - n($a.hooks.PreToolUse),
        ([($b.permissions.allow // [])[] | norm_rule | select(. as $r | any($pol[]; . == $r))] | length),
        (if guard_matcher($a) != "" and guard_matcher($a) != guard_matcher($b) then 1 else 0 end) ] | @tsv'
  )
  local summary="+${added_deny} deny, +${added_ask} ask, +${added_hooks} PreToolUse hook"
  if [[ "$matcher_changed" == "1" ]]; then summary="$summary, hook matcher updated"; fi

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} $label: $summary"
    return 0
  fi

  if write_json_if_changed "$target_file" "$merged"; then
    echo -e "  ${GREEN}✓${NC} $label: $summary"
  else
    echo -e "  ${GREEN}✓${NC} $label: safety policy already up to date"
  fi
  if [[ "$overlapping" -gt 0 ]]; then
    echo -e "  ${YELLOW}○${NC} ${overlapping} existing allow rule(s) in $label overlap the policy's ask/deny rules — kept; ask/deny take precedence"
  fi
  if [[ "$(printf '%s' "$merged" | jq -r '.enableAllProjectMcpServers')" == "true" ]]; then
    echo -e "  ${YELLOW}⚠${NC}  enableAllProjectMcpServers is true in $label (kept as set) — false starts only servers in enabledMcpjsonServers"
  fi
}

# --effort=<level>: pin the project's default reasoning effort. Lower effort spends fewer
# thinking tokens on adaptive-thinking models; the developer can still change it per session.
apply_effort_level() {
  [[ -n "$EFFORT_LEVEL" ]] || return 0
  local target_file="$PROJECT_DIR/.claude/settings.local.json"

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Set effortLevel=$EFFORT_LEVEL in settings.local.json"
    return 0
  fi
  if ! command -v jq &>/dev/null || [[ ! -f "$target_file" ]]; then
    echo -e "  ${YELLOW}⚠${NC}  Could not set effortLevel (requires jq and .claude/settings.local.json)"
    return 0
  fi

  local updated
  if updated=$(jq --arg e "$EFFORT_LEVEL" '.effortLevel = $e' "$target_file"); then
    if write_json_if_changed "$target_file" "$updated"; then
      echo -e "  ${GREEN}✓${NC} settings.local.json: effortLevel=$EFFORT_LEVEL"
    fi
  fi
}

deploy_agents_md() {
  local label="${1:-Deploying}"
  echo ""
  echo -e "${CYAN}${label} AGENTS.md (OpenAI Codex / API tools)...${NC}"

  local agents_template=""
  if [[ -f "$STACK_DIR/AGENTS.md.template" ]]; then
    agents_template="$STACK_DIR/AGENTS.md.template"
  elif [[ -f "$SCRIPT_DIR/projects/common/AGENTS.md.template" ]]; then
    agents_template="$SCRIPT_DIR/projects/common/AGENTS.md.template"
  fi

  if [[ -n "$agents_template" ]]; then
    install_rendered "$agents_template" "$PROJECT_DIR/AGENTS.md"
  else
    echo -e "  ${YELLOW}○${NC} No AGENTS.md template found for stack: $STACK"
  fi
}

# Detect whether a project already has the orchestrator pattern deployed.
# Used to make --refresh "sticky" (preserve orchestrator without re-passing the flag).
orchestrator_already_deployed() {
  local settings_file="$PROJECT_DIR/.claude/settings.local.json"
  [[ -f "$PROJECT_DIR/.claude/agents/implementer.md" ]] && return 0
  if [[ -f "$settings_file" ]] && command -v jq &>/dev/null; then
    local val
    val=$(jq -r '.env.CLAUDE_CODE_SUBAGENT_MODEL // empty' "$settings_file" 2>/dev/null)
    [[ -n "$val" ]] && return 0
  fi
  return 1
}

# Inject the Opus-orchestrator / Sonnet-subagent model config into settings.local.json.
#   - .model = "opus"                              (pin main session to Opus)
#   - .env.CLAUDE_CODE_SUBAGENT_MODEL = "sonnet"   (force every subagent to Sonnet)
# An explicit --orchestrator sets both. When the pattern is only carried forward (sticky
# refresh/redeploy), values the developer changed are kept and only missing keys are added.
inject_orchestrator_settings() {
  local settings_file="$1"

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Ensure model + env.CLAUDE_CODE_SUBAGENT_MODEL in settings.local.json"
    return 0
  fi

  if ! command -v jq &>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC}  jq not found — cannot set orchestrator model config (install jq to enable)"
    return 0
  fi

  local base="{}"
  if [[ -f "$settings_file" ]]; then
    if ! jq empty "$settings_file" 2>/dev/null; then
      echo -e "  ${YELLOW}⚠${NC}  settings.local.json is invalid JSON — orchestrator model config skipped"
      return 0
    fi
    base=$(cat "$settings_file")
  fi

  local program='.model //= "opus" | .env.CLAUDE_CODE_SUBAGENT_MODEL //= "sonnet"'
  if [[ "$ORCHESTRATOR_EXPLICIT" == true ]]; then
    program='.model = "opus" | .env.CLAUDE_CODE_SUBAGENT_MODEL = "sonnet"'
  fi

  local updated
  if ! updated=$(printf '%s' "$base" | jq "$program"); then
    echo -e "  ${RED}✗${NC}  Failed to set orchestrator model config — skipping"
    return 0
  fi

  if write_json_if_changed "$settings_file" "$updated"; then
    echo -e "  ${GREEN}✓${NC} settings.local.json: model=$(printf '%s' "$updated" | jq -r .model), subagents=$(printf '%s' "$updated" | jq -r .env.CLAUDE_CODE_SUBAGENT_MODEL)"
  else
    echo -e "  ${GREEN}✓${NC} Orchestrator model config already present"
  fi
}

# Append the delegation policy block to CLAUDE.md, idempotently.
append_orchestrator_policy() {
  append_managed_block "$1" "$2" "ORCHESTRATOR POLICY" "Model & Delegation Policy"
}

# Deploy the Opus-orchestrator + Sonnet-implementer pattern.
#   1. implementer subagent (Sonnet) → .claude/agents/implementer.md
#   2. model + env config           → .claude/settings.local.json
#   3. delegation policy block       → CLAUDE.md
deploy_orchestrator() {
  local label="${1:-Deploying}"
  echo ""
  echo -e "${CYAN}${label} Opus orchestrator + Sonnet implementer pattern...${NC}"

  local orch_dir="$SCRIPT_DIR/projects/common/orchestrator"

  if [[ -f "$orch_dir/implementer.md" ]]; then
    do_mkdir "$PROJECT_DIR/.claude/agents"
    do_copy "$orch_dir/implementer.md" "$PROJECT_DIR/.claude/agents/"
  else
    echo -e "  ${YELLOW}○${NC} implementer.md template not found — skipping subagent"
  fi

  inject_orchestrator_settings "$PROJECT_DIR/.claude/settings.local.json"
  append_orchestrator_policy "$PROJECT_DIR/CLAUDE.md" "$orch_dir/CLAUDE-orchestrator.md"
}

# append_managed_block <target.md> <block-template> <MARKER> <label>
# Refreshes a managed block — the text between "<!-- BEGIN <MARKER>" and
# "<!-- END <MARKER> -->" — in place, or appends it when absent. Content outside the markers
# is never touched, duplicate copies collapse to one, and the file is only written (after a
# backup) when the block actually changes.
append_managed_block() {
  local target="$1" template="$2" marker="$3" label="$4"

  if [[ ! -f "$template" ]]; then
    echo -e "  ${YELLOW}○${NC} $label template not found — skipping"
    return 0
  fi
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Refresh $label block in $(basename "$target")"
    return 0
  fi
  if [[ ! -f "$target" ]]; then
    echo -e "  ${YELLOW}○${NC} $(basename "$target") not found — skipping $label block"
    return 0
  fi

  local updated
  updated=$(mktemp)
  MARKER="$marker" BLOCK_FILE="$template" perl -0777 -ne '
    open(my $fh, "<", $ENV{BLOCK_FILE}) or die "cannot read $ENV{BLOCK_FILE}\n";
    my $block = do { local $/; <$fh> };
    $block =~ s/\n+\z//;
    my $m = quotemeta $ENV{MARKER};
    my $n = 0;
    s{\n?<!-- BEGIN $m.*?<!-- END $m -->\n?}{ $n++ ? "" : "\n$block\n" }gse;
    $_ .= "\n$block\n" unless $n;
    print;
  ' "$target" > "$updated"
  replace_if_changed "$target" "$updated" "$(basename "$target"): refreshed $label block"
}

remove_managed_block() {
  local updated
  updated=$(mktemp)
  MARKER="$2" perl -0777 -pe 's/\n?<!-- BEGIN \Q$ENV{MARKER}\E.*?<!-- END \Q$ENV{MARKER}\E -->\n?//gs' "$1" > "$updated"
  replace_if_changed "$1" "$updated" "$(basename "$1"): removed $2 block"
}

# replace_if_changed <target> <candidate> <message> — back up and overwrite only on a real change.
replace_if_changed() {
  if cmp -s "$1" "$2"; then
    rm -f "$2"
    return 0
  fi
  backup_file "$1"
  cat "$2" > "$1"
  rm -f "$2"
  echo -e "  ${GREEN}✓${NC} $3"
}

# Non-negotiable guardrails: no reading secrets, no unapproved push, no production changes.
append_safety_policy() {
  append_managed_block "$1" "$SCRIPT_DIR/projects/common/safety-guardrails.md" "SAFETY GUARDRAILS" "Operational Safety Guardrails"
}

# Read project memory before substantive work; log meaningful changes and decisions to it.
# With --okf-memory the OKF protocol (.okf/ bundle) replaces the MEMORY.md protocol block.
append_memory_policy() {
  if [[ "$OKF_MEMORY" == true ]]; then
    if [[ "$DRY_RUN" != true && -f "$1" ]]; then remove_managed_block "$1" "MEMORY PROTOCOL"; fi
    append_managed_block "$1" "$SCRIPT_DIR/projects/common/okf-memory-protocol.md" "OKF MEMORY PROTOCOL" "OKF Memory Protocol"
  else
    append_managed_block "$1" "$SCRIPT_DIR/projects/common/memory-protocol.md" "MEMORY PROTOCOL" "Project Memory Protocol"
  fi
}

# Front-End Stack block (what detection found); removed when nothing front-end is detected.
append_frontend_policy() {
  if [[ -n "$FRONTEND_BLOCK_FILE" && -f "$FRONTEND_BLOCK_FILE" ]]; then
    append_managed_block "$1" "$FRONTEND_BLOCK_FILE" "FRONTEND STACK" "Front-End Stack"
  elif [[ "$DRY_RUN" != true && -f "$1" ]]; then
    remove_managed_block "$1" "FRONTEND STACK"
  fi
}

# Points Claude at the codegraph MCP tools when this project has a registered code index.
append_code_index_policy() {
  if [[ "$CODE_INDEX" == true ]]; then
    append_managed_block "$1" "$SCRIPT_DIR/projects/common/code-index.md" "CODE INDEX" "Code Index"
  elif [[ "$DRY_RUN" != true && -f "$1" ]]; then
    remove_managed_block "$1" "CODE INDEX"
  fi
}

# Concise-output defaults — output tokens are the most expensive. Opt out: --no-response-style
# (which also strips a previously deployed block).
append_response_style_policy() {
  if [[ "$NO_RESPONSE_STYLE" == true ]]; then
    [[ "$DRY_RUN" != true && -f "$1" ]] && remove_managed_block "$1" "RESPONSE STYLE"
    return 0
  fi
  append_managed_block "$1" "$SCRIPT_DIR/projects/common/response-style.md" "RESPONSE STYLE" "Response Style"
}

# The always-on managed blocks, in a fixed order, for CLAUDE.md and AGENTS.md.
append_managed_policies() {
  append_safety_policy "$1"
  append_memory_policy "$1"
  append_response_style_policy "$1"
  append_frontend_policy "$1"
  append_code_index_policy "$1"
}

# Rewrite eager "@.claude/libraries/<lib>.md" imports as on-demand references.
# @imports expand into context at launch, so every session pays for every imported
# library (html5.md alone is ~19KB). A plain path lets Claude read a library only when
# the task involves it. --eager-libraries keeps the @imports.
convert_library_imports() {
  local claude_md="$1"
  [[ "$EAGER_LIBRARIES" == true || "$DRY_RUN" == true || ! -f "$claude_md" ]] && return 0

  local count
  count=$(grep -cE '^@(\./)?\.claude/libraries/[A-Za-z0-9._-]+\.md[[:space:]]*$' "$claude_md" || true)
  [[ "$count" -gt 0 ]] || return 0

  perl -i -pe '
    if (m{^@(?:\./)?\.claude/libraries/([A-Za-z0-9._-]+)\.md\s*$}) {
      my $lib = $1;
      $_ = ($in ? "" : "\n**Library references** (read one only when the task involves that library):\n")
         . "- `.claude/libraries/$lib.md`\n";
      $in = 1;
    } else {
      $in = 0;
    }' "$claude_md"
  echo -e "  ${GREEN}✓${NC} CLAUDE.md: ${count} library @import(s) → on-demand references (--eager-libraries keeps them)"
}

# Shared rule files maintained by ai-config. On --refresh a rule is updated when present
# (same curation contract as libraries); the two safety rules are restored if missing
# because the Safety Guardrails block in CLAUDE.md points at them.
refresh_common_rules() {
  local rules_dir="$PROJECT_DIR/.claude/rules"
  echo ""
  echo -e "${CYAN}Refreshing shared rules (present = update, safety rules = restore)...${NC}"
  local rule src
  for rule in deployment-safety.md sensitive-files.md token-optimization.md memory-management.md; do
    src="$SCRIPT_DIR/projects/common/rules/$rule"
    [[ -f "$src" ]] || continue
    if [[ -f "$rules_dir/$rule" || "$rule" == "deployment-safety.md" || "$rule" == "sensitive-files.md" ]]; then
      do_mkdir "$rules_dir"
      do_copy "$src" "$rules_dir/"
    fi
  done
}

# ============================================================================
# OKF Memory (--okf-memory) and Code Index (codegraph)
# ============================================================================

# --okf-memory: seed the Open Knowledge Format bundle (.okf/). Like MEMORY.md, the bundle is
# the project's own history — seed files are created only when missing, never overwritten.
deploy_okf_bundle() {
  local src="$SCRIPT_DIR/projects/common/okf" dir="$PROJECT_DIR/.okf" name now today
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  today=$(date -u +%Y-%m-%d)

  echo ""
  echo -e "${CYAN}OKF knowledge bundle (.okf/)...${NC}"
  for name in index.md log.md handoff.md; do
    if [[ -e "$dir/$name" ]]; then continue; fi
    if [[ "$DRY_RUN" == true ]]; then
      echo -e "  ${YELLOW}[DRY-RUN]${NC} Create .okf/$name"
      continue
    fi
    mkdir -p "$dir"
    sed -e "s/{{NOW}}/$now/g" -e "s/{{TODAY}}/$today/g" "$src/$name.template" > "$dir/$name.tmp"
    render_template "$dir/$name.tmp" "$dir/$name"
    rm -f "$dir/$name.tmp"
    CREATED_THIS_RUN+="$dir/$name"$'\n'
    COUNT_ADDED=$((COUNT_ADDED + 1))
    echo -e "  ${GREEN}✓${NC} Created .okf/$name"
  done

  do_copy "$src/okf-check.sh" "$PROJECT_DIR/.claude/scripts/"
  do_copy "$SCRIPT_DIR/projects/common/rules/okf-memory.md" "$PROJECT_DIR/.claude/rules/"

  # Let Claude run the checker without a permission prompt (allow entries are only added).
  local settings_file="$PROJECT_DIR/.claude/settings.local.json" updated
  if [[ "$DRY_RUN" != true && -f "$settings_file" ]] && command -v jq &>/dev/null && jq empty "$settings_file" 2>/dev/null; then
    updated=$(jq "$JQ_SETTINGS_DEFS"'.permissions.allow = union(.permissions.allow; ["Bash(bash .claude/scripts/okf-check.sh)", "Bash(bash .claude/scripts/okf-check.sh:*)"])' "$settings_file")
    write_json_if_changed "$settings_file" "$updated" || true
  fi

  update_template_map

  if [[ -f "$PROJECT_DIR/MEMORY.md" ]]; then
    echo -e "  ${YELLOW}○${NC} MEMORY.md kept as read-only history — new knowledge is recorded in .okf/"
  fi
  if [[ -d "$dir" ]]; then
    local report
    report=$(bash "$src/okf-check.sh" "$dir" 2>&1) || true
    printf '%s\n' "$report" | sed 's/^/  /'
  fi
}

# JS-framework stacks where a tree-sitter code index pays off. codegraph doesn't parse Twig,
# Blade, or ExpressionEngine templates, so monolithic PHP CMS stacks are left out.
code_index_stack() {
  case "$STACK" in
    nextjs|nuxt|astro|astro-sanity|astro-strapi|astro-tina|sveltekit|remix|t3-stack|docusaurus|craftcms-nextjs|craftcms-nuxt|ee-nextjs) return 0 ;;
    *) return 1 ;;
  esac
}

# Detect-and-register only: ai-config never installs codegraph or builds its index.
code_index_ready() {
  code_index_stack && command -v codegraph &>/dev/null && [[ -d "$PROJECT_DIR/.codegraph" ]]
}

register_code_index() {
  code_index_stack || return 0
  command -v codegraph &>/dev/null || return 0   # optional tool; stay quiet when absent

  echo ""
  echo -e "${CYAN}Code index (codegraph)...${NC}"
  local add_cmd="claude mcp add --scope local codegraph -- codegraph serve --mcp"
  if [[ ! -d "$PROJECT_DIR/.codegraph" ]]; then
    echo -e "  ${YELLOW}○${NC} codegraph is installed but this project has no index — run 'codegraph init' in the project, then --refresh"
    return 0
  fi
  if ! command -v claude &>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC}  claude CLI not found — register manually: $add_cmd"
    return 0
  fi
  if (cd "$PROJECT_DIR" && claude mcp get codegraph) </dev/null &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} codegraph MCP server already registered"
    return 0
  fi
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} $add_cmd"
    return 0
  fi
  if (cd "$PROJECT_DIR" && claude mcp add --scope local codegraph -- codegraph serve --mcp) </dev/null &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Registered codegraph MCP server (local scope: this machine and project only)"
  else
    echo -e "  ${YELLOW}⚠${NC}  Could not register codegraph — run in the project: $add_cmd"
  fi
}

# ============================================================================
# PHP Code Intelligence (php-lsp) and Template Map
# ============================================================================

PHP_LSP_PLUGIN="php-lsp@claude-plugins-official"

# PHP stacks: themes, plugins, modules, and add-ons get Intelephense code intelligence.
php_lsp_stack() {
  case "$STACK" in
    expressionengine|coilpack|ee-nextjs|craftcms|craftcms-nuxt|craftcms-nextjs|wordpress|wordpress-roots) return 0 ;;
    *) return 1 ;;
  esac
}

# plugin_setting <settings-file> <plugin> — prints "true"/"false" when the file sets the plugin
# explicitly, nothing otherwise.
plugin_setting() {
  if [[ ! -f "$1" ]] || ! command -v jq &>/dev/null; then return 0; fi
  jq -r --arg p "$2" 'if ((.enabledPlugins // {}) | has($p)) then (.enabledPlugins[$p] | tostring) else empty end' "$1" 2>/dev/null || true
}

# Enable the official php-lsp plugin for this project when Intelephense is installed. The
# plugin only tells Claude Code how to reach the language server; Intelephense itself must
# already be on PATH. An explicit true/false in project or user settings is always respected.
enable_php_lsp() {
  php_lsp_stack || return 0
  local install_cmd="claude plugin install $PHP_LSP_PLUGIN --scope local"
  local project_choice user_choice

  echo ""
  echo -e "${CYAN}PHP code intelligence (php-lsp)...${NC}"
  if ! command -v intelephense &>/dev/null; then
    echo -e "  ${YELLOW}○${NC} Intelephense not installed — for PHP go-to-definition and references, re-run with --refresh --install-deps (or npm install -g intelephense)"
    return 0
  fi

  project_choice=$(plugin_setting "$PROJECT_DIR/.claude/settings.local.json" "$PHP_LSP_PLUGIN")
  if [[ -z "$project_choice" ]]; then
    project_choice=$(plugin_setting "$PROJECT_DIR/.claude/settings.json" "$PHP_LSP_PLUGIN")
  fi
  user_choice=$(plugin_setting "${AI_CONFIG_USER_SETTINGS:-$HOME/.claude/settings.json}" "$PHP_LSP_PLUGIN")

  if [[ "$project_choice" == "true" || ( -z "$project_choice" && "$user_choice" == "true" ) ]]; then
    echo -e "  ${GREEN}✓${NC} php-lsp already enabled"
    return 0
  fi
  if [[ "$project_choice" == "false" || ( -z "$project_choice" && "$user_choice" == "false" ) ]]; then
    echo -e "  ${YELLOW}○${NC} php-lsp is disabled in your settings — left as set"
    return 0
  fi
  if ! command -v claude &>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC}  claude CLI not found — enable manually in the project: $install_cmd"
    return 0
  fi
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} $install_cmd"
    return 0
  fi

  backup_file "$PROJECT_DIR/.claude/settings.local.json"
  if (cd "$PROJECT_DIR" && claude plugin install "$PHP_LSP_PLUGIN" --scope local) </dev/null &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Enabled php-lsp for this project (local scope; Intelephense: $(command -v intelephense))"
  else
    echo -e "  ${YELLOW}⚠${NC}  Could not enable php-lsp — run in the project: $install_cmd"
  fi
}

# Stacks whose templates (EE tags, Twig, Blade) no code index parses.
template_map_stack() {
  case "$STACK" in
    expressionengine|coilpack|ee-nextjs|craftcms|craftcms-nuxt|craftcms-nextjs|wordpress-roots) return 0 ;;
    *) return 1 ;;
  esac
}

# With --okf-memory, keep .okf/architecture/templates.md in sync with template source. Only a
# change in relationships counts (never just the timestamp), and a developer-edited map is
# kept with the new version staged, like any other shipped file.
update_template_map() {
  if [[ "$OKF_MEMORY" != true ]] || ! template_map_stack; then return 0; fi
  local dest="$PROJECT_DIR/.okf/architecture/templates.md" work candidate now
  work=$(mktemp -d)
  candidate="$work/templates.md"
  bash "$SCRIPT_DIR/projects/common/okf/template-map.sh" "$PROJECT_DIR" > "$candidate" 2>/dev/null || true

  if [[ ! -s "$candidate" ]]; then
    rm -rf "$work"
    return 0
  fi
  if [[ -f "$dest" ]] && sed -E 's/^(generated: \{ by: "process:ai-config\/template-map", at: ")[^"]*(" \})$/\1__GENERATED_AT__\2/' "$dest" | cmp -s "$candidate" -; then
    rm -rf "$work"
    return 0
  fi

  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sed_inplace "s/__GENERATED_AT__/$now/" "$candidate"
  do_copy "$candidate" "$dest"
  link_template_map
  rm -rf "$work"
}

# Link the template map from .okf/index.md once — an append-only edit, backed up first.
link_template_map() {
  local index="$PROJECT_DIR/.okf/index.md" updated
  if [[ "$DRY_RUN" == true || ! -f "$index" || ! -f "$PROJECT_DIR/.okf/architecture/templates.md" ]]; then return 0; fi
  if grep -qF '/architecture/templates.md' "$index"; then return 0; fi
  updated=$(mktemp)
  LINE='- [Template map](/architecture/templates.md) — generated: which templates extend, include, or embed which' \
    perl -0777 -pe 's/^(## Architecture[ \t]*\n)/$1\n$ENV{LINE}\n/m or $_ .= "\n## Architecture\n\n$ENV{LINE}\n"' "$index" > "$updated"
  replace_if_changed "$index" "$updated" ".okf/index.md: linked the template map"
}

# ============================================================================
# Prerequisites and Health Check (--doctor)
# ============================================================================

REQUIRED_TOOLS="jq perl awk sed find cmp mktemp"

missing_required_tools() {
  local tool missing=""
  for tool in $REQUIRED_TOOLS; do
    if ! command -v "$tool" &>/dev/null; then missing="$missing $tool"; fi
  done
  if ! command -v shasum &>/dev/null && ! command -v sha256sum &>/dev/null; then
    missing="$missing shasum/sha256sum"
  fi
  printf '%s' "${missing# }"
}

# Before anything changes: required tools power the safety policy merge and the additive update
# rules, so a missing one stops the run instead of silently skipping protections.
check_prerequisites() {
  local missing
  missing=$(missing_required_tools)
  if [[ -z "$missing" ]]; then return 0; fi
  echo -e "${RED}✗ Missing required tools: ${missing}${NC}"
  echo "  They power the safety policy merge and the additive update rules; nothing was changed."
  echo "  Re-run with --install-deps, or install them with your package manager (e.g. brew install jq / sudo apt-get install jq)."
  if [[ "$DRY_RUN" == true ]]; then return 0; fi
  exit 1
}

HC_FAILURES=0
HC_WARNINGS=0
HC_VERBOSE=false   # --doctor lists passing checks too; deploy/refresh show only problems
hc_ok()   { if [[ "$HC_VERBOSE" == true ]]; then echo -e "  ${GREEN}✓${NC} $1"; fi; }
hc_info() { if [[ "$HC_VERBOSE" == true ]]; then echo -e "  ${CYAN}○${NC} $1"; fi; }
hc_warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; HC_WARNINGS=$((HC_WARNINGS + 1)); }
hc_fail() { echo -e "  ${RED}✗${NC}  $1"; HC_FAILURES=$((HC_FAILURES + 1)); }

# verify_deployment — read-only checks that the deployed configuration works (not just that
# files exist): tools, settings, a live safety-hook test, managed blocks, memory, code index,
# php-lsp, and gitignore. Returns 1 when a critical check fails.
verify_deployment() {
  local settings="$PROJECT_DIR/.claude/settings.local.json"
  local policy="$SCRIPT_DIR/projects/common/security.settings.local.json"
  local guard="$PROJECT_DIR/.claude/hooks/safety-guard.sh"
  local claude_md="$PROJECT_DIR/CLAUDE.md"
  local missing count rule report choice import target server shared f deployed current
  HC_FAILURES=0
  HC_WARNINGS=0

  # Tools
  missing=$(missing_required_tools)
  if [[ -z "$missing" ]]; then
    hc_ok "Required tools present ($REQUIRED_TOOLS, shasum)"
  else
    hc_fail "Missing required tools: $missing"
  fi
  if ! command -v git &>/dev/null; then
    hc_warn "git not found — legacy files can't be matched to shipped versions and superpowers won't auto-update"
  fi
  if [[ -f "$AI_CONFIG_DIR/version" ]]; then
    deployed=$(sed -n 's/^commit=//p' "$AI_CONFIG_DIR/version")
    current=$(ai_config_commit)
    hc_ok "Deployed by ai-config ${deployed:-unknown} ($(sed -n 's/^deployed_at=//p' "$AI_CONFIG_DIR/version"))"
    if [[ -n "$deployed" && "${deployed%+dirty}" != "${current%+dirty}" ]]; then
      hc_info "ai-config has changed since this project was last deployed (now $current) — run --refresh"
    fi
  fi

  # Settings and safety policy
  if [[ ! -f "$settings" ]]; then
    hc_fail ".claude/settings.local.json missing — run: ai-config --refresh --project=$PROJECT_DIR"
  elif ! command -v jq &>/dev/null || ! jq empty "$settings" 2>/dev/null; then
    hc_fail ".claude/settings.local.json can't be read as JSON — Claude Code ignores an invalid file"
  else
    count=$(jq -n --slurpfile s "$settings" --slurpfile p "$policy" \
      '[(($p[0].permissions.deny // []) + ($p[0].permissions.ask // []))[] | select(. as $r | ((($s[0].permissions.deny // []) + ($s[0].permissions.ask // [])) | index([$r])) == null)] | length')
    if [[ "$count" == "0" ]]; then
      hc_ok "Safety policy rules present ($(jq '(.permissions.deny // []) | length' "$settings") deny, $(jq '(.permissions.ask // []) | length' "$settings") ask)"
    else
      hc_fail "$count shared deny/ask rule(s) missing from settings.local.json — run --refresh"
    fi
    if jq -e '[.hooks.PreToolUse[]?.hooks[]?.command | select(test("safety-guard\\.sh"))] | length > 0' "$settings" >/dev/null 2>&1; then
      hc_ok "safety-guard.sh registered as a PreToolUse hook"
    else
      hc_fail "safety-guard.sh is not registered as a PreToolUse hook — run --refresh"
    fi
    if jq -e '[.hooks.SessionStart[]?.hooks[]?.command | select(test("hooks/session-start"))] | length > 0' "$settings" >/dev/null 2>&1; then
      if [[ ! -x "$PROJECT_DIR/.claude/hooks/session-start" ]]; then
        hc_fail "SessionStart hook is registered but .claude/hooks/session-start is missing or not executable"
      elif ! jq -e '[.hooks.SessionStart[]?.hooks[]?.command | select(test("CLAUDE_PLUGIN_ROOT"))] | length > 0' "$settings" >/dev/null 2>&1; then
        hc_warn "SessionStart hook registration predates the superpowers fix — run --refresh"
      elif report=$(cd "$PROJECT_DIR" && CLAUDE_PLUGIN_ROOT="$PROJECT_DIR/.claude" bash .claude/hooks/session-start 2>&1) \
        && grep -q '"additionalContext"' <<< "$report" && ! grep -q 'Error reading' <<< "$report"; then
        hc_ok "SessionStart hook loads the using-superpowers skill"
      else
        hc_fail "SessionStart hook doesn't load .claude/skills/using-superpowers/SKILL.md — run --refresh"
      fi
    fi
    while IFS= read -r server; do
      [[ -n "$server" ]] || continue
      if [[ ! -f "$PROJECT_DIR/.mcp.json" ]] || ! jq -e --arg s "$server" '(.mcpServers // {}) | has($s)' "$PROJECT_DIR/.mcp.json" >/dev/null 2>&1; then
        hc_info "enabledMcpjsonServers lists '$server' but no .mcp.json defines it (context7 is also a plugin: /plugin install context7@claude-plugins-official)"
      fi
    done < <(jq -r '(.enabledMcpjsonServers // [])[]' "$settings" 2>/dev/null)
  fi
  if [[ -d "$PROJECT_DIR/.claude/skills/superpowers" ]]; then
    hc_warn "Skills in .claude/skills/superpowers/ aren't discovered by Claude Code — run --refresh (with a --superpowers-* flag if the plugin is global) or delete them"
  fi
  if [[ "$SHARED_POLICY" == true ]]; then
    shared="$PROJECT_DIR/.claude/settings.json"
    if [[ -f "$shared" ]] && jq -e '[.hooks.PreToolUse[]?.hooks[]?.command | select(test("safety-guard\\.sh"))] | length > 0' "$shared" >/dev/null 2>&1; then
      hc_ok "Shared safety policy present in .claude/settings.json"
    else
      hc_fail "--shared-policy is on but .claude/settings.json lacks the safety hook — run --refresh"
    fi
    if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
      for f in .claude/settings.json .claude/hooks/safety-guard.sh; do
        if git -C "$PROJECT_DIR" check-ignore -q "$f" 2>/dev/null; then
          hc_warn "$f is gitignored, so teammates won't receive it — run --refresh"
        fi
      done
    fi
  fi

  # Safety hook: run it against a known-bad call
  if [[ ! -x "$guard" ]]; then
    hc_fail ".claude/hooks/safety-guard.sh missing or not executable — run --refresh"
  elif printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' | bash "$guard" 2>/dev/null | grep -q '"permissionDecision":"deny"'; then
    hc_ok "safety-guard.sh blocks a test secret read"
  else
    hc_fail "safety-guard.sh did not block a test secret read (it needs jq or python3 on PATH)"
  fi
  if [[ -f "$PENDING_DIR/.claude/hooks/safety-guard.sh" ]]; then
    hc_warn "safety-guard.sh has local edits and a newer version is staged — merge .claude/ai-config/pending/.claude/hooks/safety-guard.sh"
  fi

  # Always-on instructions and shared rules
  if [[ ! -f "$claude_md" ]]; then
    hc_fail "CLAUDE.md missing — run --refresh"
  else
    if grep -q '<!-- BEGIN SAFETY GUARDRAILS' "$claude_md"; then
      hc_ok "CLAUDE.md: Safety Guardrails block"
    else
      hc_fail "CLAUDE.md has no Safety Guardrails block — run --refresh"
    fi
    if grep -qE '<!-- BEGIN (OKF )?MEMORY PROTOCOL' "$claude_md"; then
      hc_ok "CLAUDE.md: memory protocol block"
    else
      hc_warn "CLAUDE.md has no memory protocol block — run --refresh"
    fi
    if ! grep -q '<!-- BEGIN RESPONSE STYLE' "$claude_md"; then
      hc_info "CLAUDE.md has no Response Style block (expected only with --no-response-style)"
    fi
    # An @import of a missing file loads nothing, silently.
    while IFS= read -r import; do
      target="${import#@}"
      case "$target" in
        \~/*) target="$HOME/${target:2}" ;;
        /*) ;;
        *) target="$PROJECT_DIR/${target#./}" ;;
      esac
      if [[ ! -f "$target" ]]; then
        case "$import" in
          "@~/.claude/stacks/"*) hc_warn "CLAUDE.md imports ${import#@}, which doesn't exist on this machine — run install.sh from claude-optimizer" ;;
          *) hc_warn "CLAUDE.md imports ${import#@}, which doesn't exist" ;;
        esac
      elif [[ "$import" == "@~/.claude/stacks/"* && -f "$SCRIPT_DIR/stacks/${import##*/}" ]] && ! cmp -s "$target" "$SCRIPT_DIR/stacks/${import##*/}"; then
        hc_warn "${import#@} is out of date with claude-optimizer/stacks — re-run install.sh"
      fi
    done < <(awk '/^[[:space:]]*```/ { fence = !fence; next } !fence && /^@(~\/|\.\/|\/|\.claude\/)[A-Za-z0-9_.\/-]+\.md[[:space:]]*$/ { sub(/[[:space:]]+$/, ""); print }' "$claude_md")
  fi
  for rule in deployment-safety.md sensitive-files.md; do
    if [[ ! -f "$PROJECT_DIR/.claude/rules/$rule" ]]; then
      hc_warn ".claude/rules/$rule missing — run --refresh to restore it"
    fi
  done

  # Project memory
  if [[ -f "$PROJECT_DIR/.okf/index.md" ]]; then
    if report=$(bash "$SCRIPT_DIR/projects/common/okf/okf-check.sh" "$PROJECT_DIR/.okf" 2>&1); then
      hc_ok "OKF bundle conformant — $(printf '%s\n' "$report" | tail -n 1)"
    else
      hc_warn "OKF bundle has conformance errors — run: bash .claude/scripts/okf-check.sh"
    fi
  elif [[ -f "$PROJECT_DIR/MEMORY.md" ]]; then
    hc_ok "MEMORY.md present"
  else
    hc_warn "No project memory (MEMORY.md or .okf/) — run --refresh"
  fi
  count=$(find "$PENDING_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$count" != "0" ]]; then
    hc_info "$count staged update(s) in .claude/ai-config/pending/ (adopt with --apply-pending)"
  fi

  # Code index (JS-framework stacks)
  if code_index_stack; then
    if ! command -v codegraph &>/dev/null; then
      if grep -q '<!-- BEGIN CODE INDEX' "$claude_md" 2>/dev/null; then
        hc_warn "CLAUDE.md points at codegraph but it isn't installed — install it, or --refresh to drop the block"
      else
        hc_info "Optional: codegraph (local code index) isn't installed"
      fi
    elif [[ ! -d "$PROJECT_DIR/.codegraph" ]]; then
      hc_info "codegraph installed but this project has no index — run 'codegraph init', then --refresh"
    elif command -v claude &>/dev/null && (cd "$PROJECT_DIR" && claude mcp get codegraph) </dev/null &>/dev/null; then
      hc_ok "codegraph MCP server registered"
    else
      hc_warn "codegraph index exists but the MCP server isn't registered — run --refresh"
    fi
  fi

  # PHP code intelligence (PHP stacks)
  if php_lsp_stack; then
    choice=$(plugin_setting "$settings" "$PHP_LSP_PLUGIN")
    if [[ -z "$choice" ]]; then choice=$(plugin_setting "$PROJECT_DIR/.claude/settings.json" "$PHP_LSP_PLUGIN"); fi
    if [[ -z "$choice" ]]; then choice=$(plugin_setting "${AI_CONFIG_USER_SETTINGS:-$HOME/.claude/settings.json}" "$PHP_LSP_PLUGIN"); fi
    if [[ "$choice" == "true" ]]; then
      if command -v intelephense &>/dev/null; then
        hc_ok "php-lsp enabled and intelephense on PATH"
      else
        hc_warn "php-lsp is enabled but intelephense isn't on PATH — run --install-deps (or npm install -g intelephense)"
      fi
    elif [[ "$choice" != "false" ]]; then
      if command -v intelephense &>/dev/null; then
        hc_info "intelephense installed but php-lsp isn't enabled — run --refresh"
      else
        hc_info "Optional: --refresh --install-deps (or npm install -g intelephense) for PHP code intelligence"
      fi
    fi
  fi

  # Backups and staged files must never be committed
  if [[ -d "$AI_CONFIG_DIR" ]] && git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null \
    && ! git -C "$PROJECT_DIR" check-ignore -q "$AI_CONFIG_DIR/manifest.tsv" 2>/dev/null; then
    hc_warn ".claude/ai-config/ isn't gitignored — backups could be committed (run --refresh)"
  fi

  if [[ $HC_FAILURES -gt 0 ]]; then
    echo -e "  ${RED}Health check: ${HC_FAILURES} failure(s), ${HC_WARNINGS} warning(s)${NC}"
    return 1
  fi
  echo -e "  ${GREEN}Health check: 0 failures, ${HC_WARNINGS} warning(s)${NC}"
  return 0
}

# ============================================================================
# Dependency Installation (--install-deps)
# ============================================================================

# Package manager for --install-deps: Homebrew on macOS; apt-get, dnf, yum, pacman, zypper, or
# apk on Linux. AI_CONFIG_PKG_MANAGER overrides detection ("none" disables installation).
detect_package_manager() {
  local pm
  if [[ -n "${AI_CONFIG_PKG_MANAGER:-}" ]]; then
    if [[ "$AI_CONFIG_PKG_MANAGER" != "none" ]]; then printf '%s' "$AI_CONFIG_PKG_MANAGER"; fi
    return 0
  fi
  if [[ "$OSTYPE" == darwin* ]]; then
    if command -v brew &>/dev/null; then printf 'brew'; fi
    return 0
  fi
  for pm in apt-get dnf yum pacman zypper apk brew; do
    if command -v "$pm" &>/dev/null; then
      printf '%s' "$pm"
      return 0
    fi
  done
}

# package_for <command> <manager> — the package that provides a command.
package_for() {
  case "$1" in
    awk)       echo "gawk" ;;
    find)      echo "findutils" ;;
    cmp)       echo "diffutils" ;;
    mktemp)    echo "coreutils" ;;
    sha256sum) if [[ "$2" == "brew" ]]; then echo "perl"; else echo "coreutils"; fi ;;
    *)         echo "$1" ;;
  esac
}

# pkg_install_cmd <manager> <packages...> — sets PKG_CMD to the non-interactive install command.
# System package managers get sudo when not running as root; Homebrew never does.
pkg_install_cmd() {
  local pm="$1"
  shift
  PKG_CMD=()
  if [[ "$pm" != "brew" && "$(id -u)" != "0" ]] && command -v sudo &>/dev/null; then
    PKG_CMD=(sudo)
  fi
  case "$pm" in
    brew)    PKG_CMD+=(brew install) ;;
    apt-get) PKG_CMD+=(apt-get install -y) ;;
    dnf)     PKG_CMD+=(dnf install -y) ;;
    yum)     PKG_CMD+=(yum install -y) ;;
    pacman)  PKG_CMD+=(pacman -S --needed --noconfirm) ;;
    zypper)  PKG_CMD+=(zypper --non-interactive install) ;;
    apk)     PKG_CMD+=(apk add) ;;
  esac
  PKG_CMD+=("$@")
}

run_pkg_install() {
  local pm="$1"
  shift
  pkg_install_cmd "$pm" "$@"
  if "${PKG_CMD[@]}"; then return 0; fi
  if [[ "$pm" == "apt-get" ]]; then
    # A fresh machine may have no package lists yet: update once, then retry.
    if [[ "${PKG_CMD[0]}" == "sudo" ]]; then
      sudo apt-get update && "${PKG_CMD[@]}"
    else
      apt-get update && "${PKG_CMD[@]}"
    fi
    return $?
  fi
  return 1
}

# Tools --install-deps deliberately leaves to the developer.
report_manual_deps() {
  if code_index_stack && ! command -v codegraph &>/dev/null; then
    echo -e "  ${YELLOW}○${NC} Not auto-installed (optional): codegraph — its installer pipes a remote script. See https://github.com/colbymchenry/codegraph, then run 'codegraph init'"
  fi
  if ! command -v claude &>/dev/null; then
    echo -e "  ${YELLOW}○${NC} claude CLI not on PATH — needed to register codegraph and enable php-lsp (install Claude Code yourself)"
  fi
}

# --install-deps: install what this project's configuration needs, before anything else runs.
#   required    jq, perl, awk, sed, find, cmp, mktemp, shasum/sha256sum
#   optional    git (legacy-file matching, superpowers updates)
#   PHP stacks  Intelephense via npm, plus Node.js/npm from the package manager when missing
# Never installs a package manager, never pipes remote install scripts, never runs npm with sudo.
# Shows the plan and asks first on a terminal unless --force; --dry-run only shows the plan.
install_dependencies() {
  if [[ "$INSTALL_DEPS" != true ]]; then return 0; fi
  echo -e "${CYAN}Checking dependencies (--install-deps)...${NC}"

  local pm tool
  local missing=() packages=()
  local need_intelephense=false need_node=false
  pm=$(detect_package_manager)

  for tool in $REQUIRED_TOOLS git; do
    if ! command -v "$tool" &>/dev/null; then missing+=("$tool"); fi
  done
  if ! command -v shasum &>/dev/null && ! command -v sha256sum &>/dev/null; then
    missing+=("sha256sum")
  fi
  if php_lsp_stack && ! command -v intelephense &>/dev/null; then
    need_intelephense=true
    if ! command -v npm &>/dev/null; then need_node=true; fi
  fi

  for tool in "${missing[@]}"; do
    packages+=("$(package_for "$tool" "$pm")")
  done
  if [[ "$need_node" == true ]]; then
    if [[ "$pm" == "brew" ]]; then packages+=(node); else packages+=(nodejs npm); fi
  fi
  if [[ ${#packages[@]} -gt 0 ]]; then
    # shellcheck disable=SC2207  # package names never contain whitespace
    packages=($(printf '%s\n' "${packages[@]}" | awk '!seen[$0]++'))
  fi

  if [[ ${#packages[@]} -eq 0 && "$need_intelephense" != true ]]; then
    echo -e "  ${GREEN}✓${NC} All dependencies already installed"
    report_manual_deps
    echo ""
    return 0
  fi

  if [[ ${#packages[@]} -gt 0 ]]; then
    if [[ -z "$pm" ]]; then
      echo -e "  ${RED}✗${NC}  No supported package manager found (Homebrew on macOS; apt-get, dnf, yum, pacman, zypper, or apk on Linux)"
      echo -e "      Install manually: ${packages[*]}"
    else
      pkg_install_cmd "$pm" "${packages[@]}"
      echo -e "  Will run: ${PKG_CMD[*]}"
    fi
  fi
  if [[ "$need_intelephense" == true ]]; then
    echo -e "  Will run: npm install -g intelephense   (PHP code intelligence for php-lsp)"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Nothing installed"
    echo ""
    return 0
  fi
  if [[ -t 0 && "$FORCE" != true ]]; then
    read -p "  Install these now? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo -e "  ${YELLOW}○${NC} Skipped dependency installation"
      echo ""
      return 0
    fi
  fi

  if [[ ${#packages[@]} -gt 0 && -n "$pm" ]]; then
    if run_pkg_install "$pm" "${packages[@]}"; then
      echo -e "  ${GREEN}✓${NC} Installed: ${packages[*]}"
    else
      echo -e "  ${RED}✗${NC}  Package installation failed — see the output above"
    fi
  fi
  hash -r

  if [[ "$need_intelephense" == true ]]; then
    if ! command -v npm &>/dev/null; then
      echo -e "  ${YELLOW}⚠${NC}  npm isn't available, so Intelephense wasn't installed — install Node.js, then re-run with --install-deps"
    elif npm install -g intelephense; then
      hash -r
      echo -e "  ${GREEN}✓${NC} Installed intelephense"
    else
      echo -e "  ${YELLOW}⚠${NC}  npm install -g intelephense failed. For a permissions error, use a user-owned prefix"
      echo -e "      (npm config set prefix ~/.npm-global, add ~/.npm-global/bin to PATH) rather than sudo"
    fi
  fi

  report_manual_deps
  echo ""
}

# ============================================================================
# Uninstall (--uninstall)
# ============================================================================

MANAGED_BLOCK_MARKERS=("SAFETY GUARDRAILS" "MEMORY PROTOCOL" "OKF MEMORY PROTOCOL" "RESPONSE STYLE" "FRONTEND STACK" "CODE INDEX" "ORCHESTRATOR POLICY")

# --uninstall removes ai-config from a project without losing work. Everything deleted or changed
# is backed up to .claude/ai-config/backups/<run>/ first.
#   removed   shipped files still identical to what ai-config wrote (per the manifest), an unedited
#             generated CLAUDE.md/AGENTS.md, the policy's deny/ask rules, ai-config hook registrations
#   stripped  managed blocks from an edited CLAUDE.md / AGENTS.md
#   kept      files you edited, MEMORY.md, the .okf/ bundle, .gitignore entries, plugin and MCP
#             registrations, other settings, and the backups themselves
do_uninstall() {
  echo -e "${BLUE}Uninstalling ai-config (everything removed is backed up first)...${NC}"
  echo ""
  local rel sha abs name marker settings updated removed=0 kept=0

  # 1. Shipped files, per the manifest (last entry per path wins)
  if [[ -f "$MANIFEST_FILE" ]]; then
    while IFS=$'\t' read -r rel sha; do
      # Settings files are cleaned in step 3; memory and the OKF bundle are project history.
      case "$rel" in ""|CLAUDE.md|AGENTS.md|MEMORY.md|MEMORY-ARCHIVE.md|.okf/*|.claude/settings.local.json|.claude/settings.json) continue ;; esac
      abs="$PROJECT_DIR/$rel"
      [[ -f "$abs" ]] || continue
      if [[ "$(file_sha "$abs")" == "$sha" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
          echo -e "  ${YELLOW}[DRY-RUN]${NC} Remove $rel"
        else
          backup_file "$abs"
          rm -f "$abs"
          echo -e "  ${GREEN}✓${NC} Removed $rel"
        fi
        removed=$((removed + 1))
      else
        echo -e "  ${YELLOW}○${NC} Kept $rel (you edited it)"
        kept=$((kept + 1))
      fi
    done < <(awk -F'\t' '{ if (!($1 in h)) order[++n] = $1; h[$1] = $2 } END { for (i = 1; i <= n; i++) print order[i] "\t" h[order[i]] }' "$MANIFEST_FILE")
  else
    echo -e "  ${YELLOW}○${NC} No manifest (deployed before ai-config tracked its files) — shipped files left in place"
  fi

  # 2. CLAUDE.md / AGENTS.md: remove if unedited, otherwise strip only the managed blocks
  for name in CLAUDE.md AGENTS.md; do
    abs="$PROJECT_DIR/$name"
    [[ -f "$abs" ]] || continue
    if [[ -n "$(manifest_get "$name")" && "$(manifest_get "$name")" == "$(file_sha "$abs")" ]]; then
      if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} Remove $name (generated, unedited)"
      else
        backup_file "$abs"
        rm -f "$abs"
        echo -e "  ${GREEN}✓${NC} Removed $name (generated, unedited)"
      fi
      removed=$((removed + 1))
    elif [[ "$DRY_RUN" == true ]]; then
      echo -e "  ${YELLOW}[DRY-RUN]${NC} Strip ai-config managed blocks from $name (your content kept)"
    else
      for marker in "${MANAGED_BLOCK_MARKERS[@]}"; do
        remove_managed_block "$abs" "$marker"
      done
    fi
  done

  # 3. Settings: the policy's deny/ask rules and ai-config hook registrations
  for settings in "$PROJECT_DIR/.claude/settings.local.json" "$PROJECT_DIR/.claude/settings.json"; do
    [[ -f "$settings" ]] || continue
    if ! jq empty "$settings" 2>/dev/null; then
      echo -e "  ${YELLOW}⚠${NC}  $(rel_path "$settings") is invalid JSON — left unchanged"
      continue
    fi
    updated=$(jq --slurpfile p "$SECURITY_POLICY_FILE" "$JQ_SETTINGS_DEFS"'
      (($p[0].permissions.deny // []) + ($p[0].permissions.ask // [])) as $pol
      | if .permissions then
          .permissions.deny = ((.permissions.deny // []) - $pol)
          | .permissions.ask = ((.permissions.ask // []) - $pol)
        else . end
      | if .hooks then
          .hooks |= (with_entries(.value = ((.value // [])
              | map(.hooks = ((.hooks // []) | map(select(((.command // "") | hook_key) as $k
                  | ([".claude/hooks/safety-guard.sh", ".claude/hooks/session-start"] | index([$k])) == null))))
              | map(select((.hooks | length) > 0))))
            | with_entries(select((.value | length) > 0)))
          | if .hooks == {} then del(.hooks) else . end
        else . end' "$settings")
    if [[ "$DRY_RUN" == true ]]; then
      if [[ "$(jq -S -c . "$settings")" != "$(printf '%s' "$updated" | jq -S -c .)" ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} Remove ai-config rules and hook registrations from $(rel_path "$settings")"
      fi
    elif write_json_if_changed "$settings" "$updated"; then
      echo -e "  ${GREEN}✓${NC} Removed ai-config rules and hook registrations from $(rel_path "$settings")"
    fi
  done

  if [[ "$DRY_RUN" != true ]]; then
    # 4. Empty folders left behind (never the backups), and manifest entries for removed files
    if [[ -d "$PROJECT_DIR/.claude" ]]; then
      find "$PROJECT_DIR/.claude" -mindepth 1 -depth -type d -empty ! -path "$AI_CONFIG_DIR" ! -path "$AI_CONFIG_DIR/*" -delete 2>/dev/null || true
    fi
    if [[ -f "$MANIFEST_FILE" ]]; then
      while IFS=$'\t' read -r rel sha; do
        if [[ -f "$PROJECT_DIR/$rel" ]]; then printf '%s\t%s\n' "$rel" "$sha"; fi
      done < "$MANIFEST_FILE" > "$MANIFEST_FILE.tmp"
      if [[ -s "$MANIFEST_FILE.tmp" ]]; then mv "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"; else rm -f "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"; fi
    fi
    RUN_MODE=uninstall
    write_version_stamp
  fi

  echo ""
  echo -e "${CYAN}Left in place:${NC}"
  if [[ -f "$PROJECT_DIR/MEMORY.md" ]]; then echo "  MEMORY.md (project memory)"; fi
  if [[ -d "$PROJECT_DIR/.okf" ]]; then echo "  .okf/ (knowledge bundle)"; fi
  echo "  .gitignore entries, other settings (model, env, enabledPlugins, effortLevel), backups in .claude/ai-config/"
  if [[ -d "$PROJECT_DIR/.codegraph" ]]; then
    echo "  codegraph MCP registration — remove with: claude mcp remove codegraph --scope local"
  fi
  if [[ "$(plugin_setting "$PROJECT_DIR/.claude/settings.local.json" "$PHP_LSP_PLUGIN")" == "true" ]]; then
    echo "  php-lsp plugin — remove with: claude plugin uninstall $PHP_LSP_PLUGIN --scope local"
  fi
  echo ""
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}Dry run — nothing was changed.${NC}"
  else
    echo -e "${GREEN}ai-config removed: ${removed} file(s) removed, ${kept} edited file(s) kept.${NC}"
    if [[ $COUNT_BACKED_UP -gt 0 ]]; then echo "  Backups: .claude/ai-config/backups/$RUN_STAMP/"; fi
  fi
}

# End of a deploy/refresh: verify the result; a critical failure makes the run exit 1.
run_health_check() {
  if [[ "$DRY_RUN" == true ]]; then return 0; fi
  echo ""
  echo -e "${CYAN}Health check...${NC}"
  if ! verify_deployment; then
    echo -e "${RED}Finished with failing checks — fix the ✗ items above, then run: ai-config --doctor --project=$PROJECT_DIR${NC}"
    exit 1
  fi
}

# True only when a library file is backed by a positive detection signal in THIS
# run. Used on --refresh to decide whether a *missing* library may be added.
# Framework libraries (react, vue, nextjs, …) are stack-implied with no runtime
# signal, so they return false here: once a developer removes them, --refresh
# will not re-introduce them.
library_is_detected() {
  case "$1" in
    tailwind.md)       [[ "$HAS_TAILWIND" == true ]] ;;
    alpinejs.md)       [[ "$HAS_ALPINE" == true ]] ;;
    foundation.md)     [[ "$HAS_FOUNDATION" == true ]] ;;
    scss.md)           [[ "$HAS_SCSS" == true ]] ;;
    typescript.md)     [[ "$HAS_TYPESCRIPT" == true ]] ;;
    zustand.md)        [[ "$HAS_ZUSTAND" == true ]] ;;
    tanstack-query.md) [[ "$HAS_TANSTACK_QUERY" == true ]] ;;
    trpc.md)           [[ "$HAS_TRPC" == true ]] ;;
    vitest.md)         [[ "$HAS_VITEST" == true ]] ;;
    zod.md)            [[ "$HAS_ZOD" == true ]] ;;
    pinia.md)          [[ "$HAS_PINIA" == true ]] ;;
    supabase.md)       [[ "$HAS_SUPABASE" == true ]] ;;
    framer-motion.md)  [[ "$HAS_FRAMER_MOTION" == true ]] ;;
    playwright.md)     [[ "$HAS_PLAYWRIGHT" == true ]] ;;
    prisma.md)         [[ "$HAS_PRISMA" == true ]] ;;
    shadcn-ui.md)      [[ "$HAS_SHADCN" == true ]] ;;
    tinacms.md)        [[ "$HAS_TINA" == true ]] ;;
    bootstrap.md)      [[ "$HAS_BOOTSTRAP" == true ]] ;;
    bulma.md)          [[ "$HAS_BULMA" == true ]] ;;
    jquery.md)         [[ "$HAS_JQUERY" == true ]] ;;
    material-ui.md)    [[ "$HAS_MUI" == true ]] ;;
    vanilla-js.md)     [[ "$HAS_VANILLA_JS" == true ]] ;;
    *) return 1 ;;
  esac
}

# Append @.claude/libraries/<name>.md import lines to CLAUDE.md for any
# detected technology whose library reference is not already imported.
inject_detected_library_imports() {
  local claude_md="$1"

  # Libraries eligible for auto-injection (signal-backed only)
  local injectable_libs=(
    "typescript.md"
    "zod.md"
    "zustand.md"
    "tanstack-query.md"
    "trpc.md"
    "prisma.md"
    "supabase.md"
    "vitest.md"
    "playwright.md"
    "framer-motion.md"
    "shadcn-ui.md"
    "pinia.md"
    "tailwind.md"
    "alpinejs.md"
    "scss.md"
    "tinacms.md"
    "foundation.md"
    "bootstrap.md"
    "bulma.md"
    "jquery.md"
    "material-ui.md"
    "vanilla-js.md"
  )

  local injected=0
  for lib in "${injectable_libs[@]}"; do
    if library_is_detected "$lib"; then
      # In dry-run: always report what would be injected (file may not exist yet)
      if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} Would inject @.claude/libraries/${lib}"
      elif [[ -f "$claude_md" ]] && ! grep -qF ".claude/libraries/${lib}" "$claude_md" 2>/dev/null; then
        backup_file "$claude_md"
        if [[ "$EAGER_LIBRARIES" == true ]]; then
          printf '\n@.claude/libraries/%s\n' "$lib" >> "$claude_md"
        else
          if [[ $injected -eq 0 ]]; then
            printf '\n**Detected library references** (read one only when the task involves that library):\n' >> "$claude_md"
          fi
          printf -- '- `.claude/libraries/%s`\n' "$lib" >> "$claude_md"
        fi
        echo -e "  ${GREEN}✓${NC} Added library reference: .claude/libraries/${lib}"
        injected=$((injected + 1))
      fi
    fi
  done

  [[ $injected -gt 0 ]] && echo ""
  return 0
}

merge_gitignore_template() {
  local template_file="$1"
  local gitignore_path="$2"
  local label="$3"

  local total_added=0
  local block_header_written=false
  local -a pending_section_lines=()
  local section_header_written=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Any comment line — accumulate into the current section header block
    if [[ "$line" =~ ^# ]]; then
      pending_section_lines+=("$line")
      continue
    fi

    # Blank line — section boundary: flush accumulated header state
    if [[ -z "$line" ]]; then
      pending_section_lines=()
      section_header_written=false
      continue
    fi

    # Pattern line — skip if already present (exact match)
    if grep -qxF "$line" "$gitignore_path" 2>/dev/null; then
      continue
    fi

    # New pattern found — write to file (or count for dry-run)
    if [[ "$DRY_RUN" != true ]]; then
      # Write the outer block header once
      if [[ "$block_header_written" == false ]]; then
        backup_file "$gitignore_path"
        {
          echo ""
          echo "# ============================================================================="
          echo "# Security: ${label}"
          echo "# (Added by ai-config — do not remove section header)"
          echo "# ============================================================================="
        } >> "$gitignore_path"
        block_header_written=true
      fi

      # Write the section header once per section
      if [[ "$section_header_written" == false ]] && [[ ${#pending_section_lines[@]} -gt 0 ]]; then
        echo "" >> "$gitignore_path"
        for hline in "${pending_section_lines[@]}"; do
          echo "$hline" >> "$gitignore_path"
        done
        section_header_written=true
      fi

      echo "$line" >> "$gitignore_path"
    fi

    ((total_added++))
  done < "$template_file"

  if [[ "$DRY_RUN" == true ]]; then
    if [[ $total_added -gt 0 ]]; then
      echo -e "  ${YELLOW}[DRY-RUN]${NC} Would add ${total_added} Security (${label}) entries to .gitignore"
    else
      echo -e "  ${GREEN}✓${NC}  Security (${label}) entries already up to date"
    fi
    return
  fi

  if [[ $total_added -gt 0 ]]; then
    echo -e "  ${GREEN}✓${NC}  Added ${total_added} Security (${label}) entries to .gitignore"
  else
    echo -e "  ${GREEN}✓${NC}  Security (${label}) entries already up to date"
  fi
}

do_clean() {
  # --clean starts fresh without destroying anything: CLAUDE.md and .claude/ are moved into
  # .claude/ai-config/backups/<run>/ (earlier backups and the manifest are carried over).
  echo -e "${CYAN}Cleaning existing configuration (moved to a backup, not deleted)...${NC}"

  local items=() item
  if [[ -e "$PROJECT_DIR/CLAUDE.md" ]]; then items+=("CLAUDE.md"); fi
  if [[ -e "$PROJECT_DIR/.claude" ]]; then items+=(".claude"); fi
  if [[ ${#items[@]} -eq 0 ]]; then
    echo ""
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    for item in "${items[@]}"; do
      echo -e "  ${YELLOW}[DRY-RUN]${NC} Move $item → .claude/ai-config/backups/$RUN_STAMP/"
    done
    echo ""
    return 0
  fi

  local stash="$PROJECT_DIR/.ai-config-clean-$$"
  mkdir -p "$stash"
  for item in "${items[@]}"; do
    mv "$PROJECT_DIR/$item" "$stash/"
  done
  mkdir -p "$PROJECT_DIR/.claude"
  if [[ -d "$stash/.claude/ai-config" ]]; then
    mv "$stash/.claude/ai-config" "$AI_CONFIG_DIR"
  fi
  mkdir -p "$BACKUP_DIR"
  for item in "${items[@]}"; do
    mv "$stash/$item" "$BACKUP_DIR/"
    echo -e "  ${GREEN}✓${NC} Moved $item → .claude/ai-config/backups/$RUN_STAMP/$item"
  done
  rmdir "$stash"
  echo ""
}

# ============================================================================
# Gitignore Management
# ============================================================================

update_gitignore() {
  local gitignore_path="$PROJECT_DIR/.gitignore"

  if [[ ! -f "$gitignore_path" ]]; then
    echo -e "${YELLOW}  No .gitignore found — skipping gitignore update${NC}"
    echo ""
    return
  fi

  echo ""
  echo -e "${CYAN}Updating .gitignore...${NC}"

  # --- 1. Claude AI configuration entries ---
  local claude_entries=("CLAUDE.md" "AGENTS.md" "MEMORY.md" "MEMORY-ARCHIVE.md" ".claude/" ".claude/ai-config/")
  if [[ "$SHARED_POLICY" == true ]]; then
    # Keep .claude/ ignored except the shared policy and its hook script. Git can't re-include
    # files under an ignored directory, so an exact ".claude/" line becomes ".claude/*" (backed up).
    claude_entries=("CLAUDE.md" "AGENTS.md" "MEMORY.md" "MEMORY-ARCHIVE.md" ".claude/*" "!.claude/settings.json" "!.claude/hooks/" ".claude/hooks/*" "!.claude/hooks/safety-guard.sh" ".claude/ai-config/")
    if grep -qxF ".claude/" "$gitignore_path" 2>/dev/null; then
      if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} Change '.claude/' to '.claude/*' so the shared policy files can be committed"
      else
        backup_file "$gitignore_path"
        perl -i -pe 's{^\.claude/[ \t]*$}{.claude/*}' "$gitignore_path"
        echo -e "  ${GREEN}✓${NC} Changed '.claude/' to '.claude/*' so .claude/settings.json and the safety hook can be committed"
      fi
    fi
  fi
  if [[ "$OKF_MEMORY" == true ]]; then claude_entries+=(".okf/"); fi
  if [[ "$CODE_INDEX" == true ]]; then claude_entries+=(".codegraph/"); fi
  local claude_added=()
  local claude_skipped=()

  for entry in "${claude_entries[@]}"; do
    if grep -qxF "$entry" "$gitignore_path" 2>/dev/null; then
      claude_skipped+=("$entry")
    else
      claude_added+=("$entry")
    fi
  done

  if [[ ${#claude_added[@]} -gt 0 ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      echo -e "  ${YELLOW}[DRY-RUN]${NC} Would add ${#claude_added[@]} Claude entries to .gitignore"
    else
      backup_file "$gitignore_path"
      if ! grep -q "# AI Configuration" "$gitignore_path" 2>/dev/null; then
        echo "" >> "$gitignore_path"
        echo "# AI Configuration" >> "$gitignore_path"
      fi
      for entry in "${claude_added[@]}"; do
        echo "$entry" >> "$gitignore_path"
        echo -e "  ${GREEN}✓${NC} Added: $entry"
      done
    fi
  fi

  if [[ ${#claude_skipped[@]} -gt 0 ]]; then
    echo -e "  ${GREEN}✓${NC} Claude entries already in .gitignore (${#claude_skipped[@]})"
  fi

  # --- 2. Common security patterns (all stacks) ---
  local common_security="$SCRIPT_DIR/projects/common/gitignore-security.txt"
  if [[ -f "$common_security" ]]; then
    merge_gitignore_template "$common_security" "$gitignore_path" "Common"
  fi

  # --- 3. Stack-specific security patterns ---
  local stack_label
  case "$STACK" in
    expressionengine) stack_label="ExpressionEngine" ;;
    coilpack)         stack_label="Coilpack (Laravel + EE)" ;;
    craftcms)         stack_label="Craft CMS" ;;
    craftcms-nuxt)    stack_label="Craft CMS + Nuxt" ;;
    craftcms-nextjs)  stack_label="Craft CMS + Next.js" ;;
    ee-nextjs)        stack_label="EE Coilpack + Next.js" ;;
    astro)            stack_label="Astro" ;;
    astro-strapi)     stack_label="Astro + Strapi" ;;
    astro-sanity)     stack_label="Astro + Sanity" ;;
    astro-tina)       stack_label="Astro + Tina CMS" ;;
    wordpress)        stack_label="WordPress" ;;
    wordpress-roots)  stack_label="WordPress Roots/Bedrock" ;;
    nextjs)           stack_label="Next.js" ;;
    sveltekit)        stack_label="SvelteKit" ;;
    remix)            stack_label="Remix / React Router v7" ;;
    t3-stack)         stack_label="T3 Stack (Next.js + tRPC + Prisma)" ;;
    nuxt)             stack_label="Nuxt 3" ;;
    docusaurus)       stack_label="Docusaurus" ;;
    custom)           stack_label="Custom" ;;
    *)                stack_label="$STACK" ;;
  esac

  local stack_security="$STACK_DIR/gitignore-security.txt"
  if [[ -f "$stack_security" ]]; then
    merge_gitignore_template "$stack_security" "$gitignore_path" "$stack_label"
  fi

  echo ""
}

# ============================================================================
# Superpowers Skills Deployment
# ============================================================================

# Best-effort: pull the latest superpowers/ subtree from upstream before we copy
# skills into the target project, so every deploy/refresh ships the current set.
# Runs update-superpowers.sh, which targets THIS repo (SCRIPT_DIR), not the
# project. Never fatal — if the tree is dirty, offline, or jq/git is missing, it
# warns and we fall back to the already-vendored copy.
update_superpowers() {
  [[ "$SKIP_SUPERPOWERS_UPDATE" == true ]] && return 0
  [[ "$DRY_RUN" == true ]] && {
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Pull latest superpowers subtree (update-superpowers.sh)"
    return 0
  }

  local updater="$SCRIPT_DIR/update-superpowers.sh"
  if [[ ! -x "$updater" ]]; then
    [[ -f "$updater" ]] || return 0   # script not present — nothing to do
  fi

  echo ""
  echo -e "${CYAN}Checking for superpowers updates...${NC}"
  if bash "$updater" --quiet; then
    echo -e "  ${GREEN}✓${NC} Superpowers subtree is current"
  else
    echo -e "  ${YELLOW}○${NC} Skipped superpowers update — using the vendored copy"
  fi
}

# Superpowers skills used to be deployed one level too deep (.claude/skills/superpowers/<skill>/),
# where Claude Code never discovers them. Move each skill up to .claude/skills/<skill>/ — edits
# travel with the files, and manifest/pending entries follow — unless that name is taken.
migrate_nested_superpowers() {
  local nested="$PROJECT_DIR/.claude/skills/superpowers" dir name
  [[ -d "$nested" ]] || return 0
  for dir in "$nested"/*/; do
    [[ -d "$dir" ]] || continue
    name=$(basename "$dir")
    if [[ -e "$PROJECT_DIR/.claude/skills/$name" ]]; then
      echo -e "  ${YELLOW}○${NC} Left .claude/skills/superpowers/$name in place — .claude/skills/$name already exists"
      continue
    fi
    if [[ "$DRY_RUN" == true ]]; then
      echo -e "  ${YELLOW}[DRY-RUN]${NC} Move .claude/skills/superpowers/$name → .claude/skills/$name"
      continue
    fi
    mv "${dir%/}" "$PROJECT_DIR/.claude/skills/$name"
    if [[ -f "$MANIFEST_FILE" ]]; then
      sed_inplace "s#^\.claude/skills/superpowers/$name/#.claude/skills/$name/#" "$MANIFEST_FILE"
    fi
    if [[ -d "$PENDING_DIR/.claude/skills/superpowers/$name" ]]; then
      mkdir -p "$PENDING_DIR/.claude/skills"
      mv "$PENDING_DIR/.claude/skills/superpowers/$name" "$PENDING_DIR/.claude/skills/$name"
    fi
    echo -e "  ${GREEN}✓${NC} Moved skill to .claude/skills/$name/ (Claude Code only discovers skills one level deep)"
  done
  rmdir "$nested" "$PENDING_DIR/.claude/skills/superpowers" 2>/dev/null || true
}

# True when the superpowers plugin is enabled in the user's global Claude Code settings.
# The plugin already injects the using-superpowers bootstrap at SessionStart and lists
# every skill, so a project copy would put the same content into context twice.
superpowers_plugin_enabled_globally() {
  local user_settings="${AI_CONFIG_USER_SETTINGS:-$HOME/.claude/settings.json}"
  [[ -f "$user_settings" ]] && command -v jq &>/dev/null || return 1
  jq -e '[(.enabledPlugins // {}) | to_entries[] | select((.key | startswith("superpowers@")) and .value == true)] | length > 0' \
    "$user_settings" >/dev/null 2>&1
}

deploy_superpowers() {
  local mode="${SUPERPOWERS_MODE:-all}"

  # An explicit --superpowers-* flag always deploys; the implicit default defers to the plugin.
  if [[ -z "$SUPERPOWERS_MODE" ]] && superpowers_plugin_enabled_globally; then
    echo ""
    echo -e "${CYAN}Superpowers workflow skills...${NC}"
    echo -e "  ${YELLOW}○${NC} Skipped — the superpowers plugin is enabled globally; a project copy would load"
    echo -e "      its bootstrap and skill list twice. Use --superpowers-all to deploy anyway."
    if [[ -d "$PROJECT_DIR/.claude/skills/using-superpowers" || -d "$PROJECT_DIR/.claude/skills/superpowers" ]]; then
      echo -e "      An earlier project copy (superpowers skills in .claude/skills/, SessionStart hook) was"
      echo -e "      left in place — remove it to stop the duplicate context."
    fi
    WITH_SUPERPOWERS=false
    return 0
  fi

  # Refresh the vendored subtree first (best-effort, opt-out via --skip-superpowers-update)
  update_superpowers

  echo ""
  echo -e "${CYAN}Deploying Superpowers workflow skills...${NC}"

  # Create skills directory
  do_mkdir "$PROJECT_DIR/.claude/skills"
  migrate_nested_superpowers

  case "$mode" in
    "all")
      echo -e "  Mode: ${GREEN}all skills${NC}"
      for skill_dir in "$SCRIPT_DIR/superpowers/skills"/*; do
        if [[ -d "$skill_dir" ]]; then
          do_copy "$skill_dir" "$PROJECT_DIR/.claude/skills/"
        fi
      done
      ;;
    "core")
      echo -e "  Mode: ${GREEN}core skills${NC}"
      local core_skills=("using-superpowers" "brainstorming" "test-driven-development"
                         "systematic-debugging" "writing-plans" "executing-plans")
      for skill in "${core_skills[@]}"; do
        if [[ -d "$SCRIPT_DIR/superpowers/skills/$skill" ]]; then
          do_copy "$SCRIPT_DIR/superpowers/skills/$skill" "$PROJECT_DIR/.claude/skills/"
        fi
      done
      ;;
    "minimal")
      echo -e "  Mode: ${GREEN}minimal (bootstrap only)${NC}"
      do_copy "$SCRIPT_DIR/superpowers/skills/using-superpowers" "$PROJECT_DIR/.claude/skills/"
      ;;
    "custom")
      echo -e "  Mode: ${GREEN}custom skills${NC}"
      # Always include using-superpowers
      do_copy "$SCRIPT_DIR/superpowers/skills/using-superpowers" "$PROJECT_DIR/.claude/skills/"
      # Copy custom skills
      IFS=',' read -ra SKILLS <<< "$SUPERPOWERS_CUSTOM_SKILLS"
      for skill in "${SKILLS[@]}"; do
        skill=$(echo "$skill" | xargs)  # Trim whitespace
        if [[ -d "$SCRIPT_DIR/superpowers/skills/$skill" ]]; then
          do_copy "$SCRIPT_DIR/superpowers/skills/$skill" "$PROJECT_DIR/.claude/skills/"
        else
          echo -e "  ${YELLOW}⚠${NC} Skill not found: $skill"
        fi
      done
      ;;
  esac

  # Deploy commands
  deploy_superpowers_commands

  # Deploy hooks
  deploy_superpowers_hooks
}

deploy_superpowers_commands() {
  echo ""
  echo -e "${CYAN}Deploying Superpowers commands...${NC}"

  do_mkdir "$PROJECT_DIR/.claude/commands"

  for cmd in "$SCRIPT_DIR/superpowers/commands"/*.md; do
    if [[ -f "$cmd" ]]; then
      do_copy "$cmd" "$PROJECT_DIR/.claude/commands/"
    fi
  done
}

deploy_superpowers_hooks() {
  echo ""
  echo -e "${CYAN}Deploying Superpowers session hooks...${NC}"

  do_mkdir "$PROJECT_DIR/.claude/hooks"

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Copy session-start hook script"
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Register SessionStart hook in settings.local.json"
    return 0
  fi

  do_copy "$SCRIPT_DIR/superpowers/hooks/session-start" "$PROJECT_DIR/.claude/hooks/"
  if [[ -f "$PROJECT_DIR/.claude/hooks/session-start" ]]; then chmod +x "$PROJECT_DIR/.claude/hooks/session-start"; fi

  # Claude Code reads project hooks from settings.local.json. Merge — never overwrite —
  # so the safety-guard PreToolUse hook and any project hooks survive.
  local settings_file="$PROJECT_DIR/.claude/settings.local.json"
  # CLAUDE_PLUGIN_ROOT makes the vendored hook emit Claude Code's hookSpecificOutput format.
  local session_cmd='CLAUDE_PLUGIN_ROOT="$CLAUDE_PROJECT_DIR/.claude" "$CLAUDE_PROJECT_DIR"/.claude/hooks/session-start'
  local session_hook
  session_hook=$(jq -n --arg c "$session_cmd" '{SessionStart: [{hooks: [{type: "command", command: $c}]}]}' 2>/dev/null || printf '{}')

  if ! command -v jq &>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC}  jq not found — add the hook manually to .claude/settings.local.json:"
    printf '  "hooks": %s\n' "$session_hook"
    return 0
  fi

  local base="{}"
  if [[ -f "$settings_file" ]]; then
    if ! jq empty "$settings_file" 2>/dev/null; then
      echo -e "  ${YELLOW}⚠${NC}  settings.local.json is invalid JSON — hook registration skipped"
      return 0
    fi
    base=$(cat "$settings_file")
  fi

  local updated
  # Registrations from before the fix run the same script without CLAUDE_PLUGIN_ROOT: update in place.
  if updated=$(printf '%s' "$base" | jq --argjson add "$session_hook" --arg cmd "$session_cmd" "$JQ_SETTINGS_DEFS"'
      (if .hooks.SessionStart then
         .hooks.SessionStart |= map(.hooks = ((.hooks // []) | map(if ((.command // "") | hook_key) == ".claude/hooks/session-start" then .command = $cmd else . end)))
       else . end)
      | .hooks = ((.hooks // {}) | merge_hooks($add))'); then
    if write_json_if_changed "$settings_file" "$updated"; then
      echo -e "  ${GREEN}✓${NC} Registered SessionStart hook in settings.local.json"
    else
      echo -e "  ${GREEN}✓${NC} SessionStart hook already registered in settings.local.json"
    fi
  fi
}

# ============================================================================
# Main Execution
# ============================================================================

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  AI Coding Assistant Configuration Setup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# --install-deps: install missing tools first (asks on a terminal unless --force)
install_dependencies

# Stop before changing anything if a required tool is missing
if [[ "$DOCTOR" != true ]]; then
  check_prerequisites
fi

# --uninstall: remove ai-config from the project (everything removed is backed up), then exit
if [[ "$UNINSTALL" == true ]]; then
  do_uninstall
  exit 0
fi

# Clean existing configuration if --clean flag is set (do this FIRST before scanning)
if [[ "$CLEAN" == true && "$DOCTOR" != true ]]; then
  do_clean
fi

# Run detection
echo -e "${CYAN}Scanning project...${NC}"
detect_ddev_config && echo -e "  ${GREEN}✓${NC} Found DDEV config" || echo -e "  ${YELLOW}○${NC} No DDEV config found"
detect_template_group
if [[ -n "$TEMPLATE_GROUP" ]]; then
  echo -e "  ${GREEN}✓${NC} Found template group: $TEMPLATE_GROUP"
else
  echo -e "  ${YELLOW}○${NC} No template group detected"
fi
detect_frontend_tools
write_frontend_block
if [[ -z "$(frontend_report)" ]]; then
  echo -e "  ${YELLOW}○${NC} No front-end CSS or JavaScript found"
else
  while IFS=$'\t' read -r fe_heading fe_text; do
    echo -e "  ${GREEN}✓${NC} ${fe_heading}: ${fe_text}"
  done < <(frontend_report)
fi
[[ "$HAS_BILINGUAL" == true ]] && echo -e "  ${GREEN}✓${NC} Bilingual content detected" || echo -e "  ${YELLOW}○${NC} No bilingual patterns detected"
detect_addons
[[ "$HAS_STASH" == true ]] && echo -e "  ${GREEN}✓${NC} Stash add-on detected" || true
[[ "$HAS_STRUCTURE" == true ]] && echo -e "  ${GREEN}✓${NC} Structure add-on detected" || true
detect_git_branches
echo ""

echo -e "  Stack:       ${GREEN}$STACK${NC}"
echo -e "  Project:     ${GREEN}$PROJECT_DIR${NC}"
echo -e "  Name:        ${GREEN}$PROJECT_NAME${NC}"
echo -e "  Slug:        ${GREEN}$PROJECT_SLUG${NC}"
[[ -n "$DDEV_NAME" ]] && echo -e "  DDEV Name:   ${GREEN}$DDEV_NAME${NC}"
[[ -n "$DDEV_DOCROOT" ]] && echo -e "  Docroot:     ${GREEN}$DDEV_DOCROOT${NC}"
[[ -n "$DDEV_PHP" ]] && echo -e "  PHP:         ${GREEN}$DDEV_PHP${NC}"
[[ -n "$DDEV_DB_TYPE" ]] && echo -e "  Database:    ${GREEN}$DDEV_DB_TYPE $DDEV_DB_VERSION${NC}"
[[ -n "$DDEV_PRIMARY_URL" ]] && echo -e "  Primary URL: ${GREEN}$DDEV_PRIMARY_URL${NC}"
[[ -n "$GIT_MAIN_BRANCH" ]] && echo -e "  Git Main:    ${GREEN}$GIT_MAIN_BRANCH${NC}"
[[ -n "$GIT_INTEGRATION_BRANCH" ]] && echo -e "  Git Integ:   ${GREEN}$GIT_INTEGRATION_BRANCH${NC}"
echo -e "  Dry Run:     ${YELLOW}$DRY_RUN${NC}"
echo -e "  Force:       ${YELLOW}$FORCE${NC}"
echo -e "  Clean:       ${YELLOW}$CLEAN${NC}"
echo -e "  Refresh:     ${YELLOW}$REFRESH${NC}"
[[ "$DISCOVER" == true ]] && echo -e "  Discover:    ${GREEN}true${NC}"
echo ""

# Discovery mode: Run comprehensive technology detection and generate analysis prompt
if [[ "$DISCOVER" == true ]]; then
  echo -e "${BLUE}Running discovery mode...${NC}"
  echo ""

  # Run comprehensive technology detection
  detect_all_technologies

  echo -e "${CYAN}Technologies detected:${NC}"
  if [[ ${#DETECTED_TECHNOLOGIES[@]} -gt 0 ]]; then
    for tech in "${DETECTED_TECHNOLOGIES[@]}"; do
      echo -e "  ${GREEN}✓${NC} $tech"
    done
  else
    echo -e "  ${YELLOW}○${NC} No specific technologies detected"
  fi
  echo ""
fi

# The orchestrator pattern is sticky across --refresh and redeploys. Only an explicit
# --orchestrator may overwrite model settings the developer changed.
ORCHESTRATOR_EXPLICIT="$WITH_ORCHESTRATOR"
if [[ "$WITH_ORCHESTRATOR" != true ]] && orchestrator_already_deployed; then
  WITH_ORCHESTRATOR=true
fi

if [[ "$REFRESH" == true ]]; then
  RUN_MODE=refresh
fi

# --shared-policy is sticky once .claude/settings.json carries the safety hook.
if [[ "$SHARED_POLICY" != true && -f "$PROJECT_DIR/.claude/settings.json" ]] && grep -q 'safety-guard\.sh' "$PROJECT_DIR/.claude/settings.json" 2>/dev/null; then
  SHARED_POLICY=true
fi

# OKF memory is sticky once a project has a bundle. The Code Index block is only added when
# codegraph is installed and this project already has an index (detect & register only).
if [[ "$OKF_MEMORY" != true && -f "$PROJECT_DIR/.okf/index.md" ]]; then
  OKF_MEMORY=true
fi
CODE_INDEX=false
if code_index_ready && command -v claude &>/dev/null; then
  CODE_INDEX=true
fi

# --doctor: read-only prerequisite and health check of an already-deployed project
if [[ "$DOCTOR" == true ]]; then
  echo -e "${BLUE}Health check (read-only)...${NC}"
  HC_VERBOSE=true
  if verify_deployment; then exit 0; else exit 1; fi
fi

# Refresh mode: update CLAUDE.md and merge settings.local.json — additively
if [[ "$REFRESH" == true ]]; then
  echo -e "${BLUE}Refreshing CLAUDE.md...${NC}"
  echo ""

  # Regenerate CLAUDE.md only if it has no local edits; otherwise refresh just its managed
  # blocks and library references, and stage the full new render for review
  if [[ -f "$STACK_DIR/CLAUDE.md.template" ]]; then
    install_rendered "$STACK_DIR/CLAUDE.md.template" "$PROJECT_DIR/CLAUDE.md"
  elif [[ -f "$STACK_DIR/CLAUDE.md" ]]; then
    do_copy "$STACK_DIR/CLAUDE.md" "$PROJECT_DIR/"
  fi

  # Refresh library references WITHOUT undoing the developer's curation.
  # On --refresh we only:
  #   - update a library that is ALREADY present (keep its content current), and
  #   - add a MISSING library when this run newly detects its technology.
  # A library the developer deleted is NOT re-added unless it is detected, so a
  # refresh never silently re-introduces things that required analysis to remove.
  if [[ -d "$SCRIPT_DIR/libraries" ]]; then
    proj_lib_dir="$PROJECT_DIR/.claude/libraries"
    echo ""
    echo -e "${CYAN}Refreshing library references (present = update, detected = add)...${NC}"
    for library in "$SCRIPT_DIR/libraries"/*.md; do
      [[ -f "$library" ]] || continue
      lib_name="$(basename "$library")"
      [[ "$lib_name" == "README.md" ]] && continue

      if [[ -f "$proj_lib_dir/$lib_name" ]]; then
        do_copy "$library" "$proj_lib_dir/"
      elif library_is_detected "$lib_name"; then
        do_mkdir "$proj_lib_dir"
        do_copy "$library" "$proj_lib_dir/"
        echo -e "  ${GREEN}✓${NC} Added newly detected library: $lib_name"
      fi
      # Not present and not detected → leave out (respect curation).
    done
  fi

  # Regenerate AGENTS.md from template (OpenAI Codex / API tools)
  if [[ "$WITH_OPENAI" == true ]]; then
    deploy_agents_md "Refreshing"
  fi

  # Merge settings.local.json (adds missing global rules, preserves project customizations)
  if [[ -f "$STACK_DIR/settings.local.json" ]]; then
    merge_settings_json "$STACK_DIR/settings.local.json" "$PROJECT_DIR/.claude/settings.local.json"
  fi

  # Re-apply the shared safety policy (deny/ask rules, safety-guard hook) and shared rules
  apply_security_policy
  apply_effort_level
  refresh_common_rules
  if [[ "$OKF_MEMORY" == true ]]; then
    deploy_okf_bundle
  fi
  register_code_index
  enable_php_lsp

  # Re-apply the orchestrator pattern if requested, or sticky if already deployed
  if [[ "$WITH_ORCHESTRATOR" == true ]]; then
    deploy_orchestrator "Refreshing"
  fi

  # Merge .gitignore security patterns (adds missing entries, preserves existing content)
  update_gitignore

  # Deploy Superpowers if requested (even in refresh mode)
  if [[ "$WITH_SUPERPOWERS" == true ]]; then
    deploy_superpowers
  fi

  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  CLAUDE.md refreshed successfully!${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "${CYAN}Updated values:${NC}"
  [[ -n "$DDEV_NAME" ]] && echo -e "  DDEV Name:   ${GREEN}$DDEV_NAME${NC}"
  [[ -n "$DDEV_DOCROOT" ]] && echo -e "  Docroot:     ${GREEN}$DDEV_DOCROOT${NC}"
  [[ -n "$DDEV_PHP" ]] && echo -e "  PHP:         ${GREEN}$DDEV_PHP${NC}"
  [[ -n "$DDEV_DB_TYPE" ]] && echo -e "  Database:    ${GREEN}$DDEV_DB_TYPE $DDEV_DB_VERSION${NC}"
  [[ -n "$DDEV_PRIMARY_URL" ]] && echo -e "  Primary URL: ${GREEN}$DDEV_PRIMARY_URL${NC}"
  [[ -n "$TEMPLATE_GROUP" ]] && echo -e "  Template:    ${GREEN}$TEMPLATE_GROUP${NC}"
  [[ "$HAS_TAILWIND" == true ]] && echo -e "  Tailwind:    ${GREEN}Yes${NC}"
  echo ""
  echo -e "${CYAN}Preserved & merged:${NC}"
  echo -e "  .claude/agents/              (your customizations)"
  echo -e "  .claude/commands/            (your customizations)"
  echo -e "  .claude/rules/               (your customizations)"
  echo -e "  .claude/skills/              (your customizations)"
  echo -e "  settings.local.json          (nothing removed; shared deny/ask rules + safety-guard hook added)"
  echo -e "  CLAUDE.md, rules, libraries  (updated only if unedited; your edits kept, new versions in .claude/ai-config/pending/)"
  echo -e "  MEMORY.md                    (never modified)"
  echo -e "  .gitignore                   (existing entries kept, missing security patterns added)"
  if [[ "$WITH_ORCHESTRATOR" == true ]]; then
    echo ""
    echo -e "${CYAN}Orchestrator pattern (Opus manager + Sonnet implementer):${NC}"
    echo -e "  .claude/agents/implementer.md — Sonnet implementer subagent"
    echo -e "  settings.local.json           — model=opus, CLAUDE_CODE_SUBAGENT_MODEL=sonnet"
    echo -e "  CLAUDE.md                     — Model & Delegation Policy block"
  fi
  if [[ "$WITH_SUPERPOWERS" == true ]]; then
    echo ""
    echo -e "${CYAN}Superpowers workflow skills deployed:${NC}"
    echo -e "  .claude/skills/ — Superpowers workflow skills"
    echo -e "  .claude/commands/ — Slash commands"
    echo -e "  .claude/hooks/ — Session auto-bootstrap"
  fi
  apply_pending_updates
  finish_additive_run
  run_health_check
  exit 0
fi

# Check for existing configuration (skip if --clean or --force)
if [[ -d "$PROJECT_DIR/.claude" ]] && [[ "$FORCE" != true ]] && [[ "$CLEAN" != true ]] && [[ "$DRY_RUN" != true ]]; then
  echo -e "${YELLOW}Warning: .claude/ directory already exists in project${NC}"
  read -p "Update it? Files you edited are kept and new versions staged for review. (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo -e "${BLUE}Deploying configuration...${NC}"
echo ""

# 1. Create .claude directory structure
do_mkdir "$PROJECT_DIR/.claude"

# 2a. Copy library references (project-local)
if [[ -d "$SCRIPT_DIR/libraries" ]]; then
  echo ""
  echo -e "${CYAN}Copying library references (per project)...${NC}"
  do_mkdir "$PROJECT_DIR/.claude/libraries"
  for library in "$SCRIPT_DIR/libraries"/*.md; do
    if [[ -f "$library" ]]; then
      do_copy "$library" "$PROJECT_DIR/.claude/libraries/"
    fi
  done
fi

# 2. Copy agents with smart filtering
if [[ -d "$STACK_DIR/agents" ]]; then
  echo ""
  echo -e "${CYAN}Copying agents (conditional based on stack)...${NC}"
  do_mkdir "$PROJECT_DIR/.claude/agents"

  # Each stack only ships agents relevant to it, so copy all of them
  for agent_file in "$STACK_DIR/agents/"*.md; do
    if [[ -f "$agent_file" ]]; then
      do_copy "$agent_file" "$PROJECT_DIR/.claude/agents/"
    fi
  done
fi

# 2b. Copy commands conditionally
if [[ -d "$STACK_DIR/commands" ]]; then
  echo ""
  echo -e "${CYAN}Copying commands (conditional based on detection)...${NC}"
  do_mkdir "$PROJECT_DIR/.claude/commands"

  # Core commands - ALWAYS copy if they exist
  for cmd in project-analyze.md project-discover.md sync-configs.md ddev-helper.md ee-template-scaffold.md ee-check-syntax.md craft-helper.md wordpress-helper.md nextjs-helper.md stash-optimize.md laravel-helper.md twig-helper.md livewire-component.md twig-scaffold.md docusaurus-helper.md; do
    if [[ -f "$STACK_DIR/commands/$cmd" ]]; then
      do_copy "$STACK_DIR/commands/$cmd" "$PROJECT_DIR/.claude/commands/"
    fi
  done

  # Conditional: Tailwind
  if [[ -f "$STACK_DIR/commands/tailwind-build.md" ]]; then
    if [[ "$HAS_TAILWIND" == "true" ]]; then
      do_copy "$STACK_DIR/commands/tailwind-build.md" "$PROJECT_DIR/.claude/commands/"
    else
      if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[SKIP]${NC} tailwind-build.md (not detected)"
      else
        echo -e "  ${YELLOW}○${NC} Skipped tailwind-build.md (not detected)"
      fi
    fi
  fi

  # Conditional: Alpine.js
  if [[ -f "$STACK_DIR/commands/alpine-component-gen.md" ]]; then
    if [[ "$HAS_ALPINE" == "true" ]]; then
      do_copy "$STACK_DIR/commands/alpine-component-gen.md" "$PROJECT_DIR/.claude/commands/"
    else
      if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[SKIP]${NC} alpine-component-gen.md (not detected)"
      else
        echo -e "  ${YELLOW}○${NC} Skipped alpine-component-gen.md (not detected)"
      fi
    fi
  fi
fi

# 2c. Copy skills conditionally
if [[ -d "$STACK_DIR/skills" ]]; then
  echo ""
  echo -e "${CYAN}Copying skills (conditional based on detection)...${NC}"
  do_mkdir "$PROJECT_DIR/.claude/skills"

  # Core skills - ALWAYS copy if they exist
  for skill in ee-stash-optimizer ee-template-assistant; do
    if [[ -d "$STACK_DIR/skills/$skill" ]]; then
      do_copy "$STACK_DIR/skills/$skill" "$PROJECT_DIR/.claude/skills/"
    fi
  done

  # Conditional: Tailwind
  if [[ -d "$STACK_DIR/skills/tailwind-utility-finder" ]]; then
    if [[ "$HAS_TAILWIND" == "true" ]]; then
      do_copy "$STACK_DIR/skills/tailwind-utility-finder" "$PROJECT_DIR/.claude/skills/"
    else
      if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[SKIP]${NC} tailwind-utility-finder (not detected)"
      else
        echo -e "  ${YELLOW}○${NC} Skipped tailwind-utility-finder (not detected)"
      fi
    fi
  fi

  # Conditional: Alpine.js
  if [[ -d "$STACK_DIR/skills/alpine-component-builder" ]]; then
    if [[ "$HAS_ALPINE" == "true" ]]; then
      do_copy "$STACK_DIR/skills/alpine-component-builder" "$PROJECT_DIR/.claude/skills/"
    else
      if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[SKIP]${NC} alpine-component-builder (not detected)"
      else
        echo -e "  ${YELLOW}○${NC} Skipped alpine-component-builder (not detected)"
      fi
    fi
  fi
fi

# 2d. Copy rules conditionally based on detection. Common safety/token/memory rules
# deploy even for stacks that ship no rules/ directory of their own.
if [[ -d "$STACK_DIR/rules" ]] || [[ -d "$SCRIPT_DIR/projects/common/rules" ]]; then
  echo ""
  echo -e "${CYAN}Copying rules (conditional based on detection)...${NC}"
  do_mkdir "$PROJECT_DIR/.claude/rules"

  # Core rules - ALWAYS copy if they exist (stack-specific or common fallback)
  for rule in accessibility.md performance.md memory-management.md token-optimization.md sensitive-files.md deployment-safety.md; do
    if [[ -f "$STACK_DIR/rules/$rule" ]]; then
      do_copy "$STACK_DIR/rules/$rule" "$PROJECT_DIR/.claude/rules/"
    elif [[ -f "$SCRIPT_DIR/projects/common/rules/$rule" ]]; then
      do_copy "$SCRIPT_DIR/projects/common/rules/$rule" "$PROJECT_DIR/.claude/rules/"
    fi
  done

  # Stack-specific rules - ALWAYS copy if they exist
  for rule in expressionengine-templates.md craft-templates.md blade-templates.md nextjs-patterns.md laravel-patterns.md markdown-content.md; do
    if [[ -f "$STACK_DIR/rules/$rule" ]]; then
      do_copy "$STACK_DIR/rules/$rule" "$PROJECT_DIR/.claude/rules/"
    fi
  done

  # Conditional: Tailwind
  if [[ -f "$STACK_DIR/rules/tailwind-css.md" ]]; then
    if [[ "$HAS_TAILWIND" == "true" ]]; then
      do_copy "$STACK_DIR/rules/tailwind-css.md" "$PROJECT_DIR/.claude/rules/"
    else
      if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[SKIP]${NC} tailwind-css.md (not detected)"
      else
        echo -e "  ${YELLOW}○${NC} Skipped tailwind-css.md (not detected)"
      fi
    fi
  fi

  # Conditional: Alpine.js
  if [[ -f "$STACK_DIR/rules/alpinejs.md" ]]; then
    if [[ "$HAS_ALPINE" == "true" ]]; then
      do_copy "$STACK_DIR/rules/alpinejs.md" "$PROJECT_DIR/.claude/rules/"
    else
      if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[SKIP]${NC} alpinejs.md (not detected)"
      else
        echo -e "  ${YELLOW}○${NC} Skipped alpinejs.md (not detected)"
      fi
    fi
  fi

  # Conditional: Bilingual
  if [[ -f "$STACK_DIR/rules/bilingual-content.md" ]]; then
    if [[ "$HAS_BILINGUAL" == "true" ]]; then
      do_copy "$STACK_DIR/rules/bilingual-content.md" "$PROJECT_DIR/.claude/rules/"
    else
      if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[SKIP]${NC} bilingual-content.md (not detected)"
      else
        echo -e "  ${YELLOW}○${NC} Skipped bilingual-content.md (not detected)"
      fi
    fi
  fi
fi

# 3. Copy/merge settings.local.json
if [[ -f "$STACK_DIR/settings.local.json" ]]; then
  merge_settings_json "$STACK_DIR/settings.local.json" "$PROJECT_DIR/.claude/settings.local.json"
fi

# 3b. Shared safety policy (all stacks, no flag required) + optional effort level
apply_security_policy
apply_effort_level

# 4. Copy VSCode settings
vscode_source=""
if [[ "$SKIP_VSCODE" != true ]]; then
  if [[ -d "$STACK_DIR/.vscode" ]]; then
    vscode_source="$STACK_DIR/.vscode"
  elif [[ -d "$SCRIPT_DIR/projects/common/.vscode" ]]; then
    vscode_source="$SCRIPT_DIR/projects/common/.vscode"
  fi
else
  echo ""
  echo -e "  ${YELLOW}○${NC} Skipped VSCode settings (--skip-vscode)"
fi

if [[ -n "$vscode_source" ]]; then
  echo ""
  echo -e "${CYAN}Copying VSCode settings...${NC}"

  # Check if .vscode exists and is not empty
  if [[ -d "$PROJECT_DIR/.vscode" ]] && [[ "$(ls -A "$PROJECT_DIR/.vscode" 2>/dev/null)" ]]; then
    if [[ "$FORCE" != true ]] && [[ "$DRY_RUN" != true ]]; then
      echo -e "${YELLOW}Warning: .vscode/ directory already has files${NC}"
      read -p "Merge/overwrite VSCode settings? (y/N) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "  ${YELLOW}○${NC} Skipped VSCode settings"
        vscode_source=""
      fi
    fi
  fi

  if [[ -n "$vscode_source" ]]; then
    do_mkdir "$PROJECT_DIR/.vscode"
    for file in "$vscode_source"/*; do
      if [[ -e "$file" ]]; then
        do_copy "$file" "$PROJECT_DIR/.vscode/"
      fi
    done
  fi
fi

# 4. Create CLAUDE.md from template
echo ""
echo -e "${CYAN}Deploying Claude Code main configuration...${NC}"
# Rendered with detected library references and the managed blocks (safety guardrails, memory
# protocol, response style). An existing CLAUDE.md with local edits is kept, not replaced.
if [[ -f "$STACK_DIR/CLAUDE.md.template" ]]; then
  install_rendered "$STACK_DIR/CLAUDE.md.template" "$PROJECT_DIR/CLAUDE.md"
elif [[ -f "$STACK_DIR/CLAUDE.md" ]]; then
  do_copy "$STACK_DIR/CLAUDE.md" "$PROJECT_DIR/"
fi

# 4a. Create AGENTS.md from template (OpenAI Codex / API tools)
if [[ "$WITH_OPENAI" == true ]]; then
  deploy_agents_md "Deploying"
fi

# 4b. Deploy Opus orchestrator + Sonnet implementer pattern (opt-in)
if [[ "$WITH_ORCHESTRATOR" == true ]]; then
  deploy_orchestrator "Deploying"
fi

# 5. Project memory: an OKF bundle with --okf-memory, otherwise MEMORY.md (never overwritten)
if [[ "$OKF_MEMORY" == true ]]; then
  deploy_okf_bundle
elif [[ ! -f "$PROJECT_DIR/MEMORY.md" ]]; then
  echo ""
  echo -e "${CYAN}Deploying Memory Bank template...${NC}"
  if [[ -f "$STACK_DIR/MEMORY.md.template" ]]; then
    do_template "$STACK_DIR/MEMORY.md.template" "$PROJECT_DIR/MEMORY.md"
  elif [[ -f "$SCRIPT_DIR/projects/common/MEMORY.md.template" ]]; then
    do_template "$SCRIPT_DIR/projects/common/MEMORY.md.template" "$PROJECT_DIR/MEMORY.md"
  fi
else
  if [[ "$DRY_RUN" != true ]]; then
    echo ""
    echo -e "  ${YELLOW}○${NC} MEMORY.md exists, preserving existing memory"
  fi
fi

# 5b. Register an existing codegraph index for JS-framework stacks (never installs anything)
register_code_index

# 5c. Enable the php-lsp plugin for PHP stacks when Intelephense is installed
enable_php_lsp

# 6. Generate analysis prompt if requested
if [[ "$ANALYZE" == true ]] && [[ "$DRY_RUN" != true ]]; then
  echo ""
  echo -e "${CYAN}Generating analysis prompt...${NC}"
  
  cat > "$PROJECT_DIR/.claude/ANALYZE_PROJECT.md" << 'ANALYSIS_EOF'
# Project Analysis Request

Please run the `/project-analyze` command to scan this project and customize the configuration.

## What to Analyze

1. **DDEV Configuration** (`.ddev/config.yaml`)
   - Verify project name, URLs, PHP version
   - Check database type and version
   - Note any custom configuration

2. **Template Structure** (`system/user/templates/`)
   - Identify template group name
   - Document layout and partial organization
   - Check for bilingual patterns

3. **Frontend Build** (`public/` or project root)
   - Find `package.json` and document npm scripts
   - Check Tailwind config for brand colors
   - Note build tool (PostCSS, Vite, Webpack, etc.)

4. **Add-ons** (`system/user/addons/`)
   - List installed add-ons
   - Note any custom add-ons

5. **Update Configuration**
   - Customize CLAUDE.md with detected values
   - Update brand colors in Tailwind rules
   - Adjust commands for this project's paths

## After Analysis

Update these files with project-specific information:
- `CLAUDE.md` - Project overview, URLs, commands
- `.claude/rules/tailwind-css.md` - Brand colors
- `.claude/skills/tailwind-utility-finder/BRAND_COLORS.md` - Color reference
ANALYSIS_EOF

  echo -e "  ${GREEN}✓${NC} Created .claude/ANALYZE_PROJECT.md"
fi

# 7. Deploy Superpowers workflow skills (enabled by default)
if [[ "$WITH_SUPERPOWERS" == true ]]; then
  deploy_superpowers
fi

# 8. Generate discovery prompt if in discovery mode
if [[ "$DISCOVER" == true ]] && [[ "$DRY_RUN" != true ]]; then
  echo ""
  echo -e "${CYAN}Generating discovery analysis prompt...${NC}"

  # Build technology list for the prompt
  TECH_LIST=""
  if [[ ${#DETECTED_TECHNOLOGIES[@]} -gt 0 ]]; then
    for tech in "${DETECTED_TECHNOLOGIES[@]}"; do
      TECH_LIST="${TECH_LIST}- ${tech}\n"
    done
  fi

  cat > "$PROJECT_DIR/.claude/DISCOVERY_PROMPT.md" << DISCOVERY_EOF
# Project Discovery Analysis

This project was set up using **discovery mode**. Claude (or another AI assistant) should analyze this codebase and generate comprehensive configuration.

## Detected Technologies

The setup script detected the following technologies:

${TECH_LIST:-"- No specific technologies detected - manual analysis required"}

## Your Task

Run the \`/project-discover\` command (or follow these steps manually):

### 1. Analyze the Codebase

Scan the project to understand:
- Directory structure and organization
- Primary programming language(s) and frameworks
- Build tools and package managers
- Testing setup and conventions
- Code quality tools (linters, formatters)

### 2. Research Best Practices

For each detected technology, research:
- Official coding standards and style guides
- Security best practices
- Performance optimization techniques
- Testing strategies

### 3. Generate Configuration

Create or update:

**CLAUDE.md** - Update with:
- Accurate project overview
- Complete directory structure
- All development commands
- Framework-specific patterns

**.claude/rules/** - Create rules for:
- Framework-specific patterns
- Language coding standards
- Security requirements
- Testing guidelines

**.claude/agents/** - Create specialists for:
- Backend development (if applicable)
- Frontend development (if applicable)
- Testing and QA
- Security review

## Project Information

- **Name**: ${PROJECT_NAME}
- **Path**: ${PROJECT_DIR}
- **Stack**: ${STACK} (custom/discovery mode)

## After Discovery

Once complete, delete this file and commit the generated configuration.
DISCOVERY_EOF

  echo -e "  ${GREEN}✓${NC} Created .claude/DISCOVERY_PROMPT.md"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ "$DRY_RUN" == true ]]; then
  echo -e "${YELLOW}  Dry run complete. No changes made.${NC}"
else
  echo -e "${GREEN}  Configuration deployed successfully!${NC}"
fi
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Adjust next steps based on mode
if [[ "$DISCOVER" == true ]]; then
  echo -e "${CYAN}Discovery Mode - Next steps:${NC}"
  echo "  1. Open the project in Claude Code (or your AI assistant)"
  echo "  2. Run: /project-discover"
  echo "     This will analyze your codebase and generate custom configuration"
  echo ""
  echo "  The AI will:"
  echo "  - Analyze your project structure and technologies"
  echo "  - Research best practices for your stack"
  echo "  - Generate rules, agents, and documentation"
  echo "  - Update all AI assistant configuration files"
else
  echo -e "${CYAN}Next steps:${NC}"
  echo "  1. Open the project in Claude Code"
  echo "  2. Run: /project-analyze"
  echo "     This will scan the codebase and customize the configuration"
fi
echo ""
echo "  Or manually review and customize:"
echo "  - CLAUDE.md — Project overview and commands"
echo "  - .claude/rules/ — Project-specific constraints"
echo "  - .claude/agents/ — Custom agent personas"
echo ""
if [[ "$WITH_SUPERPOWERS" == true ]]; then
  echo -e "${CYAN}Superpowers workflow skills deployed:${NC}"
  echo "  - .claude/skills/ — Superpowers workflow skills"
  echo "  - .claude/commands/ — Slash commands (/brainstorm, /write-plan, /execute-plan)"
  echo "  - .claude/hooks/ — Session auto-bootstrap"
  echo ""
  echo -e "${GREEN}Skills activate automatically on Claude Code session start.${NC}"
  echo ""
fi
echo -e "${CYAN}Safety guardrails deployed:${NC}"
echo "  - CLAUDE.md — Operational Safety Guardrails block"
echo "  - .claude/hooks/safety-guard.sh — PreToolUse hook (secrets, push, production, destructive ops)"
echo "  - settings.local.json — shared deny/ask rules"
echo ""
echo -e "${CYAN}Memory & token optimization deployed:${NC}"
if [[ "$OKF_MEMORY" == true ]]; then
  echo "  - .okf/ — OKF knowledge bundle (index.md first; validate with .claude/scripts/okf-check.sh)"
else
  echo "  - MEMORY.md — Persistent project memory bank"
fi
[[ "$NO_RESPONSE_STYLE" != true ]] && echo "  - CLAUDE.md — Response Style block (concise output by default)"
[[ "$EAGER_LIBRARIES" != true ]] && echo "  - CLAUDE.md — library references load on demand"
echo "  - .claude/rules/ — path-scoped rules load only for matching files"
echo ""
if [[ "$WITH_ORCHESTRATOR" == true ]]; then
  echo -e "${CYAN}Orchestrator pattern deployed (Opus manager + Sonnet implementer):${NC}"
  echo "  - .claude/agents/implementer.md — Sonnet implementer subagent"
  echo "  - settings.local.json — model=opus, all subagents pinned to Sonnet"
  echo "  - CLAUDE.md — Model & Delegation Policy block"
  echo ""
  echo -e "${GREEN}Opus plans & reviews in the main thread; delegate coding to the implementer.${NC}"
  echo ""
fi
if [[ -n "$vscode_source" ]] || [[ -d "$PROJECT_DIR/.vscode" ]]; then
  echo -e "${CYAN}VSCode settings deployed:${NC}"
  echo "  - .vscode/settings.json — Editor + formatter preferences"
  [[ -f "$PROJECT_DIR/.vscode/launch.json" ]] && echo "  - .vscode/launch.json — Xdebug configuration"
  [[ -f "$PROJECT_DIR/.vscode/tasks.json" ]] && echo "  - .vscode/tasks.json — DDEV tasks"
  echo ""
fi

# Install VSCode extensions if requested
if [[ "$INSTALL_EXTENSIONS" == true ]] && [[ "$DRY_RUN" != true ]]; then
  echo ""
  echo -e "${CYAN}Installing recommended VSCode extensions...${NC}"

  # Common extensions for all stacks
  EXTENSIONS=(
    "esbenp.prettier-vscode"
    "editorconfig.editorconfig"
  )

  # Stack-specific extensions
  case "$STACK" in
    expressionengine|coilpack|craftcms|wordpress|wordpress-roots)
      EXTENSIONS+=(
        "bmewburn.vscode-intelephense-client"
        "xdebug.php-debug"
      )
      ;;
    nextjs|docusaurus)
      EXTENSIONS+=(
        "dbaeumer.vscode-eslint"
      )
      ;;
  esac

  # Tailwind extension if project uses Tailwind
  if [[ "$HAS_TAILWIND" == true ]]; then
    EXTENSIONS+=("bradlc.vscode-tailwindcss")
  fi

  for ext in "${EXTENSIONS[@]}"; do
    if command -v code &>/dev/null; then
      code --install-extension "$ext" --force 2>/dev/null && \
        echo -e "  ${GREEN}✓${NC} Installed $ext" || \
        echo -e "  ${YELLOW}○${NC} Failed to install $ext"
    else
      echo -e "  ${YELLOW}○${NC} VSCode CLI (code) not found — install extensions manually"
      break
    fi
  done
  echo ""
elif [[ "$INSTALL_EXTENSIONS" == true ]] && [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo -e "${CYAN}[DRY RUN] Would install VSCode extensions${NC}"
  echo ""
fi

# Update .gitignore automatically
update_gitignore

# Adopt staged versions if requested, record what this run wrote, report, and verify
apply_pending_updates
finish_additive_run
run_health_check
