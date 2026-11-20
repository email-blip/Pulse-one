#!/usr/bin/env bash
# Usage: push-screenshots.sh <dir> <branch>  – force-pushes <dir> as a single orphan commit.
set -euo pipefail
dir="$1"; branch="$2"
[ -d "$dir" ] && [ -n "$(ls -A "$dir")" ] || { echo "nothing to push"; exit 0; }
cat > "$dir/index.md" <<MD
# Screenshots
- Source commit: ${GITHUB_SHA}
- Run: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}
- Created: $(date -u +%FT%TZ)

$(cd "$dir" && find . -name '*.png' | sort | sed 's/^/- /')
MD
cd "$dir"
git init -q -b "$branch"
git config user.name "ios-ci"; git config user.email "ios-ci@users.noreply.github.com"
git add -A && git commit -qm "screenshots for ${GITHUB_SHA}"
git push -qf "https://x-access-token:${GITHUB_TOKEN:?GITHUB_TOKEN required}@github.com/${GITHUB_REPOSITORY}.git" "HEAD:refs/heads/$branch"
echo "pushed to $branch"
