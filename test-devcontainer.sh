#!/usr/bin/env bash
# Tests for the optional dev container sandbox (ai-devcontainer 2.x):
#   * sandbox_policy.py: profile + [sandbox] + integrations, +/- lists, requires, blocks
#   * ai-devcontainer.py: generated files, nothing organization-specific without a profile,
#     --update keeps edits and stages new versions, domains.conf is never replaced
#   * ai-config --devcontainer: deploys the config, writes .devcontainer/, stays sticky,
#     --sandbox=none stops updating, a foreign .devcontainer/ is left alone without --force
#   * egress-credentials.sh: tokens from token-hosts.conf (a fake Keychain), per-project
#     folders, placeholders for mounted config; ensure-relay.sh's link to the 1.x state folder
# No Docker, no real Keychain, no real profile: HOME and AI_CONFIG_HOME are throwaway folders.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$HERE/devcontainer-kit"
GEN="$KIT/ai-devcontainer.py"
SETUP="$HERE/setup-project.sh"
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ko() { echo "FAIL: $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" AI_CONFIG_HOME="$work/ai-config"
export AI_CONFIG_SKIP_GLOBAL_SKILLS=1 AI_CONFIG_USER_SETTINGS=/nonexistent
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

# --- no profile: generic, nothing organization-specific ---------------------------------
P=$(new_project plain)
gen --project "$P" --out "$work/out-plain" >/dev/null
O="$work/out-plain/plain/.devcontainer"
check "no profile: core files written" '[[ -f $O/docker-compose.yml && -f $O/allowed-domains.txt && -f $O/token-hosts.conf && -f $O/domains.conf ]]'
check "no profile: GitHub is the only integration" '[[ $(grep -vc "^#" "$O/token-hosts.conf") -eq 1 ]] && grep -q "ai-devcontainer-github" "$O/token-hosts.conf"'
check "no profile: no Playwright, wrangler or Plausible" '! grep -qi "playwright\|wrangler" "$O/Dockerfile" && ! grep -q plausible "$O/docker-compose.yml"'
# Generated files only: the copied scripts keep the 1.x paths they link to, on purpose.
check "no organization's names in the generated files" \
  '! grep -qi "cps\|paediatric\|caringforkids" "$O"/{Dockerfile,docker-compose.yml,devcontainer.json,allowed-domains.txt,README.md,managed-settings.json,token-hosts.conf,mounts.conf,domains.conf}'
check "relay token mounted for a project without DDEV" 'grep -qE "relay/tokens/plain-[0-9a-f]{8}\.token:/run/ddev-relay/token:ro" "$O/docker-compose.yml"'
check "the project key carries a hash of its folder" 'grep -qE "ensure-relay.sh .* plain-[0-9a-f]{8}" "$O/devcontainer.json"'
check "ai-config.conf is mounted read-only even when missing" 'grep -q "../ai-config.conf:/workspace/ai-config.conf:ro" "$O/docker-compose.yml"'
check "init command starts the relay without DDEV" 'grep -q "ensure-relay.sh" "$O/devcontainer.json" && ! grep -q "ensure-ddev.sh" "$O/devcontainer.json"'
check "sandbox-domains is installed in the image" 'grep -q "/usr/local/bin/sandbox-domains" "$O/Dockerfile"'
check "kit sources name no organization" '! grep -rqiE "cps\.ca|paediatric|statements studio" "$KIT/ai-devcontainer.py" "$KIT/sandbox_policy.py" "$KIT/integrations"'

# --- a profile and project settings ------------------------------------------------------
cat > "$AI_CONFIG_HOME/profiles/acme.conf" <<'EOF'
name = Test Person
share_domain = share.acme.example
plausible_host = stats.acme.example
devcontainer_integrations = playwright, cloudflare, plausible, mailtrap
devcontainer_domains = .acme.example
devcontainer_hosts = www.acme.example
EOF
A=$(new_project acme)
printf '[options]\nprofile = acme\n\n[sandbox]\nintegrations = +stripe, -mailtrap, +nonesuch\nhosts = api.client.example\nblock = js.stripe.com, claude.ai, api.stripe.com\n' > "$A/ai-config.conf"
out=$(gen --project "$A" --out "$work/out-acme")
O="$work/out-acme/acme/.devcontainer"
check "profile integrations, with the project's +/-" '[[ "$out" == *"Integrations: github, playwright, cloudflare, plausible, stripe"* ]]'
check "an unknown integration is a follow-up, not an error" '[[ "$out" == *"integration '"'"'nonesuch'"'"' not found"* ]]'
check "Claude Code's hosts can't be blocked" '[[ "$out" == *"Not blocked (Claude Code needs them): claude.ai"* ]] && grep -qx claude.ai <(hosts_of "$O/allowed-domains.txt")'
check "a blocked host is left out of the generated list" '! grep -qx api.stripe.com <(hosts_of "$O/allowed-domains.txt")'
check "the block is also written to the first domains.conf" 'sed -n "/^\[block\]/,\$p" "$O/domains.conf" | grep -qx api.stripe.com'
check "profile domains and project hosts allowed" 'hosts_of "$O/allowed-domains.txt" | grep -qx .acme.example && hosts_of "$O/allowed-domains.txt" | grep -qx api.client.example'
check "integration hosts filled from the profile" 'hosts_of "$O/allowed-domains.txt" | grep -qx stats.acme.example && hosts_of "$O/allowed-domains.txt" | grep -qx share.acme.example'
check "mailtrap removed by the project" '! hosts_of "$O/allowed-domains.txt" | grep -q mailtrap'
check "per-profile Keychain and volume names" 'grep -q "acme-devcontainer-github" "$O/token-hosts.conf" && grep -q "cloudflare-api-acme" "$O/token-hosts.conf" && grep -q "name: acme-cloudflare-config" "$O/docker-compose.yml"'
check "the profile reaches the container" 'grep -q "AI_CONFIG_PROFILE: acme" "$O/docker-compose.yml"'
check "Playwright and wrangler only when their integration is on" 'grep -q "playwright==" "$O/Dockerfile" && grep -q "wrangler@4" "$O/Dockerfile"'
check "integration deny rules reach managed settings" 'grep -q "plausible/api-key" "$O/managed-settings.json"'

# requires: plausible without plausible_host is left out, with a follow-up.
printf 'devcontainer_integrations = plausible\n' > "$AI_CONFIG_HOME/profiles/bare.conf"
B=$(new_project bare)
printf '[options]\nprofile = bare\n' > "$B/ai-config.conf"
out=$(gen --project "$B" --list; gen --project "$B")
check "an integration missing a required setting is left out" '[[ "$out" == *"integration plausible needs plausible_host"* ]]'

# A private integration overrides a built-in one of the same name.
mkdir -p "$AI_CONFIG_HOME/devcontainer/integrations"
printf '[integration]\ndescription = private flowbite\n[hosts]\nprivate.flowbite.example\n' > "$AI_CONFIG_HOME/devcontainer/integrations/flowbite.conf"
F=$(new_project fb)
printf '[sandbox]\nintegrations = +flowbite\n' > "$F/ai-config.conf"
gen --project "$F" --out "$work/out-fb" >/dev/null
check "a private integration wins over the built-in one" 'hosts_of "$work/out-fb/fb/.devcontainer/allowed-domains.txt" | grep -qx private.flowbite.example && ! hosts_of "$work/out-fb/fb/.devcontainer/allowed-domains.txt" | grep -qx flowbite.com'

# --- --write / --update ------------------------------------------------------------------
W=$(new_project upd)
gen --project "$W" --write >/dev/null
D="$W/.devcontainer"
check "--write creates .devcontainer with a manifest" '[[ -f $D/.ai-devcontainer.manifest && -x $D/sandbox-domains.sh ]]'
echo "api.mine.example" >> "$D/domains.conf"
echo "# my edit" >> "$D/Dockerfile"
gen --project "$W" --update >/dev/null
check "--update keeps an edited file" 'grep -q "# my edit" "$D/Dockerfile"'
check "--update stages the new version" '[[ -f $W/.claude/ai-config/pending/.devcontainer/Dockerfile ]]'
check "domains.conf is never replaced" 'grep -q api.mine.example "$D/domains.conf"'
printf '[sandbox]\nhosts = added.example\n' > "$W/ai-config.conf"
out=$(gen --project "$W" --update </dev/null)
check "a widening refresh lists the new host and, unconfirmed, leaves it out" \
  '[[ "$out" == *"+ reach added.example"* ]] && ! hosts_of "$D/allowed-domains.txt" | grep -qx added.example'
gen --project "$W" --update --yes </dev/null >/dev/null
check "--yes applies it (and --update rewrites an unedited file)" 'hosts_of "$D/allowed-domains.txt" | grep -qx added.example'
# ai-config.conf is in the project: it may add hosts, never decide where a token goes.
printf '[options]\nprofile = acme\n\n[sandbox]\nplausible_host = attacker.example\n' > "$W/ai-config.conf"
out=$(gen --project "$W" --update --yes </dev/null)
check "a project can't redirect a token (plausible_host comes from the profile)" \
  '[[ "$out" == *"plausible_host is ignored"* ]] && ! grep -q attacker.example "$D/token-hosts.conf" && grep -q stats.acme.example "$D/token-hosts.conf"'
mkdir -p "$work/foreign/.devcontainer" && git -C "$work/foreign" init -q && echo '{}' > "$work/foreign/.devcontainer/devcontainer.json"
out=$(gen --project "$work/foreign" --update)
check "a .devcontainer/ it didn't write is skipped" '[[ "$out" == *SKIPPED* ]] && [[ $(cat "$work/foreign/.devcontainer/devcontainer.json") == "{}" ]]'

# --- ai-config --devcontainer -------------------------------------------------------------
S=$(new_project via-setup)
"$SETUP" --project="$S" --devcontainer --force --no-superpowers --skip-vscode >"$work/setup.out" 2>&1
check "ai-config --devcontainer deploys the config first" '[[ -f $S/CLAUDE.md && -f $S/.claude/hooks/safety-guard.sh ]]'
check "ai-config --devcontainer writes .devcontainer/" '[[ -f $S/.devcontainer/.ai-devcontainer.manifest ]]'
check "the safety hook is re-registered in managed settings" 'grep -q safety-guard.sh "$S/.devcontainer/managed-settings.json"'
check "settings.local.json exists to be mounted read-only" '[[ -f $S/.claude/settings.local.json ]]'
printf '[sandbox]\nhosts = sticky.example\n' >> "$S/ai-config.conf"
"$SETUP" --project="$S" --refresh --no-superpowers --skip-vscode </dev/null >"$work/refresh.out" 2>&1
check "the sandbox is sticky on --refresh (a new host is listed, not applied unasked)" \
  'grep -q "+ reach sticky.example" "$work/refresh.out" && ! hosts_of "$S/.devcontainer/allowed-domains.txt" | grep -qx sticky.example'
"$SETUP" --project="$S" --refresh --force --no-superpowers --skip-vscode </dev/null >/dev/null 2>&1
check "ai-config --refresh --force confirms it" 'hosts_of "$S/.devcontainer/allowed-domains.txt" | grep -qx sticky.example'
printf '[sandbox]\nhosts = after-none.example\n' >> "$S/ai-config.conf"
"$SETUP" --project="$S" --refresh --sandbox=none --no-superpowers --skip-vscode >/dev/null 2>&1
check "--sandbox=none stops updating and deletes nothing" '[[ -d $S/.devcontainer ]] && ! hosts_of "$S/.devcontainer/allowed-domains.txt" | grep -qx after-none.example'
"$SETUP" --project="$S" --doctor >"$work/doctor.out" 2>&1
check "--doctor reports the sandbox" 'grep -q "Sandbox: dev container (2" "$work/doctor.out"'
X=$(new_project plain-setup)
"$SETUP" --project="$X" --force --no-superpowers --skip-vscode >/dev/null 2>&1
check "without the flag, no .devcontainer/ appears" '[[ ! -e $X/.devcontainer ]]'
Y=$(new_project foreign-setup)
mkdir -p "$Y/.devcontainer" && echo '{}' > "$Y/.devcontainer/devcontainer.json"
"$SETUP" --project="$Y" --devcontainer --no-superpowers --skip-vscode >"$work/y.out" 2>&1
check "a foreign .devcontainer/ is left alone without --force" '[[ $(cat "$Y/.devcontainer/devcontainer.json") == "{}" ]] && grep -q "left alone" "$work/y.out"'

# --- Mac-side scripts ---------------------------------------------------------------------
# The 1.x state folder is linked, never moved, so running 1.x containers keep their mounts.
# A fresh HOME: the steps above already created the new folder in the first one.
export HOME="$work/home-mac"
mkdir -p "$HOME/.cache/cps-devcontainer/relay"
H="$work/h-proj"; mkdir -p "$H/.devcontainer"
# No relay is started here: test-ddev-relay.sh tests the relay, on its own port, and stops only
# the PID it launched. Never sweep processes by pattern: on macOS `pkill -f PATTERN -u UID` treats
# "-u" and the UID as more patterns and kills unrelated apps (it took down VS Code and Chrome).
# Tokens come from token-hosts.conf only; a fake Keychain stands in for security(1).
printf 'GITHUB_TOKEN\tt-gh\tgithub\tgithub.com api.github.com\nPLAUSIBLE_API_KEY\tt-pl\tbearer\tstats.example\n' > "$H/.devcontainer/token-hosts.conf"
printf 'plausible\t~/.config/plausible\tconfig\tapi-key\n' > "$H/.devcontainer/mounts.conf"
mkdir -p "$HOME/.config/plausible" && echo "site=x" > "$HOME/.config/plausible/config"
printf 't-gh=fake.gh.1\nother=never.copied\n' > "$work/keychain"
# A hostname as long as GitHub's macOS runners': the CA's common name must still fit in 64.
mkdir -p "$work/long-host-bin"
printf '#!/bin/sh\necho dsm12-dh249-ac27c7cb-a29d-4e74-bd30-b8dc46599682-0123456789\n' > "$work/long-host-bin/hostname"
chmod 755 "$work/long-host-bin/hostname"
out=$(PATH="$work/long-host-bin:$PATH" AI_DEVCONTAINER_FAKE_KEYCHAIN="$work/keychain" \
  bash "$KIT/files/egress-credentials.sh" "$H" hproj 2>&1)
E="$HOME/.cache/ai-devcontainer/egress/projects/hproj"
egress_diag=""
[[ -f "$E/credentials.env" ]] || egress_diag="${out:-(no output)}"
check "the new state folder links to the 1.x one" '[[ -L $HOME/.cache/ai-devcontainer && -d $HOME/.cache/cps-devcontainer/egress ]]'
check "only the listed Keychain items are copied" 'grep -q "^GITHUB_TOKEN=fake.gh.1$" "$E/credentials.env" && ! grep -q never.copied "$E/credentials.env"'
check "missing items are named, values never printed" '[[ "$out" == *"t-pl"* && "$out" != *fake.gh.1* ]]'
# GNU stat first: on Linux `stat -f` means filesystem status and succeeds, so it can't go first.
check "credentials.env is private" '[[ $(stat -c %a "$E/credentials.env" 2>/dev/null || stat -f %Lp "$E/credentials.env") == 600 ]]'
check "mounted config is copied, its key file is the placeholder" 'grep -q site=x "$E/mounts/plausible/config" && grep -qx ai-egress-placeholder "$E/mounts/plausible/api-key"'
check "the CA is shared by every project" '[[ -s $HOME/.cache/ai-devcontainer/egress/ca.crt ]]'

# --- Enclave (--sandbox=enclave): Enclave's config root follows HOME, so it's throwaway too -----
if command -v enclave >/dev/null 2>&1; then
  export HOME="$work/home-enclave"; mkdir -p "$HOME"
  N=$(new_project enc)
  printf '[options]\nprofile = acme\n\n[sandbox]\nhosts = api.enc.example\nblock = mailtrap.io\n' > "$N/ai-config.conf"
  "$SETUP" --project="$N" --sandbox=enclave --force --no-superpowers --skip-vscode >"$work/enc.out" 2>&1
  CFG=$(find "$HOME" -path '*org.eclipse.enclave/config/projects/*/config.json' | head -1)
  PATCH=$(find "$HOME" -path '*org.eclipse.enclave/config/projects/*/patches/claude/settings.json' | head -1)
  check "enclave: project config written outside the repo" '[[ -n "$CFG" && "$CFG" != "$N"* ]]'
  check "enclave: Enclave validated it" 'grep -q "Enclave validated it" "$work/enc.out"'
  check "enclave: project and integration hosts allowed" 'grep -q "+api.enc.example" "$CFG" && grep -q "+stats.acme.example" "$CFG"'
  check "enclave: blocked host left off, and the gap reported" '! grep -q "+mailtrap.io\"" "$CFG" && grep -q "Enclave has no block list" "$work/enc.out"'
  check "enclave: guardrail folders read-only" 'grep -q "/.claude/hooks" "$CFG"'
  check "enclave: safety hook in Claude's settings patch, once" '[[ $(grep -c safety-guard "$PATCH") -eq 1 ]]'
  check "enclave: tokens Enclave can't inject are reported" 'grep -q "only injects the GitHub token" "$work/enc.out"'
  python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['allow_domains'].append('+mine.example'); open(p,'w').write(json.dumps(d))" "$CFG"
  "$SETUP" --project="$N" --refresh --sandbox=enclave --no-superpowers --skip-vscode >/dev/null 2>&1
  check "enclave: a refresh keeps your own entries, adds no duplicates" \
    'grep -q "+mine.example" "$CFG" && [[ $(python3 -c "import json,sys; a=json.load(open(sys.argv[1]))[\"allow_domains\"]; print(len(a)-len(set(a)))" "$CFG") -eq 0 ]]'
  check "enclave: the hook isn't added twice on refresh" '[[ $(grep -c safety-guard "$PATCH") -eq 1 ]]'
  check "enclave: the ownership record lives outside the worktree" \
    '[[ -f "$(dirname "$CFG")/ai-config-owned.json" ]] && ! grep -q allow_domains "$N/.claude/ai-config/enclave.json"'
  # ai-config.conf is writable inside Enclave: a widening is listed and, without a terminal, left out.
  printf 'hosts = api.enc.example, sneaky.example\n' >> "$N/ai-config.conf"
  "$SETUP" --project="$N" --refresh --no-superpowers --skip-vscode </dev/null >"$work/enc2.out" 2>&1
  check "enclave: new hosts are listed and not applied without confirmation" \
    'grep -q "+ sneaky.example" "$work/enc2.out" && ! grep -q "+sneaky.example" "$CFG"'
  "$SETUP" --project="$N" --refresh --force --no-superpowers --skip-vscode </dev/null >/dev/null 2>&1
  check "enclave: --force confirms them" 'grep -q "+sneaky.example" "$CFG"'
  # A tampered in-repo record can't make a refresh drop your own entries any more.
  printf '{"allow_domains":["mine.example"],"deny":[]}\n' > "$N/.claude/ai-config/enclave.json"
  "$SETUP" --project="$N" --refresh --no-superpowers --skip-vscode </dev/null >/dev/null 2>&1
  check "enclave: an edited in-repo marker doesn't remove your entries" 'grep -q "+mine.example" "$CFG"'
else
  echo "SKIP: enclave not installed (Enclave cases)"
fi

# Printed last so run-tests.sh's 30-line tail shows why the Mac-side script stopped.
if [[ -n "${egress_diag:-}" ]]; then
  printf '\negress-credentials.sh wrote no token file; it said:\n%s\n' "$egress_diag"
fi
echo ""
echo "devcontainer: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
