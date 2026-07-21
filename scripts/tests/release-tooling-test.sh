#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

node - "$PROJECT_ROOT/package.json" "$PROJECT_ROOT/package-lock.json" <<'NODE'
const fs = require('node:fs');
const assert = require('node:assert/strict');

const packageJson = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const packageLock = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));

assert.equal(packageJson.private, true);
assert.equal(packageJson.devDependencies?.wrangler, '4.112.0');
assert.equal(packageLock.packages?.['']?.devDependencies?.wrangler, '4.112.0');
NODE

git -C "$PROJECT_ROOT" check-ignore -q node_modules

echo "release tooling contract tests passed"
