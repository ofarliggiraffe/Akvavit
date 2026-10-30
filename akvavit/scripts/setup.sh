#!/usr/bin/env bash
# Prepares a checkout of Akvavit for building. Safe to re-run.
#
#   1. installs the git hooks (akvavit/scripts/check-personal.sh before commit, merge
#      and push), with fallbacks in .git/hooks;
#   2. adds Madeira as the remote "upstream", which the privacy check needs to tell
#      our commits from Madeira's, and fetches it;
#   3. checks out the submodules at their pinned commits;
#   4. checks everything of ours for personal information.
#
# Then run akvavit/scripts/build-native.sh, and build the "Madeira" scheme in Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS=akvavit/githooks
MADEIRA_URL=https://github.com/willfaust/madeira.git

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "$ROOT/local.config" ]] || die "Copy local.config.example to local.config and fill it in."
# shellcheck disable=SC1091
source "$ROOT/local.config"

log "Installing git hooks"
git -C "$ROOT" config core.hooksPath "$HOOKS"
chmod +x "$ROOT/$HOOKS"/* "$ROOT"/akvavit/scripts/*.sh "$ROOT"/.claude/hooks/*.sh
# Fallbacks in .git/hooks, so the hooks still run if core.hooksPath is ever unset.
HOOKS_DIR="$(cd "$ROOT" && cd "$(git rev-parse --git-common-dir)" && pwd)/hooks"
mkdir -p "$HOOKS_DIR"
for hook in "$ROOT/$HOOKS"/*; do
    name="$(basename "$hook")"
    printf '%s\n' '#!/usr/bin/env bash' \
        '# Written by akvavit/scripts/setup.sh: runs the tracked hook even without core.hooksPath.' \
        "exec \"\$(git rev-parse --show-toplevel)/$HOOKS/$name\" \"\$@\"" >"$HOOKS_DIR/$name"
    chmod +x "$HOOKS_DIR/$name"
done

log "Fetching Madeira (remote \"upstream\")"
if ! git -C "$ROOT" remote get-url upstream >/dev/null 2>&1; then
    git -C "$ROOT" remote add upstream "$MADEIRA_URL"
    # Madeira's tags under refs/remotes/upstream/tags, apart from ours.
    git -C "$ROOT" config --add remote.upstream.fetch '+refs/tags/*:refs/remotes/upstream/tags/*'
    git -C "$ROOT" config remote.upstream.tagOpt --no-tags
fi
git -C "$ROOT" fetch upstream

log "Checking out the submodules at their pinned commits"
git -C "$ROOT" submodule update --init --recursive

# Only needed for committing, so a build-only setup doesn't need PERSONAL_WORDS.
if [[ -n "${PERSONAL_WORDS:-}" ]]; then
    log "Checking our files and commits for personal information"
    "$ROOT/akvavit/scripts/check-personal.sh" --everything
else
    log "Skipping the privacy check: PERSONAL_WORDS in local.config is empty (commits need it)"
fi

log "Done. Next: akvavit/scripts/build-native.sh"
