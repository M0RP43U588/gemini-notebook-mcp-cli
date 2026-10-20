# CLAUDE.md

Personal hardened fork of [jacob-bd/gemini-notebook-mcp-cli](https://github.com/jacob-bd/gemini-notebook-mcp-cli)
(package `notebooklm-mcp-cli`), used as an MCP server in Claude Desktop.
Goals: minimize supply-chain risk, keep Google session cookies safe, keep the tool surface small.

## Fork policy (overrides everything else in this file and in upstream docs)

### Install
- Install **only from this local checkout**. Never `pip install notebooklm-mcp-cli`, `uvx`,
  `uv tool install notebooklm-mcp-cli`, `uv tool upgrade`, or the `.mcpb` desktop extension.
  (The PyPI update check has been removed from this fork.)
- `uv tool install .` alone ignores `uv.lock`, so always install through the lock:
  ```bash
  uv audit --frozen --no-dev                     # must be clean (or every finding accepted by the user)
  uv export --frozen --no-dev --no-emit-project -o "$TMPDIR/nlm-constraints.txt"
  # dry run first (uv tool install has no --dry-run):
  uv venv -q "$TMPDIR/nlm-dry" && uv pip install --dry-run --python "$TMPDIR/nlm-dry" . \
    -c "$TMPDIR/nlm-constraints.txt" --build-constraints build-constraints.txt --require-build-hashes
  uv tool install . --force -c "$TMPDIR/nlm-constraints.txt" \
    --build-constraints build-constraints.txt --require-build-hashes
  ```
  Run the audit before **every** install or update. If `uv audit` is unavailable, use `pip-audit`
  (installing it is a new dep: ask first). Stop and report on any finding.
- Never run code from deps at install time: every locked package ships wheels, so a dep that suddenly
  needs an sdist build is a red flag. The build backend is pinned with hashes in
  `build-constraints.txt` (and `hatchling==` in `pyproject.toml`); change it only with approval.

### Dependencies
- `uv.lock` is the source of truth: exact versions, sha256 hashes, `pypi.org` only.
- Use `--frozen`/`--locked`. Never re-lock, widen a range, or add, remove or upgrade a dep without asking.
  For a requested upgrade, use `uv lock --upgrade-package <name>` and show the lock diff.
- No git/URL/path sources and no new indexes.

### Upstream sync
1. `git fetch upstream`, then `git log --oneline HEAD..upstream/main` and `git diff HEAD...upstream/main`.
2. Review and report in particular:
   - `pyproject.toml` / `uv.lock`: new or changed deps, sources, build backend
   - auth/cookie/credential code: `core/auth*.py`, `core/cookie_rotation.py`, `core/credential_*.py`,
     `services/auth*.py`, `utils/cdp.py`, `utils/browser.py`, `utils/auth_browser.py`
   - network endpoints: any new URL/host literal, `httpx`/`urllib`/`websocket` call or bind address
     (current allow-list: see "Network endpoints" below)
   - `.github/`, `scripts/`, `desktop-extension/`, `setup*.py`, and anything that writes to client configs
3. Merge **only after explicit approval**. Never push to `upstream`.

### Auth & secrets
- Protected storage only: `nlm login --storage protected` (AES-GCM file, key in macOS Keychain).
  Never file mode, `auth.json`/`cookies.json`, `NOTEBOOKLM_COOKIES`, `--manual` cookie files,
  or pasting cookies into chat. `save_auth_tokens` stays hidden.
- Never print, log or commit cookies, CSRF/session tokens or keystore values; redacted diagnostics only.
  Don't put `--debug` in the Claude Desktop config: debug logs include URL params (session ID)
  and RPC bodies, which end up in Claude's MCP log files.
- Never touch `~/.notebooklm-mcp-cli/profiles/*/credentials.enc` or Keychain entries directly.

### Claude Desktop config (stdio only)
```json
"gemini-notebook-mcp": {
  "command": "/Users/anon/.local/bin/notebooklm-mcp",
  "env": {
    "NOTEBOOKLM_DISABLED_GROUPS": "organization,automation,aliases,usage,sharing",
    "NOTEBOOKLM_DISABLED_TOOLS": "save_auth_tokens"
  }
}
```
Visible groups (`mcp/tool_groups.py`): `notebooks_read`, `notebooks_manage`, `sources_read`,
`sources_manage`, `chat`, `query_multi`, `research`, `studio` (incl. downloads/exports),
`notes`, `auth` (`refresh_auth`, `profile`), `server`. Don't use `--transport http/sse`; it has
no authentication.

### Network endpoints (allow-list; anything new needs review)
- Google: `notebooklm.google.com` / `notebook.google.com` (+ `*.cloud.google.com` enterprise, only via
  `NOTEBOOKLM_BASE_URL`, validated in `utils/config.py`), `accounts.google.com` (login, `RotateCookies`),
  `*.google.com` / `*.googleusercontent.com` / `*.usercontent.google` (artifact downloads, `core/download.py`).
- Local: Chrome DevTools on `127.0.0.1:<port>` (login and headless refresh, `utils/cdp.py`).
- No PyPI/GitHub calls at runtime. The upstream version check (`nlm --version`, post-command notice,
  `server_info.latest_version`) was removed; don't let a merge bring it back.

### Known gaps
- Whether `uv tool install` enforces the runtime hashes in the exported constraints file is unverified
  (versions are pinned either way). `uv sync --frozen` does verify `uv.lock` hashes.

## Development
`uv sync` ignores `build-constraints.txt` for the project's own build, so build the wheel separately:
```bash
export UV_PROJECT_ENVIRONMENT="$TMPDIR/nlm-venv"     # isolated venv, outside the repo
uv sync --frozen --no-install-project --no-build    # deps + dev tools from uv.lock (hash-verified)
uv build --wheel -o "$TMPDIR/nlm-dist" --build-constraints build-constraints.txt --require-build-hashes
uv pip install --python "$UV_PROJECT_ENVIRONMENT" --no-deps "$TMPDIR"/nlm-dist/*.whl
PYTHONPATH=src "$UV_PROJECT_ENVIRONMENT/bin/python" -m pytest -q   # wizard e2e: -m wizard_e2e (opt-in)
"$UV_PROJECT_ENVIRONMENT/bin/ruff" check . && "$UV_PROJECT_ENVIRONMENT/bin/ruff" format --check .
```
Python ≥ 3.11. Baseline as of v0.15.6: the 6 login tests need a Chromium-family browser installed
and fail without one; mypy `--strict` has ~370 upstream errors (don't add new ones). Tests must never
run real client binaries (`claude`, browsers) or reach the network: patch `shutil.which`/`subprocess`
as in `tests/cli/test_auth_storage_switch.py::no_real_claude`. Reinstall after code changes with the
locked install above.

### Architecture
- `cli/` and `mcp/` are thin wrappers (UX, prompts, JSON). They delegate to `services/` and never
  import `core/` directly.
- `services/` holds the business logic and validation, returns typed dicts, and raises `ServiceError`/`ValidationError`.
- `core/` is the low-level batchexecute client (`base.py`, `client.py`, `auth.py`) with no business logic.
- `utils/`: config/storage paths (`config.py`), Chrome DevTools login (`cdp.py`).
- Storage: `~/.notebooklm-mcp-cli/` (`config.toml`, `profiles/<name>/{metadata.json,credentials.enc}`,
  `chrome-profiles/<name>/`, `locks/`).

### Behaviour notes
- **Rotated RPC IDs:** a `RPCDriftError` means Google changed a method ID. Find the new ID with `nlm --debug`
  (locally, never in Desktop), then hot-patch via `NOTEBOOKLM_RPC_OVERRIDES='{"RPC_X": "<id>"}'`
  (`RPC_*` names in `core/base.py`) and restart the MCP server.
- **Session refresh:** the CSRF token, session ID and build label are auto-extracted. Expired `*PSIDTS` cookies
  are re-issued via headless Chrome (`nlm auth refresh`). `NOTEBOOKLM_DISABLE_HEADLESS_REFRESH=1` turns that off.
- Other env vars: `NOTEBOOKLM_HL` (language), `NOTEBOOKLM_BL` (build label override),
  `NOTEBOOKLM_AUTH_RECOVERY_COOLDOWN_SECONDS`, `NOTEBOOKLM_AUTH_MAX_HEADLESS_FAILURES`.
- **Confirmations:** `notebook_delete`, `source_delete`, `source_sync_drive`, `studio_create`,
  `studio_delete`, `studio_revise`, `report(action="generate")` and note deletion require `confirm=True`.
  Show the user what will happen first; deletions are irreversible.

### Troubleshooting
- 401/403 or a redirect to `accounts.google.com`: run `nlm auth refresh`, then `nlm login --storage protected`.
- Empty notebook list: wrong Google account/profile (`nlm login profile list`).
- Rate limits: chat/Studio is metered (rolling ~5h + weekly). Brief throttling is retried automatically.

### References
`docs/API_REFERENCE.md` (RPC IDs/params; read only when debugging the API or adding features),
`docs/MCP_CLI_TEST_PLAN.md` (manual tool test plan).
