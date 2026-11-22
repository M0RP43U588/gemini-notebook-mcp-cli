# Bump workflow (cloud preparation, Mac finalize)

Fork `gemini-notebook-mcp-cli`, upstream `jacob-bd/gemini-notebook-mcp-cli`. Branch `main` only; no tags are pushed.

## Cloud (never pushes main or tags)
1. `git remote add upstream https://github.com/jacob-bd/gemini-notebook-mcp-cli.git` (push URL `DISABLED`), `git fetch --unshallow origin`, `git fetch upstream --tags`.
2. Latest release: `git ls-remote --tags --refs upstream | sort -V` (the cloud cannot use the GitHub API; the Mac checks the release).
3. `git switch -c claude/bump-gemini-notebook-<tag>` and `git merge --no-ff <tag>`. On conflict keep the fork's `CLAUDE.md`; keep the update check removed.
4. Review `git diff <old>..<tag>` for: `pyproject.toml`/`uv.lock` (deps, sources, backend), auth/cookie code, new URL/host literals, `.github/`, `scripts/`, `desktop-extension/`, `setup*.py`, new MCP tools. Ask Delta keep/nuke per new tool or risky finding with decision cards. Nuke dead code.
5. Commits: merge `bump(gemini-notebook): <tag>`; fork changes `fork(gemini-notebook): <summary>`. No attribution trailers.
6. `bash fork/verify.sh` (lock, audit, wheel, ruff, tests; advisories only if listed in `fork/accepted-advisories.txt`). Push the branch.

## Mac (Claude Code Remote Control, outside the sandbox, in this checkout)
`git switch main && bash fork/finalize-bump.sh <tag> [<branch>]`
Checks the release and tag SHA with `gh`, verifies the branch, fast-forwards and pushes main, reinstalls through the lock, then deletes the bump branch and the local tag.
