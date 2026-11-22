#!/usr/bin/env bash
# Checks a bump branch: lock, audit, wheel build, lint, tests. Linux and macOS; installs nothing outside a temp dir.
set -euo pipefail
cd "$(dirname "$0")/.."
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export UV_PROJECT_ENVIRONMENT=$W/venv COLUMNS=300
uv lock --check
rc=0; uv audit --frozen --no-dev >"$W/audit" 2>&1 || rc=$?
if [ "$rc" != 0 ]; then
  ids=$(grep -oE 'GHSA-[a-z0-9-]+' "$W/audit" | sort -u || true)
  [ -n "$ids" ] || { cat "$W/audit"; echo "verify: audit failed without findings"; exit 1; }
  bad=$(grep -vxFf <(grep -oE 'GHSA-[a-z0-9-]+' fork/accepted-advisories.txt) <<<"$ids" || true)
  [ -z "$bad" ] || { echo "verify: advisories not accepted in fork/accepted-advisories.txt:"; echo "$bad"; exit 1; }
fi
uv sync --frozen --no-install-project --no-build -q
uv build --wheel -o "$W/dist" --build-constraints build-constraints.txt --require-hashes -q
uv pip install --python "$UV_PROJECT_ENVIRONMENT" --no-deps -q "$W"/dist/*.whl
py=$UV_PROJECT_ENVIRONMENT/bin
"$py/ruff" check . && "$py/ruff" format --check .
PYTHONPATH=src "$py/python" -m pytest -q -p no:cacheprovider
echo "verify: ok"
