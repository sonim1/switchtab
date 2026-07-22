#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

node - "$PROJECT_ROOT/package.json" "$PROJECT_ROOT/package-lock.json" <<'NODE'
const fs = require('node:fs');
const assert = require('node:assert/strict');

const packageJson = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const packageLock = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const wranglerLock = packageLock.packages?.['node_modules/wrangler'];
const sharpLock = packageLock.packages?.['node_modules/sharp'];

assert.equal(packageJson.private, true, 'package.json must be private');
assert.equal(packageJson.devDependencies?.wrangler, '4.112.0', 'package.json must pin Wrangler to 4.112.0');
assert.equal(packageJson.overrides?.sharp, '0.35.3', 'package.json must override sharp to patched 0.35.3');
assert.equal(packageLock.packages?.['']?.devDependencies?.wrangler, '4.112.0', 'package-lock root must pin Wrangler to 4.112.0');
assert.ok(wranglerLock, 'package-lock must contain node_modules/wrangler');
assert.equal(wranglerLock.version, '4.112.0', 'locked Wrangler version must be 4.112.0');
assert.equal(wranglerLock.resolved, 'https://registry.npmjs.org/wrangler/-/wrangler-4.112.0.tgz', 'locked Wrangler resolved URL is incorrect');
assert.equal(typeof wranglerLock.integrity, 'string', 'locked Wrangler integrity must be a string');
assert.ok(wranglerLock.integrity.length > 0, 'locked Wrangler integrity must be non-empty');
assert.match(wranglerLock.integrity, /^sha512-/, 'locked Wrangler integrity must begin with sha512-');
assert.ok(sharpLock, 'package-lock must contain node_modules/sharp');
assert.equal(sharpLock.version, '0.35.3', 'locked sharp version must be patched 0.35.3');
assert.equal(sharpLock.resolved, 'https://registry.npmjs.org/sharp/-/sharp-0.35.3.tgz', 'locked sharp resolved URL is incorrect');
assert.equal(typeof sharpLock.integrity, 'string', 'locked sharp integrity must be a string');
assert.match(sharpLock.integrity, /^sha512-/, 'locked sharp integrity must begin with sha512-');
NODE

ignore_source="$(git -C "$PROJECT_ROOT" check-ignore -v node_modules)"
if [[ "$ignore_source" != .gitignore:* ]]; then
  printf 'node_modules must be ignored by .gitignore, got: %s\n' "$ignore_source" >&2
  exit 1
fi

echo "release tooling contract tests passed"
