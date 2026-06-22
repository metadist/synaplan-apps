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

if [[ "$WEB_ONLY" == true ]]; then
  echo "==> [3/3] Skipping cap sync (--web-only)"
  exit 0
fi

if [[ -f capacitor.config.ts || -f capacitor.config.js || -f capacitor.config.json ]]; then
  echo "==> [3/3] Syncing web assets into native projects (npx cap sync)"
  if [[ ! -d node_modules ]]; then
    npm ci || npm install
  fi
  npx cap sync
else
  echo "==> [3/3] Capacitor not set up yet (Epic 1) — skipping cap sync"
fi

echo "==> Done."
