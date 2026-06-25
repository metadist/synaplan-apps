#!/usr/bin/env bash
#
# build.sh — Reproducible build of the bundled Synaplan SPA for the native apps.
#
# What it does:
#   1. Ensure the `synaplan` submodule is checked out at its pinned tag.
#   2. Build the frontend → synaplan/frontend/dist/ (the WebView payload).
#   3. If Capacitor is set up (Epic 1+), sync the web assets into ios/ + android/.
#
# Requirements on a clean machine: Node 22+ and (for `cap sync`) the npm deps of this repo.
# Usage:
#   ./build.sh            # full build (+ cap sync if available)
#   ./build.sh --web-only # only build the frontend dist/, skip cap sync
#
# Environment:
#   SYNAPLAN_OPENAPI_URL  OpenAPI spec used to generate the frontend's Zod API schemas.
#                         The generated code (src/generated/) is gitignored in the submodule,
#                         so it MUST be produced at build time. Defaults to production.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

SYNAPLAN_OPENAPI_URL="${SYNAPLAN_OPENAPI_URL:-https://web.synaplan.com/api/doc.json}"

WEB_ONLY=false
if [[ "${1:-}" == "--web-only" ]]; then
  WEB_ONLY=true
fi

echo "==> [1/3] Ensuring submodule is initialized at its pinned tag"
git submodule update --init --recursive

echo "==> [2/3] Building frontend (synaplan/frontend → dist/)"
pushd synaplan/frontend >/dev/null
if [[ -f package-lock.json ]]; then
  npm ci
else
  npm install
fi

# The frontend's API layer imports from src/generated/api-schemas.ts, which is gitignored
# (generated from the backend OpenAPI spec). Produce it here from the configured spec, then
# run the submodule's own post-processor (--skip-fetch = no second download) so the Zod v4
# fixes + readable aliases stay identical to the platform's pipeline.
echo "    Generating API schemas from: ${SYNAPLAN_OPENAPI_URL}"
mkdir -p src/generated
npx openapi-zod-client "${SYNAPLAN_OPENAPI_URL}" -o src/generated/api-schemas.ts --template schema-template.hbs
node scripts/generate-schemas.js --skip-fetch

npm run build
popd >/dev/null
echo "    Built: synaplan/frontend/dist/"

echo "==> [2.5/3] Injecting app-owned native bootstrap (Server config, Epic 3 §3.0)"
# The in-app server switcher + its pre-SPA bootstrap live ENTIRELY in this repo
# (zero blast radius in the public submodule). We copy the app-owned script into
# the bundled dist/ and inject it as the FIRST <script> in index.html so it runs
# before the SPA's deferred ES module and can set window.__SYNAPLAN_API_BASE_URL__.
DIST_DIR="synaplan/frontend/dist"
INDEX_HTML="$DIST_DIR/index.html"
NATIVE_JS="app/synaplan-native.js"
if [[ -f "$INDEX_HTML" && -f "$NATIVE_JS" ]]; then
  cp "$NATIVE_JS" "$DIST_DIR/synaplan-native.js"

  # Epic 10.1: stamp the resolved build identity into the bundle so the app-owned
  # bootstrap can render a non-prod environment badge (visible env indicator) and
  # expose the version/build for debugging. These are NOT secrets.
  APP_ENV="${SYNAPLAN_ENV:-prod}"
  APP_VERSION="$(node -p "require('./package.json').version")"
  APP_BUILD="${SYNAPLAN_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
  cat > "$DIST_DIR/synaplan-env.js" <<EOF
window.__SYNAPLAN_ENV__ = "${APP_ENV}";
window.__SYNAPLAN_APP_VERSION__ = "${APP_VERSION}";
window.__SYNAPLAN_BUILD__ = "${APP_BUILD}";
EOF
  echo "    Stamped env=${APP_ENV} version=${APP_VERSION} build=${APP_BUILD} into $DIST_DIR/synaplan-env.js"

  if grep -q 'synaplan-native.js' "$INDEX_HTML"; then
    echo "    Bootstrap already present in index.html — skipping inject"
  else
    # Insert right after <head> so they are the first scripts the WebView evaluates,
    # env stamp BEFORE the bootstrap so window.__SYNAPLAN_ENV__ is set when it runs.
    # Use a portable perl one-liner (works on macOS + Linux build agents).
    perl -0pi -e 's/(<head[^>]*>)/$1\n    <script src="\/synaplan-env.js"><\/script>\n    <script src="\/synaplan-native.js"><\/script>/i' "$INDEX_HTML"
    echo "    Injected /synaplan-env.js + /synaplan-native.js into $INDEX_HTML"
  fi
else
  echo "    WARNING: $INDEX_HTML or $NATIVE_JS missing — skipped bootstrap inject"
fi

if [[ "$WEB_ONLY" == true ]]; then
  echo "==> [3/3] Skipping cap sync (--web-only)"
  exit 0
fi

if [[ -f capacitor.config.ts || -f capacitor.config.js || -f capacitor.config.json ]]; then
  echo "==> [3/3] Syncing web assets into native projects (npx cap sync)"
  if [[ ! -d node_modules ]]; then
    npm ci || npm install
  fi
  # Epic 10.1: stamp version + per-env bundle id / display name into the iOS
  # project (Android is configured Gradle-natively at build time). Idempotent.
  echo "    Applying app config (Epic 10.1) to native projects"
  node scripts/app-config.mjs
  npx cap sync
else
  echo "==> [3/3] Capacitor not set up yet (Epic 1) — skipping cap sync"
fi

echo "==> Done."
