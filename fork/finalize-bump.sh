#!/usr/bin/env bash
# Mac: bash fork/finalize-bump.sh <tag> [<branch>]; branch defaults to claude/bump-gemini-notebook-<tag> (first run: see fork/BUMP.md)
# Verifies the release and the branch, moves main to it, reinstalls through the lock, deletes the bump branch.
set -euo pipefail
# run from a copy: the script switches branches, and on the first run only the bump branch has it
if [ -z "${FB_REPO:-}" ]; then
  FB_REPO=$(git rev-parse --show-toplevel) && export FB_REPO && t=$(mktemp) && cp "$0" "$t" && exec bash "$t" "$@"
fi
cd "$FB_REPO"
tag=${1:?usage: finalize-bump.sh <tag> [<branch>]}; branch=${2:-claude/bump-gemini-notebook-$tag}
UP=jacob-bd/gemini-notebook-mcp-cli
[ -z "$(git status --porcelain)" ] || { echo "finalize: working tree not clean"; exit 1; }
git fetch -q origin "$branch"
git fetch -q "https://github.com/$UP.git" "refs/tags/$tag:refs/tags/$tag"
# release check (the cloud cannot reach the API): published, not a draft or prerelease, tag matches the fetched one
read -r draft pre <<<"$(gh release view "$tag" -R "$UP" --json isDraft,isPrerelease -q '"\(.isDraft) \(.isPrerelease)"')"
[ "$draft $pre" = "false false" ] || { echo "finalize: $tag is a draft or prerelease"; exit 1; }
[ "$(gh api "repos/$UP/commits/$tag" -q .sha)" = "$(git rev-parse "$tag^{commit}")" ] || { echo "finalize: tag SHA mismatch"; exit 1; }
git switch -q main && git merge --ff-only -q origin/main
git merge-base --is-ancestor "$tag" "origin/$branch" || { echo "finalize: branch lacks $tag"; exit 1; }
git merge-base --is-ancestor main "origin/$branch" || { echo "finalize: branch is not based on main"; exit 1; }
git switch -q --detach "origin/$branch"
bash fork/verify.sh
git switch -q main && git merge --ff-only -q "origin/$branch" && git push -q origin main
# install through the lock (CLAUDE.md); --require-build-hashes only where this uv has it
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
h=--require-build-hashes; uv tool install --help | grep -q -- "$h" || { h=; echo "finalize: uv lacks --require-build-hashes, installing without it"; }
uv export --frozen --no-dev --no-emit-project -o "$T/c.txt" -q
uv venv -q "$T/dry"
uv pip install --dry-run --python "$T/dry" . -c "$T/c.txt" --build-constraints build-constraints.txt $h
uv tool install . --force -c "$T/c.txt" --build-constraints build-constraints.txt $h
# only main stays
git push -q origin --delete "$branch" || true
# standing rule: only main stays on origin (other branches are reported if they hold unmerged commits)
git fetch -q --prune origin
for r in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin | grep -vE '^origin/(main|HEAD)$'); do
  git merge-base --is-ancestor "$r" main || { echo "finalize: keeping $r (unmerged commits)"; continue; }
  git push -q origin --delete "${r#origin/}"
done
git branch -D "$branch" 2>/dev/null || true
git tag -d "$tag" >/dev/null
echo "finalize: main is at $(git rev-parse --short HEAD), $tag installed"
