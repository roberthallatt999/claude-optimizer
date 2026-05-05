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
SUPERPOWERS_MODE=""            # all, core, minimal, custom
SUPERPOWERS_CUSTOM_SKILLS=""   # comma-separated skill names

# Detected values (populated during analysis)
DDEV_NAME=""
DDEV_DOCROOT=""
DDEV_PHP=""
DDEV_DB_TYPE=""
DDEV_DB_VERSION=""
DDEV_NODEJS=""
TEMPLATE_GROUP=""
HAS_TAILWIND=false
HAS_ALPINE=false
HAS_FOUNDATION=false
HAS_SCSS=false
HAS_VANILLA_JS=false
HAS_STASH=false
HAS_STRUCTURE=false
HAS_BILINGUAL=false

# Brand colors (discovered from project's Tailwind config or set manually)
BRAND_GREEN=""
BRAND_BLUE=""
BRAND_ORANGE=""
BRAND_LIGHT_GREEN=""

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
      echo ""
      echo "Superpowers Skills (enabled by default):"
      echo "  --no-superpowers        Disable Superpowers skills system"
      echo "  --superpowers-all       Deploy all skills (default when enabled)"
      echo "  --superpowers-core      Deploy core skills only (TDD, debugging, brainstorming)"
      echo "  --superpowers-minimal   Deploy only the bootstrap skill"
      echo "  --superpowers-skill=X   Deploy specific skills (comma-separated)"
      echo ""
      echo "OpenAI / API tools:"
      echo "  --with-openai           Deploy AGENTS.md for OpenAI Codex and API tools"
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
    # Astro (check for CMS integrations first, then standalone)
    elif [[ -f "$PROJECT_DIR/astro.config.mjs" ]] || [[ -f "$PROJECT_DIR/astro.config.ts" ]]; then
      if [[ -f "$PROJECT_DIR/sanity.config.ts" ]] || [[ -f "$PROJECT_DIR/sanity.config.js" ]]; then
        STACK="astro-sanity"
      elif [[ -d "$PROJECT_DIR/backend" ]] && [[ -f "$PROJECT_DIR/backend/package.json" ]] && grep -q '"@strapi' "$PROJECT_DIR/backend/package.json" 2>/dev/null; then
        STACK="astro-strapi"
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
      elif grep -q '"astro"' "$PROJECT_DIR/package.json" 2>/dev/null; then
        if grep -q '"@sanity' "$PROJECT_DIR/package.json" 2>/dev/null; then
          STACK="astro-sanity"
        elif grep -q '"@strapi' "$PROJECT_DIR/package.json" 2>/dev/null; then
          STACK="astro-strapi"
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
    DDEV_NODEJS=$(grep -E "^nodejs_version:" "$config_file" 2>/dev/null | head -1 | sed 's/nodejs_version:[[:space:]]*//' | tr -d '"' || echo "18")
    
    # TLD detection (default: ddev.site)
    DDEV_TLD=$(grep -E "^project_tld:" "$config_file" 2>/dev/null | head -1 | sed 's/project_tld:[[:space:]]*//' | tr -d '"' || echo "ddev.site")
    
    # Get all additional FQDNs
    local fqdns=$(grep -A10 "additional_fqdns:" "$config_file" 2>/dev/null | grep -E "^\s+-" | sed 's/.*-[[:space:]]*//' | tr -d '"')
    
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
    TEMPLATE_GROUP=$(ls -1 "$templates_dir" 2>/dev/null | grep -v "^_" | head -1 || true)
  fi
  return 0
}

detect_frontend_tools() {
  # Check for Tailwind (root, docroot, or nested in themes - common in WordPress Roots/Sage)
  if [[ -f "$PROJECT_DIR/tailwind.config.js" ]] || [[ -f "$PROJECT_DIR/$DDEV_DOCROOT/tailwind.config.js" ]]; then
    HAS_TAILWIND=true
  elif [[ -f "$PROJECT_DIR/package.json" ]] && grep -q "tailwindcss" "$PROJECT_DIR/package.json" 2>/dev/null; then
    HAS_TAILWIND=true
  elif find "$PROJECT_DIR" -path "*/node_modules" -prune -o -name "tailwind.config.*" -print 2>/dev/null | head -1 | grep -q .; then
    HAS_TAILWIND=true
  fi

  # Check for Foundation
  if [[ -f "$PROJECT_DIR/package.json" ]] && grep -q "foundation-sites" "$PROJECT_DIR/package.json" 2>/dev/null; then
    HAS_FOUNDATION=true
  elif find "$PROJECT_DIR" -name "foundation.min.css" -o -name "foundation.css" 2>/dev/null | head -1 | grep -q .; then
    HAS_FOUNDATION=true
  fi

  # Check for SCSS/Sass
  if [[ -f "$PROJECT_DIR/package.json" ]] && grep -q '"sass"\|"node-sass"' "$PROJECT_DIR/package.json" 2>/dev/null; then
    HAS_SCSS=true
  elif find "$PROJECT_DIR" -name "*.scss" -o -name "*.sass" 2>/dev/null | head -1 | grep -q .; then
    HAS_SCSS=true
  fi

  # Check for Alpine.js (in package.json at root or docroot, or in templates)
  local docroot="${DDEV_DOCROOT:-public}"
  if [[ -f "$PROJECT_DIR/package.json" ]] && grep -q "alpinejs" "$PROJECT_DIR/package.json" 2>/dev/null; then
    HAS_ALPINE=true
  elif [[ -f "$PROJECT_DIR/$docroot/package.json" ]] && grep -q "alpinejs" "$PROJECT_DIR/$docroot/package.json" 2>/dev/null; then
    HAS_ALPINE=true
  elif grep -rq --include="*.html" --include="*.twig" --include="*.blade.php" "x-data\|x-bind\|x-on:" "$PROJECT_DIR" 2>/dev/null; then
    HAS_ALPINE=true
  fi

  # Check for bilingual content patterns (EE user_language, Twig lang, Blade @lang)
  if grep -rq --include="*.html" "user_language" "$PROJECT_DIR/system/user/templates" 2>/dev/null; then
    HAS_BILINGUAL=true
  elif grep -rq --include="*.twig" --include="*.blade.php" '{%.*lang\|@lang\|__(' "$PROJECT_DIR" 2>/dev/null; then
    HAS_BILINGUAL=true
  fi

  # Detect vanilla JS/HTML (no major framework detected)
  # If no Tailwind, Foundation, or Alpine, assume vanilla JS/HTML is being used
  if [[ "$HAS_TAILWIND" == false ]] && [[ "$HAS_FOUNDATION" == false ]] && [[ "$HAS_ALPINE" == false ]]; then
    HAS_VANILLA_JS=true
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

  # Remove duplicates
  DETECTED_TECHNOLOGIES=($(echo "${DETECTED_TECHNOLOGIES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
}

# ============================================================================
# Helper Functions
# ============================================================================

do_copy() {
  local src="$1"
  local dest="$2"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} cp -r $src → $dest"
  else
    cp -r "$src" "$dest"
    echo -e "  ${GREEN}✓${NC} Copied $(basename "$src")"
  fi
}

do_mkdir() {
  local dir="$1"
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} mkdir -p $dir"
  else
    mkdir -p "$dir"
  fi
}

do_template() {
  local src="$1"
  local dest="$2"
  local dest_file=$(basename "$dest")
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Template $src → $dest"
    echo -e "           Substitutions: {{PROJECT_NAME}}=$PROJECT_NAME, {{PROJECT_SLUG}}=$PROJECT_SLUG"
  else
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
        -e "s/{{BRAND_GREEN}}/${BRAND_GREEN:-#000000}/g" \
        -e "s/{{BRAND_BLUE}}/${BRAND_BLUE:-#000000}/g" \
        -e "s/{{BRAND_ORANGE}}/${BRAND_ORANGE:-#000000}/g" \
        -e "s/{{BRAND_LIGHT_GREEN}}/${BRAND_LIGHT_GREEN:-#000000}/g" \
        "$src" > "$dest"

    # Second pass: handle conditional {{#SUPERPOWERS}}...{{/SUPERPOWERS}} sections
    if [[ "$WITH_SUPERPOWERS" == true ]]; then
      # Remove only the markers, keep the content
      sed_inplace -e 's/{{#SUPERPOWERS}}//' -e 's/{{\/SUPERPOWERS}}//' "$dest"
    else
      # Remove the entire section including markers and content
      # Use perl for multi-line matching (more reliable than sed)
      perl -i -0pe 's/\{\{#SUPERPOWERS\}\}.*?\{\{\/SUPERPOWERS\}\}\n?//gs' "$dest"
    fi

    echo -e "  ${GREEN}✓${NC} Created $dest_file from template"
  fi
}

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
  #   - Array fields (allow, deny, enabledMcpjsonServers): union of both sets
  #   - Top-level keys only in template are added; keys only in existing are kept
  local merged
  merged=$(jq -s '
    .[0] as $existing |
    .[1] as $template |
    ($template * $existing) |
    .permissions.allow = (
      (($template.permissions.allow // []) + ($existing.permissions.allow // [])) | unique
    ) |
    .permissions.deny = (
      (($template.permissions.deny // []) + ($existing.permissions.deny // [])) | unique
    ) |
    if ($template.enabledMcpjsonServers != null or $existing.enabledMcpjsonServers != null) then
      .enabledMcpjsonServers = (
        (($template.enabledMcpjsonServers // []) + ($existing.enabledMcpjsonServers // [])) | unique
      )
    else . end
  ' "$target_file" "$template_file")

  if [[ $? -ne 0 ]]; then
    echo -e "  ${RED}✗${NC}  Failed to merge settings.local.json — skipping"
    return
  fi

  echo "$merged" > "$target_file"

  local after_deny after_allow
  after_deny=$(echo "$merged" | jq '.permissions.deny | length')
  after_allow=$(echo "$merged" | jq '.permissions.allow | length')
  local added_deny=$((after_deny - before_deny))
  local added_allow=$((after_allow - before_allow))

  if [[ $added_deny -gt 0 || $added_allow -gt 0 ]]; then
    echo -e "  ${GREEN}✓${NC} Merged settings.local.json"
    [[ $added_allow -gt 0 ]] && echo -e "       ${GREEN}+${added_allow}${NC} allow rule(s) added"
    [[ $added_deny -gt 0 ]] && echo -e "       ${GREEN}+${added_deny}${NC} deny rule(s) added"
  else
    echo -e "  ${GREEN}✓${NC} settings.local.json already up to date"
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
    do_template "$agents_template" "$PROJECT_DIR/AGENTS.md"
  else
    echo -e "  ${YELLOW}○${NC} No AGENTS.md template found for stack: $STACK"
  fi
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
  # Remove existing AI assistant configuration files
  local files_to_clean=(
    # Claude Code
    "$PROJECT_DIR/CLAUDE.md"
    "$PROJECT_DIR/.claude"
  )

  echo -e "${CYAN}Cleaning existing configuration...${NC}"

  for item in "${files_to_clean[@]}"; do
    if [[ -e "$item" ]] || [[ -L "$item" ]]; then
      if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} rm -rf $item"
      else
        rm -rf "$item"
        echo -e "  ${GREEN}✓${NC} Removed $(basename "$item")"
      fi
    fi
  done
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
  local claude_entries=("CLAUDE.md" "AGENTS.md" "MEMORY.md" "MEMORY-ARCHIVE.md" ".claude/")
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
    wordpress)        stack_label="WordPress" ;;
    wordpress-roots)  stack_label="WordPress Roots/Bedrock" ;;
    nextjs)           stack_label="Next.js" ;;
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

deploy_superpowers() {
  local mode="${SUPERPOWERS_MODE:-all}"

  echo ""
  echo -e "${CYAN}Deploying Superpowers workflow skills...${NC}"

  # Create skills directory
  do_mkdir "$PROJECT_DIR/.claude/skills"
  do_mkdir "$PROJECT_DIR/.claude/skills/superpowers"

  case "$mode" in
    "all")
      echo -e "  Mode: ${GREEN}all skills${NC}"
      for skill_dir in "$SCRIPT_DIR/superpowers/skills"/*; do
        if [[ -d "$skill_dir" ]]; then
          skill_name=$(basename "$skill_dir")
          if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${YELLOW}[DRY-RUN]${NC} cp -r $skill_name → .claude/skills/superpowers/"
          else
            cp -r "$skill_dir" "$PROJECT_DIR/.claude/skills/superpowers/"
            echo -e "  ${GREEN}✓${NC} Copied skill: $skill_name"
          fi
        fi
      done
      ;;
    "core")
      echo -e "  Mode: ${GREEN}core skills${NC}"
      local core_skills=("using-superpowers" "brainstorming" "test-driven-development"
                         "systematic-debugging" "writing-plans" "executing-plans")
      for skill in "${core_skills[@]}"; do
        if [[ -d "$SCRIPT_DIR/superpowers/skills/$skill" ]]; then
          if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${YELLOW}[DRY-RUN]${NC} cp -r $skill → .claude/skills/superpowers/"
          else
            cp -r "$SCRIPT_DIR/superpowers/skills/$skill" "$PROJECT_DIR/.claude/skills/superpowers/"
            echo -e "  ${GREEN}✓${NC} Copied skill: $skill"
          fi
        fi
      done
      ;;
    "minimal")
      echo -e "  Mode: ${GREEN}minimal (bootstrap only)${NC}"
      if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} cp -r using-superpowers → .claude/skills/superpowers/"
      else
        cp -r "$SCRIPT_DIR/superpowers/skills/using-superpowers" "$PROJECT_DIR/.claude/skills/superpowers/"
        echo -e "  ${GREEN}✓${NC} Copied skill: using-superpowers"
      fi
      ;;
    "custom")
      echo -e "  Mode: ${GREEN}custom skills${NC}"
      # Always include using-superpowers
      if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} cp -r using-superpowers → .claude/skills/superpowers/"
      else
        cp -r "$SCRIPT_DIR/superpowers/skills/using-superpowers" "$PROJECT_DIR/.claude/skills/superpowers/"
        echo -e "  ${GREEN}✓${NC} Copied skill: using-superpowers"
      fi
      # Copy custom skills
      IFS=',' read -ra SKILLS <<< "$SUPERPOWERS_CUSTOM_SKILLS"
      for skill in "${SKILLS[@]}"; do
        skill=$(echo "$skill" | xargs)  # Trim whitespace
        if [[ -d "$SCRIPT_DIR/superpowers/skills/$skill" ]]; then
          if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${YELLOW}[DRY-RUN]${NC} cp -r $skill → .claude/skills/superpowers/"
          else
            cp -r "$SCRIPT_DIR/superpowers/skills/$skill" "$PROJECT_DIR/.claude/skills/superpowers/"
            echo -e "  ${GREEN}✓${NC} Copied skill: $skill"
          fi
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
      cmd_name=$(basename "$cmd")
      if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} cp $cmd_name → .claude/commands/"
      else
        cp "$cmd" "$PROJECT_DIR/.claude/commands/"
        echo -e "  ${GREEN}✓${NC} Copied command: $cmd_name"
      fi
    fi
  done
}

deploy_superpowers_hooks() {
  echo ""
  echo -e "${CYAN}Deploying Superpowers session hooks...${NC}"

  do_mkdir "$PROJECT_DIR/.claude/hooks"

  if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Copy session-start hook script"
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Inject SessionStart hook into settings.local.json"
  else
    # Copy session-start script
    cp "$SCRIPT_DIR/superpowers/hooks/session-start" "$PROJECT_DIR/.claude/hooks/"
    chmod +x "$PROJECT_DIR/.claude/hooks/session-start"
    echo -e "  ${GREEN}✓${NC} Copied session-start hook script"

    # Inject SessionStart hook into settings.local.json
    # Claude Code reads hooks from settings.local.json, not from a standalone hooks.json
    local settings_file="$PROJECT_DIR/.claude/settings.local.json"
    if [[ -f "$settings_file" ]] && command -v jq &>/dev/null; then
      if ! jq -e '.hooks.SessionStart' "$settings_file" &>/dev/null 2>&1; then
        local updated
        updated=$(jq '.hooks = {"SessionStart": [{"hooks": [{"type": "command", "command": ".claude/hooks/session-start"}]}]}' "$settings_file")
        if [[ $? -eq 0 ]]; then
          echo "$updated" > "$settings_file"
          echo -e "  ${GREEN}✓${NC} Injected SessionStart hook into settings.local.json"
        fi
      else
        echo -e "  ${GREEN}✓${NC} SessionStart hook already configured in settings.local.json"
      fi
    elif [[ ! -f "$settings_file" ]]; then
      echo -e "  ${YELLOW}⚠${NC}  settings.local.json not found — hook injection skipped"
    else
      echo -e "  ${YELLOW}⚠${NC}  jq not found — add hook manually to .claude/settings.local.json:"
      printf '  %s\n' '"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": ".claude/hooks/session-start"}]}]}'
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

# Clean existing configuration if --clean flag is set (do this FIRST before scanning)
if [[ "$CLEAN" == true ]]; then
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
[[ "$HAS_TAILWIND" == true ]] && echo -e "  ${GREEN}✓${NC} Tailwind CSS detected" || echo -e "  ${YELLOW}○${NC} No Tailwind detected"
[[ "$HAS_FOUNDATION" == true ]] && echo -e "  ${GREEN}✓${NC} Foundation framework detected" || echo -e "  ${YELLOW}○${NC} No Foundation detected"
[[ "$HAS_SCSS" == true ]] && echo -e "  ${GREEN}✓${NC} SCSS/Sass detected" || echo -e "  ${YELLOW}○${NC} No SCSS/Sass detected"
[[ "$HAS_ALPINE" == true ]] && echo -e "  ${GREEN}✓${NC} Alpine.js detected" || echo -e "  ${YELLOW}○${NC} No Alpine.js detected"
[[ "$HAS_VANILLA_JS" == true ]] && echo -e "  ${GREEN}✓${NC} Vanilla JS/HTML detected (no frameworks)" || true
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

# Refresh mode: regenerate CLAUDE.md and merge settings.local.json
if [[ "$REFRESH" == true ]]; then
  echo -e "${BLUE}Refreshing CLAUDE.md...${NC}"
  echo ""

  # Regenerate CLAUDE.md from template
  if [[ -f "$STACK_DIR/CLAUDE.md.template" ]]; then
    do_template "$STACK_DIR/CLAUDE.md.template" "$PROJECT_DIR/CLAUDE.md"
  elif [[ -f "$STACK_DIR/CLAUDE.md" ]]; then
    do_copy "$STACK_DIR/CLAUDE.md" "$PROJECT_DIR/"
  fi

  # Copy library reference docs to project-local CLAUDE context
  if [[ -d "$SCRIPT_DIR/libraries" ]]; then
    do_mkdir "$PROJECT_DIR/.claude/libraries"
    for library in "$SCRIPT_DIR/libraries"/*.md; do
      if [[ -f "$library" ]]; then
        do_copy "$library" "$PROJECT_DIR/.claude/libraries/"
      fi
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
  echo -e "  settings.local.json (allow)  (project-specific rules kept)"
  echo -e "  .gitignore                   (existing entries kept, missing security patterns added)"
  if [[ "$WITH_SUPERPOWERS" == true ]]; then
    echo ""
    echo -e "${CYAN}Superpowers workflow skills deployed:${NC}"
    echo -e "  .claude/skills/superpowers/ — Workflow skills"
    echo -e "  .claude/commands/ — Slash commands"
    echo -e "  .claude/hooks/ — Session auto-bootstrap"
  fi
  exit 0
fi

# Check for existing configuration (skip if --clean or --force)
if [[ -d "$PROJECT_DIR/.claude" ]] && [[ "$FORCE" != true ]] && [[ "$CLEAN" != true ]] && [[ "$DRY_RUN" != true ]]; then
  echo -e "${YELLOW}Warning: .claude/ directory already exists in project${NC}"
  read -p "Overwrite? (y/N) " -n 1 -r
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

  # Universal agents - ALWAYS copy these
  universal_agents=(
    "backend-architect.md"
    "frontend-architect.md"
    "devops-engineer.md"
    "security-expert.md"
    "performance-auditor.md"
    "data-migration-specialist.md"
    "server-admin.md"
    "code-quality-specialist.md"
  )

  for agent in "${universal_agents[@]}"; do
    if [[ -f "$STACK_DIR/agents/$agent" ]]; then
      do_copy "$STACK_DIR/agents/$agent" "$PROJECT_DIR/.claude/agents/"
    fi
  done

  # Stack-specific agents - conditional copy
  # All agents in the stack directory are now copied unconditionally
  # (each stack only includes agents relevant to it)
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

# 2d. Copy rules conditionally based on detection
if [[ -d "$STACK_DIR/rules" ]]; then
  echo ""
  echo -e "${CYAN}Copying rules (conditional based on detection)...${NC}"
  do_mkdir "$PROJECT_DIR/.claude/rules"

  # Core rules - ALWAYS copy if they exist (stack-specific or common fallback)
  for rule in accessibility.md performance.md memory-management.md token-optimization.md sensitive-files.md; do
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
if [[ -f "$STACK_DIR/CLAUDE.md.template" ]]; then
  do_template "$STACK_DIR/CLAUDE.md.template" "$PROJECT_DIR/CLAUDE.md"
elif [[ -f "$STACK_DIR/CLAUDE.md" ]]; then
  do_copy "$STACK_DIR/CLAUDE.md" "$PROJECT_DIR/"
fi

# 4a. Create AGENTS.md from template (OpenAI Codex / API tools)
if [[ "$WITH_OPENAI" == true ]]; then
  deploy_agents_md "Deploying"
fi

# 5. Create MEMORY.md from template (if it doesn't exist)
if [[ ! -f "$PROJECT_DIR/MEMORY.md" ]]; then
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
  echo "  - .claude/skills/superpowers/ — Workflow skills"
  echo "  - .claude/commands/ — Slash commands (/brainstorm, /write-plan, /execute-plan)"
  echo "  - .claude/hooks/ — Session auto-bootstrap"
  echo ""
  echo -e "${GREEN}Skills activate automatically on Claude Code session start.${NC}"
  echo ""
fi
echo -e "${CYAN}Memory & Token Optimization deployed:${NC}"
echo "  - MEMORY.md — Persistent project memory bank"
echo "  - .claude/rules/memory-management.md — Memory update protocols"
echo "  - .claude/rules/token-optimization.md — Context efficiency rules"
echo ""
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
