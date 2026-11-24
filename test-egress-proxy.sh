#!/usr/bin/env bash
# Tests for devcontainer-kit/files/egress-proxy.sh token injection (kit 1.16.0).
#
# Builds the kit's proxy image and runs it on a private Docker network next to a fake upstream
# that answers as api.github.com, github.com, uploads.github.com, plausible.cps.ca,
# api.cloudflare.com and registry.npmjs.org, and echoes back the Authorization header it got.
# Everything is throwaway: a test CA for the proxy, another for the fake upstream, fake tokens.
# No real host and no real token is involved. Needs Docker; skips without it.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$HERE/devcontainer-kit"
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ko() { echo "FAIL: $1"; fail=$((fail + 1)); }
expect() { # expect <name> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else ko "$1 [expected '$2', got '${3:0:200}']"; fi
}

if ! docker info >/dev/null 2>&1; then
  echo "SKIP: Docker is not available"
  exit 0
fi

id="ai-egress-test-$$"
work=$(mktemp -d)
cleanup() {
  docker rm -f "$id-proxy" "$id-upstream" >/dev/null 2>&1
  docker network rm "$id" >/dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT

GH_FAKE="fake.github.token.1"
PLAUSIBLE_FAKE="fake.plausible.key.2"
CLOUDFLARE_FAKE="fake.cloudflare.token.3"
PLACEHOLDER="ai-egress-placeholder"
TOKEN_SCHEME_FAKE="fake.token.scheme.4"
CRED_NAMES="api.github.com github.com uploads.github.com stats.example.test api.cloudflare.com tokens.example.test"
SPLICE_NAME="registry.npmjs.org"
BLOCK_NAME="blocked.example.test"
ALL_NAMES="$CRED_NAMES $SPLICE_NAME $BLOCK_NAME"

# --- certificates (inside a container, so macOS LibreSSL and CI OpenSSL behave the same) --
mkdir -p "$work/egress" "$work/egress-ca" "$work/upstream" "$work/sandbox"
docker run --rm -v "$work:/w" debian:bookworm-slim sh -ec "
  apt-get update -qq >/dev/null && apt-get install -y -qq openssl >/dev/null
  cd /w
  openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj '/CN=test egress CA' \
    -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign \
    -keyout egress/ca.key -out egress/ca.crt 2>/dev/null
  openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj '/CN=test upstream CA' \
    -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign \
    -keyout upstream/ca.key -out upstream/ca.crt 2>/dev/null
  san=\$(for n in $ALL_NAMES; do printf 'DNS:%s,' \$n; done)
  openssl req -new -newkey rsa:2048 -nodes -subj '/CN=fake upstream' \
    -keyout upstream/server.key -out upstream/server.csr 2>/dev/null
  printf 'subjectAltName=%s\n' \"\${san%,}\" > upstream/ext.cnf
  openssl x509 -req -in upstream/server.csr -CA upstream/ca.crt -CAkey upstream/ca.key \
    -CAcreateserial -days 2 -extfile upstream/ext.cnf -out upstream/server.crt 2>/dev/null
  chmod 644 egress/* upstream/*
" || { echo "FAIL: could not create test certificates"; exit 1; }

cp "$work/egress/ca.crt" "$work/egress/ca.key" "$work/egress-ca/"
printf 'GITHUB_TOKEN=%s\nPLAUSIBLE_API_KEY=%s\nCLOUDFLARE_API_TOKEN=%s\nTOKEN_SCHEME_KEY=%s\n' \
  "$GH_FAKE" "$PLAUSIBLE_FAKE" "$CLOUDFLARE_FAKE" "$TOKEN_SCHEME_FAKE" > "$work/egress/credentials.env"
# What the generator writes: which variable goes to which hosts, and how (names only).
printf '%s\t%s\t%s\t%s\n' \
  GITHUB_TOKEN test-github github 'github.com api.github.com uploads.github.com' \
  PLAUSIBLE_API_KEY plausible-api bearer stats.example.test \
  CLOUDFLARE_API_TOKEN cloudflare-api bearer api.cloudflare.com \
  TOKEN_SCHEME_KEY token-api token tokens.example.test > "$work/sandbox/token-hosts.conf"
# blocked.example.test is on the generated list but blocked in domains.conf; the block wins.
printf '%s\n' $ALL_NAMES > "$work/sandbox/allowed-domains.txt"
printf '[allow]\n\n[block]\n%s  # test\n' "$BLOCK_NAME" > "$work/sandbox/domains.conf"

# --- fake upstream: echoes the Authorization header on 80 and 443 -------------------------
cat > "$work/upstream/echo.py" <<'EOF'
import http.server, json, ssl, threading

class Echo(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"host": self.headers.get("Host", ""),
                           "auth": self.headers.get("Authorization", "")}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

def serve(port, tls):
    server = http.server.ThreadingHTTPServer(("0.0.0.0", port), Echo)
    if tls:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain("/u/server.crt", "/u/server.key")
        server.socket = ctx.wrap_socket(server.socket, server_side=True)
    server.serve_forever()

threading.Thread(target=serve, args=(80, False), daemon=True).start()
serve(443, True)
EOF

# A subnet the proxy's private-destination list doesn't cover (benchmarking range, RFC 2544):
# it refuses RFC 1918, carrier-grade NAT, loopback and link-local destinations, as it should.
docker network create --subnet 198.18.77.0/24 "$id" >/dev/null || { echo "FAIL: network"; exit 1; }
aliases=()
for n in $ALL_NAMES; do aliases+=(--network-alias "$n"); done
docker run -d --name "$id-upstream" --network "$id" "${aliases[@]}" -v "$work/upstream:/u:ro" \
  python:3.12-alpine python /u/echo.py >/dev/null || { echo "FAIL: upstream"; exit 1; }

# --- the kit's proxy image ----------------------------------------------------------------
mkdir -p "$work/build"
python3 -I - "$KIT/ai-devcontainer.py" "$work/build/Dockerfile.proxy" <<'EOF'
import importlib.util, os, sys
sys.path.insert(0, os.path.dirname(sys.argv[1]))
spec = importlib.util.spec_from_file_location("kit", sys.argv[1])
kit = importlib.util.module_from_spec(spec)
sys.modules["kit"] = kit  # @dataclass looks its module up here
spec.loader.exec_module(kit)
open(sys.argv[2], "w").write(kit.gen_proxy_dockerfile())
EOF
cp "$KIT/files/egress-proxy.sh" "$work/build/"
docker build -q -t "$id-image" -f "$work/build/Dockerfile.proxy" "$work/build" >/dev/null \
  || { echo "FAIL: proxy image build"; exit 1; }

start_proxy() { # start_proxy: proxy trusting the fake upstream's CA (stands in for the public CAs)
  docker rm -f "$id-proxy" >/dev/null 2>&1
  docker run -d --name "$id-proxy" --network "$id" \
    -v "$work/sandbox:/etc/sandbox:ro" -v "$work/egress:/etc/sandbox-egress:ro" \
    -v "$work/egress-ca:/etc/sandbox-egress-ca:ro" \
    -v "$work/upstream/ca.crt:/usr/local/share/ca-certificates/test-upstream.crt:ro" \
    --entrypoint sh "$id-image" -c 'update-ca-certificates >/dev/null 2>&1; exec /usr/local/sbin/egress-proxy.sh' \
    >/dev/null || return 1
  for _ in $(seq 1 40); do
    docker logs "$id-proxy" 2>&1 | grep -q 'Accepting ' && return 0
    sleep 0.5
  done
  docker logs "$id-proxy" 2>&1 | tail -20
  return 1
}

client() { # client <curl args…>: curl through the proxy, trusting only the proxy's CA
  docker run --rm --network "$id" -v "$work:/w:ro" curlimages/curl:8.11.1 \
    -s -m 15 -x "http://$id-proxy:3128" --cacert /w/egress/ca.crt "$@"
}
auth_of() { sed -n 's/.*"auth": "\([^"]*\)".*/\1/p'; }

if ! start_proxy; then
  ko "proxy starts with token injection"
  echo "Results: $pass passed, $fail failed"
  exit 1
fi
ok "proxy starts with token injection"

ph="Authorization: Bearer $PLACEHOLDER"
expect "api.github.com gets the real token as Bearer" "Bearer $GH_FAKE" \
  "$(client -H "$ph" https://api.github.com/user | auth_of)"
expect "uploads.github.com gets the real token as Bearer" "Bearer $GH_FAKE" \
  "$(client -H "$ph" https://uploads.github.com/ | auth_of)"
expected_basic="Basic $(printf 'x-access-token:%s' "$GH_FAKE" | base64 | tr -d '\n')"
expect "github.com (git) gets the real token as Basic" "$expected_basic" \
  "$(client -u "x-access-token:$PLACEHOLDER" https://github.com/org/repo.git/info/refs | auth_of)"
expect "stats.example.test gets the Plausible key" "Bearer $PLAUSIBLE_FAKE" \
  "$(client -H "$ph" https://stats.example.test/api/v1/stats/aggregate | auth_of)"
expect "the token scheme sends 'Token <value>'" "Token $TOKEN_SCHEME_FAKE" \
  "$(client -H "$ph" https://tokens.example.test/ | auth_of)"
expect "api.cloudflare.com gets the Cloudflare token" "Bearer $CLOUDFLARE_FAKE" \
  "$(client -H "$ph" https://api.cloudflare.com/client/v4/user/tokens/verify | auth_of)"
expect "a token the client sends itself is replaced, not passed on" "Bearer $GH_FAKE" \
  "$(client -H 'Authorization: Bearer someone-elses-token' https://api.github.com/ | auth_of)"
expect "plain HTTP never carries a token (and the placeholder is dropped)" "" \
  "$(client -H "$ph" http://api.github.com/ | auth_of)"

# Spliced host: not intercepted, so the proxy's CA can't verify it and the upstream's own can.
out=$(client https://$SPLICE_NAME/ -o /dev/null -w '%{http_code}'); rc=$?
if [ "$rc" -ne 0 ]; then ok "other hosts are not intercepted (proxy CA doesn't verify them)"; else
  ko "other hosts are not intercepted [rc=$rc code=$out]"; fi
expect "other hosts get the client's own Authorization untouched" "Bearer client-own" \
  "$(docker run --rm --network "$id" -v "$work:/w:ro" curlimages/curl:8.11.1 -s -m 15 \
      -x "http://$id-proxy:3128" --cacert /w/upstream/ca.crt -H 'Authorization: Bearer client-own' \
      https://$SPLICE_NAME/ | auth_of)"
# On an ssl-bump port squid accepts a denied CONNECT and serves its 403 inside TLS, so check the
# final status (init-firewall.sh's own check does the same).
expect "hosts off the allowlist are refused" "403" \
  "$(client -o /dev/null -w '%{http_code}' https://example.org/)"
expect "a domains.conf [block] beats the generated allowlist" "403" \
  "$(client -o /dev/null -w '%{http_code}' https://$BLOCK_NAME/)"

# Without tokens: the placeholder still never reaches the host, and nothing is added.
: > "$work/egress/credentials.env"
if start_proxy; then
  expect "missing token: nothing injected, placeholder dropped" "" \
    "$(client -H "$ph" https://api.github.com/ | auth_of)"
else
  ko "proxy starts without credentials"
fi

# The generated squid.conf holds tokens: squid's group only, never world-readable.
expect "squid.conf is not world-readable" "640" \
  "$(docker exec "$id-proxy" stat -c '%a' /etc/squid/squid.conf 2>/dev/null)"

docker rmi -f "$id-image" >/dev/null 2>&1
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
