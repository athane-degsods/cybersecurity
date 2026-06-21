#!/usr/bin/env bash
# Next.js deep fingerprint + route discovery for HTB Reactor
# Usage: ./nextjs-deep-enum.sh [host] [port]
set -euo pipefail

TARGET="${1:-10.129.32.211}"
PORT="${2:-3000}"
BASE="http://${TARGET}:${PORT}"
OUTDIR="$(dirname "$0")/nextjs-scan"
mkdir -p "$OUTDIR"/{chunks,maps,manifests}

log() { printf '[*] %s\n' "$*"; }
die() { printf '[!] %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }
need curl
need grep
need jq

log "Target: $BASE"
log "Output: $OUTDIR"

# --- connectivity ---
if ! curl -sS --connect-timeout 5 -o "$OUTDIR/index.html" -w '%{http_code}' "$BASE/" | grep -q '^200$'; then
  die "Cannot reach $BASE/ (machine down, VPN, or port filtered). Start HTB box first."
fi

# --- headers ---
curl -sS -D "$OUTDIR/headers.txt" -o /dev/null "$BASE/"
log "Saved headers -> $OUTDIR/headers.txt"

# --- build ID (App Router: RSC "b" field; Pages Router: __NEXT_DATA__) ---
BUILD_ID=""
# App Router RSC payload (escaped or plain JSON)
BUILD_ID="$(sed -n 's/.*\\"b\\":\\"\([^"\\]*\)\\".*/\1/p' "$OUTDIR/index.html" | head -1)"
[[ -z "$BUILD_ID" ]] && BUILD_ID="$(sed -n 's/.*"b":"\([^"]*\)".*/\1/p' "$OUTDIR/index.html" | head -1)"
# Pages Router fallback
[[ -z "$BUILD_ID" ]] && BUILD_ID="$(sed -n 's/.*"buildId":"\([^"]*\)".*/\1/p' "$OUTDIR/index.html" | head -1)"
printf '%s\n' "$BUILD_ID" > "$OUTDIR/build-id.txt"
log "Build ID: ${BUILD_ID:-<not found>}"

# --- manifest files (route map goldmine) ---
if [[ -n "$BUILD_ID" ]]; then
  for f in _buildManifest.js _ssgManifest.js; do
    url="$BASE/_next/static/${BUILD_ID}/${f}"
    code="$(curl -sS -o "$OUTDIR/manifests/${f}" -w '%{http_code}' "$url" || true)"
    log "Manifest $f -> HTTP $code"
  done
  if [[ -f "$OUTDIR/manifests/_buildManifest.js" ]]; then
    # Pretty-print route keys from build manifest
    grep -oE '"/[^"]+"' "$OUTDIR/manifests/_buildManifest.js" 2>/dev/null \
      | tr -d '"' | sort -u > "$OUTDIR/routes-from-manifest.txt" || true
    log "Routes extracted -> $OUTDIR/routes-from-manifest.txt"
  fi
fi

# --- download all JS chunks referenced on homepage ---
grep -oE '/_next/static/[^"'\'' ]+\.js' "$OUTDIR/index.html" | sort -u > "$OUTDIR/chunk-urls.txt"
while read -r path; do
  [[ -z "$path" ]] && continue
  fname="$(basename "$path")"
  curl -sS "$BASE${path}" -o "$OUTDIR/chunks/${fname}" 2>/dev/null || true
  # probe sourcemap (primary version fingerprint vector)
  map_code="$(curl -sS -o "$OUTDIR/maps/${fname}.map" -w '%{http_code}' "${BASE}${path}.map" 2>/dev/null || echo 000)"
  [[ "$map_code" == "200" ]] && log "Sourcemap found: ${path}.map"
done < "$OUTDIR/chunk-urls.txt"

# --- extract Next.js + React versions from sourcemaps ---
: > "$OUTDIR/versions.txt"
for mapfile in "$OUTDIR"/maps/*.map; do
  [[ -f "$mapfile" ]] || continue
  for pkg in next react react-dom; do
    ver="$(jq -r --arg pkg "$pkg" '
      (.sources | to_entries[]) |
      select(.value | endswith("node_modules/\($pkg)/package.json")) |
      .key as $i | .sourcesContent[$i] // empty |
      fromjson? | .version // empty
    ' "$mapfile" 2>/dev/null | head -1)"
    [[ -n "$ver" && "$ver" != "null" ]] && echo "${pkg}=${ver} (from $(basename "$mapfile"))" >> "$OUTDIR/versions.txt"
  done
done
sort -u "$OUTDIR/versions.txt" -o "$OUTDIR/versions.txt" 2>/dev/null || true

# --- grep bundles for routes, actions, secrets ---
{
  echo "=== API / fetch paths ==="
  grep -rhoE '"/api/[^"]+"|'\''/api/[^'\'']+'\''' "$OUTDIR/chunks" 2>/dev/null | tr -d '"'\''' | sort -u
  echo
  echo "=== Server Action IDs (40-char hex) ==="
  grep -rhoE '\b[0-9a-f]{40}\b' "$OUTDIR/chunks" 2>/dev/null | sort -u
  echo
  echo "=== Interesting strings ==="
  grep -riE 'password|secret|token|api[_-]?key|NEXT_|process\.env|admin|login|upload' "$OUTDIR/chunks" 2>/dev/null \
    | head -50
} > "$OUTDIR/chunk-grep.txt"

# --- probe high-value Next.js paths ---
: > "$OUTDIR/path-probe.txt"
PATHS=(
  /api /api/health /api/status /api/auth /api/login /api/users
  /admin /dashboard /login /register /upload /debug
  /_next/webpack-hmr /_next/data /_next/image
  /robots.txt /sitemap.xml /.env /env.js /config.json
  /package.json /next.config.js /server.js
)
for p in "${PATHS[@]}"; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE${p}" 2>/dev/null || echo 000)"
  printf '%s\t%s\n' "$code" "$p" >> "$OUTDIR/path-probe.txt"
done

# --- summary ---
{
  echo "=== NEXT.JS DEEP ENUM SUMMARY ==="
  echo "Target: $BASE"
  echo "Build ID: ${BUILD_ID:-n/a}"
  echo
  echo "--- Response headers (version hints) ---"
  grep -iE '^(x-powered-by|server|x-nextjs|vary|cache-control):' "$OUTDIR/headers.txt" || true
  echo
  echo "--- Versions (from sourcemaps) ---"
  cat "$OUTDIR/versions.txt" 2>/dev/null || echo "(none — sourcemaps disabled or not exposed)"
  echo
  echo "--- Routes from _buildManifest.js ---"
  cat "$OUTDIR/routes-from-manifest.txt" 2>/dev/null || echo "(manifest not available)"
  echo
  echo "--- Path probe (non-404) ---"
  awk '$1 != "404" && $1 != "000"' "$OUTDIR/path-probe.txt"
} | tee "$OUTDIR/SUMMARY.txt"

log "Done. Read $OUTDIR/SUMMARY.txt first."
