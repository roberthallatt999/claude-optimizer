"""
review: facts about a codebase and its dev container, for a review (ai-devcontainer.py --json).

The kit's rules decide what every container gets. A review is where Claude looks for what a
codebase needs that the rules missed (a PHPStan config with no PHPStan extension, a test runner
with nothing to run it from the editor, a host an integration allows that nothing uses), and
suggests [vscode] / [sandbox] lines for ai-config.conf. This module only gathers facts.

Names only, never values: file paths that exist, dependency names, host names. It never opens
.env, auth.json or any other secret file, and reads composer.json / package.json only through
the Project the kit already parsed. Standard library only.
"""
from __future__ import annotations

import re
from pathlib import Path

# Config files that say a tool is in use. Each is looked for at the project root and in the
# folder holding package.json (themes and front-end subfolders).
SIGNAL_FILES = {
    "phpstan": ("phpstan.neon", "phpstan.neon.dist", "phpstan.dist.neon"),
    "psalm": ("psalm.xml", "psalm.xml.dist"),
    "pint": ("pint.json",),
    "phpcs": ("phpcs.xml", "phpcs.xml.dist", ".phpcs.xml", ".phpcs.xml.dist"),
    "php-cs-fixer": (".php-cs-fixer.php", ".php-cs-fixer.dist.php"),
    "rector": ("rector.php",),
    "phpunit": ("phpunit.xml", "phpunit.xml.dist"),
    "eslint": (".eslintrc", ".eslintrc.js", ".eslintrc.cjs", ".eslintrc.json", ".eslintrc.yml",
               "eslint.config.js", "eslint.config.mjs", "eslint.config.cjs", "eslint.config.ts"),
    "prettier": (".prettierrc", ".prettierrc.json", ".prettierrc.js", ".prettierrc.cjs", ".prettierrc.yml",
                 ".prettierrc.yaml", "prettier.config.js", "prettier.config.cjs", "prettier.config.mjs"),
    "stylelint": (".stylelintrc", ".stylelintrc.json", ".stylelintrc.js", ".stylelintrc.cjs",
                  "stylelint.config.js", "stylelint.config.cjs", "stylelint.config.mjs"),
    "markdownlint": (".markdownlint.json", ".markdownlint.yaml", ".markdownlint.yml", ".markdownlintrc"),
    "editorconfig": (".editorconfig",),
    "vite": ("vite.config.js", "vite.config.ts", "vite.config.mjs"),
    "webpack": ("webpack.config.js", "webpack.mix.js"),
    "tailwind": ("tailwind.config.js", "tailwind.config.ts", "tailwind.config.cjs", "tailwind.config.mjs"),
    "postcss": ("postcss.config.js", "postcss.config.cjs", "postcss.config.mjs"),
    "typescript": ("tsconfig.json",),
    "node-version": (".nvmrc", ".node-version"),
    "playwright": ("playwright.config.ts", "playwright.config.js"),
    "vitest": ("vitest.config.ts", "vitest.config.js", "vitest.config.mjs"),
    "jest": ("jest.config.js", "jest.config.ts", "jest.config.cjs"),
    "cypress": ("cypress.config.js", "cypress.config.ts"),
    "docker": ("Dockerfile", "docker-compose.yml", "compose.yaml"),
    "github-actions": (".github/workflows",),
    "rest-client": (".http",),          # folder name some projects use for .http request files
}

# Template folders by convention, and the file types inside them that matter for editor support.
TEMPLATE_DIRS = ("templates", "system/user/templates", "resources/views", "src/pages", "src/layouts",
                 "src/components", "web/app/themes", "wp-content/themes")
TEMPLATE_SUFFIXES = (".html", ".twig", ".blade.php", ".php", ".astro", ".vue", ".svelte", ".tsx", ".jsx", ".md",
                     ".mdx")
# Never descend into these when counting template files.
SKIP_DIRS = {"node_modules", "vendor", ".git", "cache", "storage", "dist", "build", ".next", ".nuxt", ".astro"}
MAX_FILES_COUNTED = 5000


def signals(path: Path, package_dir: str = "") -> dict[str, list[str]]:
    """{signal: [project-relative paths that exist]} for the tools a codebase uses."""
    roots = [path] + ([path / package_dir] if package_dir else [])
    found: dict[str, list[str]] = {}
    for name, files in SIGNAL_FILES.items():
        hits = []
        for root in roots:
            for f in files:
                candidate = root / f
                if candidate.exists():
                    hits.append(str(candidate.relative_to(path)))
        if hits:
            found[name] = sorted(set(hits))
    return found


def template_files(path: Path) -> dict[str, dict[str, int]]:
    """{template folder: {suffix: count}} for the conventional template folders that exist."""
    out: dict[str, dict[str, int]] = {}
    for rel in TEMPLATE_DIRS:
        root = path / rel
        if not root.is_dir():
            continue
        counts: dict[str, int] = {}
        seen = 0
        for f in walk(root):
            seen += 1
            if seen > MAX_FILES_COUNTED:
                break
            suffix = next((s for s in TEMPLATE_SUFFIXES if f.name.endswith(s)), None)
            if suffix:
                counts[suffix] = counts.get(suffix, 0) + 1
        if counts:
            out[rel] = dict(sorted(counts.items()))
    # A renamed EE system folder: <name>/user/templates next to admin.php's $system_path.
    for candidate in path.glob("*/user/templates"):
        rel = str(candidate.relative_to(path))
        if rel not in out and candidate.is_dir():
            counts = {}
            for f in walk(candidate):
                if f.suffix == ".html":
                    counts[".html"] = counts.get(".html", 0) + 1
            if counts:
                out[rel] = counts
    return out


def walk(root: Path):
    """Files under root, skipping dependency, build and cache folders and symlinks."""
    stack = [root]
    while stack:
        d = stack.pop()
        try:
            entries = list(d.iterdir())
        except OSError:
            continue
        for e in entries:
            if e.is_symlink():
                continue
            if e.is_dir():
                if e.name not in SKIP_DIRS and not e.name.startswith("."):
                    stack.append(e)
            elif e.is_file():
                yield e


def dependencies(composer: dict, package: dict) -> dict[str, list[str]]:
    """Dependency names (never versions' sources or scripts) from the parsed manifests."""
    def names(*sections):
        out = set()
        for s in sections:
            if isinstance(s, dict):
                out.update(k for k in s if isinstance(k, str))
        return sorted(out)
    return {
        "composer": names(composer.get("require"), composer.get("require-dev")),
        "npm": names(package.get("dependencies"), package.get("devDependencies")),
    }


def kit_version_on_disk(path: Path) -> str | None:
    """The ai-devcontainer version that wrote .devcontainer/ (from a generated file's header)."""
    for name in ("docker-compose.yml", "devcontainer.json", "Dockerfile"):
        f = path / ".devcontainer" / name
        if f.is_file():
            # The header reads "Generated by ai-devcontainer 2.2.0." — the full stop isn't the version's.
            m = re.search(r"Generated by ai-devcontainer ([0-9]+(?:\.[0-9]+)*)", f.read_text(errors="replace")[:500])
            if m:
                return m.group(1)
    return None


def pending_files(path: Path) -> list[str]:
    """Kit files you edited, whose new versions a refresh staged instead of writing."""
    pend = path / ".claude" / "ai-config" / "pending" / ".devcontainer"
    return sorted(f.name for f in pend.iterdir() if f.is_file()) if pend.is_dir() else []
