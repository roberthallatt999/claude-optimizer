#!/usr/bin/env bash
# Tests for per-project VS Code config in dev containers (devcontainer-kit/vscode_policy.py):
#   * ai-config.conf [vscode]: extensions +/-, settings as JSON, language-specific keys, case kept
#   * refused: locked isolation keys, removing Claude Code, malformed values and IDs
#   * an added extension's publisher hosts go through the widening confirmation
#   * --vscode-overrides / --doctor: .vscode/settings.json (JSONC) against the container's and
#     the user's settings, plus personal preferences; the file itself is never changed
#   * --save-policy keeps [sandbox] and [vscode] verbatim (it used to drop them)
# No Docker, no real profile: HOME and AI_CONFIG_HOME are throwaway folders.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$HERE/devcontainer-kit/ai-devcontainer.py"
SETUP="$HERE/setup-project.sh"
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ko() { echo "FAIL: $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" AI_CONFIG_HOME="$work/ai-config"
export AI_CONFIG_SKIP_GLOBAL_SKILLS=1 AI_CONFIG_USER_SETTINGS=/nonexistent
export AI_CONFIG_VSCODE_USER_SETTINGS="$work/user-settings.json"
export GIT_CONFIG_GLOBAL="$work/gitconfig" GIT_CONFIG_NOSYSTEM=1
printf '[user]\n\tname = test\n\temail = test@example.invalid\n' > "$GIT_CONFIG_GLOBAL"
mkdir -p "$HOME" "$AI_CONFIG_HOME/profiles"
unset AI_CONFIG_PROFILE

new_project() { # new_project <name>: a small Astro project in its own git repo
  local d="$work/$1"
  mkdir -p "$d"
  git -C "$d" init -q
  echo '{"dependencies":{"astro":"4.0.0"}}' > "$d/package.json"
  echo "$d"
}
gen() { python3 "$GEN" "$@" 2>&1; }
hosts_of() { sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$' | sort -u; }
# jq_dc <devcontainer.json> <jq filter>: the file starts with // comment lines.
jq_dc() { grep -v '^//' "$1" | jq -r "$2"; }

# --- [vscode] in the generated devcontainer.json ------------------------------------------
P=$(new_project site)
cat > "$P/ai-config.conf" <<'EOF'
[vscode]
extensions = +streetsidesoftware.code-spell-checker, -usernamehw.errorlens  # spelling, quieter
editor.wordWrap = "on"
tailwindCSS.emmetCompletions = true
editor.rulers = [100]   # house style
files.eol = lf
twig: editor.formatOnSave = true
markdown: files.trimTrailingWhitespace = false
editor.tabSize = [2
git.terminalAuthentication = true
github.gitAuthentication = true
terminal.integrated.env.linux = {"GIT_ASKPASS": "x"}
http.proxy = "http://example.invalid"
remote.containers.foo = 1
extensions = -anthropic.claude-code, not_an_id
EOF
out=$(gen --project "$P" --out "$work/out")
DC="$work/out/site/.devcontainer/devcontainer.json"
AD="$work/out/site/.devcontainer/allowed-domains.txt"
check "an added extension is installed" 'jq_dc "$DC" ".customizations.vscode.extensions[]" | grep -qx streetsidesoftware.code-spell-checker'
check "a removed extension is left out" '! jq_dc "$DC" ".customizations.vscode.extensions[]" | grep -qx usernamehw.errorlens'
check "Claude Code can't be removed" 'jq_dc "$DC" ".customizations.vscode.extensions[]" | grep -qx anthropic.claude-code'
check "a JSON string setting applies" '[[ $(jq_dc "$DC" ".customizations.vscode.settings[\"editor.wordWrap\"]") == on ]]'
check "a setting name keeps its case" '[[ $(jq_dc "$DC" ".customizations.vscode.settings[\"tailwindCSS.emmetCompletions\"]") == true ]]'
check "a trailing comment is ignored" '[[ $(jq_dc "$DC" ".customizations.vscode.settings[\"editor.rulers\"] | tostring") == "[100]" ]]'
check "a bare word is a string" '[[ $(jq_dc "$DC" ".customizations.vscode.settings[\"files.eol\"]") == lf ]]'
check "language-specific settings become [lang] objects" \
  '[[ $(jq_dc "$DC" ".customizations.vscode.settings[\"[twig]\"][\"editor.formatOnSave\"]") == true && $(jq_dc "$DC" ".customizations.vscode.settings[\"[markdown]\"][\"files.trimTrailingWhitespace\"]") == false ]]'
check "the kit's own settings stay" '[[ $(jq_dc "$DC" ".customizations.vscode.settings[\"editor.formatOnSaveMode\"]") == modificationsIfAvailable ]]'
check "a malformed value is refused, not kept as text" '[[ $(jq_dc "$DC" ".customizations.vscode.settings[\"editor.tabSize\"]") == null && "$out" == *"editor.tabSize"*"isn'"'"'t valid JSON"* ]]'
check "isolation keys can't be turned back on" \
  '[[ $(jq_dc "$DC" ".customizations.vscode.settings[\"git.terminalAuthentication\"]") == false && $(jq_dc "$DC" ".customizations.vscode.settings[\"github.gitAuthentication\"]") == false ]]'
check "terminal env, proxy and remote settings are locked" \
  '[[ $(jq_dc "$DC" "[.customizations.vscode.settings | keys[] | select(startswith(\"terminal.integrated.env\") or startswith(\"http.\") or startswith(\"remote.\"))] | length") == 0 ]]'
check "each refusal is reported" \
  '[[ "$out" == *"git.terminalAuthentication is locked"* && "$out" == *"http.proxy is locked"* && "$out" == *"anthropic.claude-code can'"'"'t be removed"* && "$out" == *"not_an_id"*"isn'"'"'t an extension ID"* ]]'
check "the added extension's publisher hosts are allowed" 'hosts_of "$AD" | grep -qx streetsidesoftware.gallerycdn.vsassets.io'

# Pure merge behaviour: a [lang] object merges with the kit's instead of replacing it.
merge=$(cd "$HERE/devcontainer-kit" && python3 -c '
import vscode_policy as v
cfg = v.VSCodeConfig(settings={"[php]": {"editor.tabSize": 4}, "editor.formatOnSave": False})
ext, s = v.apply(["a.b"], {"[php]": {"editor.defaultFormatter": "x.y"}, "editor.formatOnSave": True}, cfg)
print(s["[php]"] == {"editor.defaultFormatter": "x.y", "editor.tabSize": 4} and s["editor.formatOnSave"] is False)')
check "a [lang] setting merges with the kit's" '[[ $merge == True ]]'

# --- widening: a new publisher on refresh asks first ------------------------------------
W=$(new_project widen)
gen --project "$W" --write </dev/null >/dev/null
printf '[vscode]\nextensions = +ms-vscode.makefile-tools\n' > "$W/ai-config.conf"
out=$(gen --project "$W" --update </dev/null)
check "an extension from a new publisher is listed and, unconfirmed, left out" \
  '[[ "$out" == *"+ reach ms-vscode.gallerycdn.vsassets.io"* ]] && ! hosts_of "$W/.devcontainer/allowed-domains.txt" | grep -qx ms-vscode.gallerycdn.vsassets.io'
gen --project "$W" --update --yes </dev/null >/dev/null
check "--yes allows its hosts" 'hosts_of "$W/.devcontainer/allowed-domains.txt" | grep -qx ms-vscode.gallerycdn.vsassets.io'

# --- .vscode/settings.json overrides ------------------------------------------------------
mkdir -p "$W/.vscode"
cat > "$W/.vscode/settings.json" <<'EOF'
{
  // Comments, a URL holding "//", and trailing commas: VS Code's JSONC.
  "editor.formatOnSave": false,          /* the container sets true */
  "editor.wordWrap": "on",
  "editor.rulers": [120],
  "editor.tabSize": 4,
  "intelephense.licenceKey": "see https://example.invalid/a//b",
  "files.associations": { "*.css": "css", },
}
EOF
printf '{\n  // mine\n  "editor.tabSize": 2,\n  "editor.rulers": [120],\n}\n' > "$AI_CONFIG_VSCODE_USER_SETTINGS"
before=$(shasum "$W/.vscode/settings.json")
rows=$(gen --project "$W" --vscode-overrides)
check "JSONC is read (comments, URL, trailing commas)" '[[ -n "$rows" ]]'
T=$'\t'
check "a container override is reported as kit" 'printf "%s\n" "$rows" | grep -qx "kit${T}editor.formatOnSave${T}false${T}true"'
check "a user override is reported as user" 'printf "%s\n" "$rows" | grep -qx "user${T}editor.tabSize${T}4${T}2"'
check "a personal preference is reported" 'printf "%s\n" "$rows" | grep -q "^personal${T}editor.wordWrap${T}"'
check "a personal key equal to the user's value isn't" '! printf "%s\n" "$rows" | grep -q "editor.rulers"'
check "the report never changes the file" '[[ $(shasum "$W/.vscode/settings.json") == "$before" ]]'
check "no .vscode/settings.json: no output" '[[ -z $(gen --project "$P" --vscode-overrides) ]]'

# --- ai-config: --save-policy keeps the kit's sections; --doctor reports overrides --------
S=$(new_project policy)
cat > "$S/ai-config.conf" <<'EOF'
[options]
stack = astro

[sandbox]
# a client API
hosts = api.client.example

[vscode]
extensions = +streetsidesoftware.code-spell-checker
twig: editor.formatOnSave = true
EOF
out=$("$SETUP" --project="$S" --save-policy </dev/null 2>&1)
check "[sandbox] and [vscode] aren't reported as unknown" '[[ "$out" != *"Unknown section"* ]]'
check "--save-policy keeps [sandbox] verbatim" 'grep -q "^# a client API$" "$S/ai-config.conf" && grep -q "^hosts = api.client.example$" "$S/ai-config.conf"'
check "--save-policy keeps [vscode] verbatim" 'grep -q "^twig: editor.formatOnSave = true$" "$S/ai-config.conf"'
first=$(grep -v "^# Written at" "$S/ai-config.conf")
"$SETUP" --project="$S" --save-policy </dev/null >/dev/null 2>&1
check "a second --save-policy changes nothing" '[[ "$(grep -v "^# Written at" "$S/ai-config.conf")" == "$first" ]]'

"$SETUP" --project="$W" --stack=astro --no-superpowers --skip-vscode </dev/null >/dev/null 2>&1
out=$("$SETUP" --project="$W" --doctor </dev/null 2>&1)
check "--doctor warns about a container override" '[[ "$out" == *".vscode/settings.json overrides the dev container: editor.formatOnSave = false (container: true)"* ]]'
check "--doctor lists overridden personal settings once" '[[ $(grep -c "overrides your own VS Code settings here" <<< "$out") -eq 1 && "$out" == *"editor.wordWrap"* ]]'

echo ""
echo "vscode-config: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
