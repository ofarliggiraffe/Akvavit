#!/usr/bin/env bash
# Prepares a checkout of Akvavit for building. Safe to re-run.
#
#   1. installs the git hooks (akvavit/scripts/check-personal.sh before commit, merge
#      and push), with fallbacks in .git/hooks;
#   2. adds Madeira as the remote "upstream", which the privacy check needs to tell
#      our commits from Madeira's, and fetches it;
#   3. checks out the submodules at their pinned commits;
#   4. writes the team ID and bundle IDs from local.config into
#      app/Signing.local.xcconfig (git-ignored), which app/Signing.xcconfig includes;
#   5. generates the Xcode project of Akvavit's own app (akvavit/Akvavit/project.yml);
#   6. checks everything of ours for personal information.
#
# Then run akvavit/scripts/build-native.sh, and build the "Akvavit" scheme
# (akvavit/Akvavit/Akvavit.xcodeproj) or the "Madeira" scheme (app/Madeira.xcodeproj) in Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS=akvavit/githooks
MADEIRA_URL=https://github.com/willfaust/madeira.git

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "$ROOT/local.config" ]] || die "Copy local.config.example to local.config and fill it in."
# shellcheck disable=SC1091
source "$ROOT/local.config"
[[ "${TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]] || die "local.config: TEAM_ID must be a 10-character Apple team ID."
[[ "${BUNDLE_ID:-}" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || die "local.config: BUNDLE_ID is not a bundle identifier."
APP_BUNDLE_ID="${APP_BUNDLE_ID:-$BUNDLE_ID.app}"
[[ "$APP_BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || die "local.config: APP_BUNDLE_ID is not a bundle identifier."

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

log "Writing app/Signing.local.xcconfig from local.config"
printf '%s\n' '// Written by akvavit/scripts/setup.sh from local.config. Git-ignored.' \
    "DEVELOPMENT_TEAM = $TEAM_ID" \
    "MADEIRA_BUNDLE_IDENTIFIER = $BUNDLE_ID" \
    "AKVAVIT_APP_BUNDLE_IDENTIFIER = $APP_BUNDLE_ID" >"$ROOT/app/Signing.local.xcconfig"

log "Generating akvavit/Akvavit/Akvavit.xcodeproj (Akvavit's own app) with XcodeGen"
if ! command -v xcodegen >/dev/null; then
    command -v brew >/dev/null || die "XcodeGen is needed for Akvavit's own app: install Homebrew, or XcodeGen from github.com/yonaskolb/XcodeGen."
    brew install xcodegen
fi
xcodegen generate --spec "$ROOT/akvavit/Akvavit/project.yml" --quiet

# Only needed for committing, so a build-only setup doesn't need PERSONAL_WORDS.
if [[ -n "${PERSONAL_WORDS:-}" ]]; then
    log "Checking our files and commits for personal information"
    "$ROOT/akvavit/scripts/check-personal.sh" --everything
else
    log "Skipping the privacy check: PERSONAL_WORDS in local.config is empty (commits need it)"
fi

log "Done. Next: akvavit/scripts/build-native.sh"
