#!/usr/bin/env bash
# Claude Code PreToolUse hook for Bash (.claude/settings.json). Keeps Claude from
# getting around akvavit/scripts/check-personal.sh:
#   - refuses --no-verify, `git commit -n` and changes to core.hooksPath;
#   - refuses git commits, merges, tags and pushes while the hooks are not installed;
#   - scans the text that gh would publish (PRs, issues, releases, gists, API calls);
#   - before the repository is made public, scans the whole history and asks the user.
# Exit 2 refuses the command and shows the message to Claude.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$ROOT/akvavit/scripts/check-personal.sh"
HOOKS=akvavit/githooks

input="$(cat)"
if command -v jq >/dev/null 2>&1; then
    cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
else
    cmd="$input"   # crude, but errs towards refusing
fi
[[ -z "$cmd" ]] && exit 0

deny() { printf 'Refused by .claude/hooks/guard-git.sh: %s\n' "$*" >&2; exit 2; }
ask() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$*"
    exit 0
}

# Regexes live in variables: bash 3.2 can't parse some of them inline in [[ =~ ]].
START='(^|[^[:alnum:]_./-])'
RE_GIT_SUB="${START}git(([[:space:]]+-[Cc])?[[:space:]]+[^[:space:]]+)*[[:space:]]+(commit|merge|tag|push|am|cherry-pick|rebase|revert)([[:space:]]|\$)"
RE_COMMIT_N="${START}git([[:space:]]+[^;&|]*)?[[:space:]]commit([[:space:]][^;&|]*)?[[:space:]]-[A-Za-z]*n[A-Za-z]*([[:space:]]|\$)"
RE_ENV_CONFIG='GIT_CONFIG_(PARAMETERS|COUNT|KEY_)'
RE_UNSET_HOOKS='--unset(-all)?[^;&|]*core\.hookspath'
RE_SET_HOOKS='core\.hookspath[[:space:]=]+([^[:space:];&|)]+)'
RE_GH_PUBLISH="${START}gh[[:space:]]+(pr|issue|release|gist|api|repo|discussion|label)([[:space:]]|\$)"
RE_GH_REPO='gh[[:space:]]+repo[[:space:]]+(edit|create)'
RE_PUBLIC='--visibility[=[:space:]]+public|--public'

if [[ "$cmd" == *--no-verify* ]]; then
    deny "--no-verify skips the privacy hooks. Fix what akvavit/scripts/check-personal.sh reports instead."
fi
if [[ "$cmd" =~ $RE_COMMIT_N ]]; then
    deny "'git commit -n' skips the privacy hooks."
fi
shopt -s nocasematch
if [[ "$cmd" =~ $RE_ENV_CONFIG ]]; then
    deny "setting git config through the environment could switch the hooks off."
fi
if [[ "$cmd" =~ $RE_UNSET_HOOKS ]]; then
    deny "core.hooksPath must stay $HOOKS."
fi
if [[ "$cmd" =~ $RE_SET_HOOKS && "${BASH_REMATCH[1]}" != "$HOOKS" ]]; then
    deny "core.hooksPath must stay $HOOKS."
fi
shopt -u nocasematch

if [[ "$cmd" =~ $RE_GIT_SUB ]]; then
    [[ "$(git -C "$ROOT" config core.hooksPath)" == "$HOOKS" ]] ||
        deny "the git hooks are not installed. Run akvavit/scripts/setup.sh first."
    [[ -x "$CHECK" ]] || deny "$CHECK is missing or not executable."
fi

# gh commands that publish text: scan what follows "gh", and any files they read.
if [[ "$cmd" =~ $RE_GH_PUBLISH ]]; then
    gh_part="gh ${cmd#*gh }"
    files=()
    while IFS= read -r f; do
        [[ -n "$f" ]] && files+=("${f/#\~/$HOME}")
    done < <(grep -oE -- '(--body-file|--notes-file|--input|-F)[= ]+@?[^[:space:]]+' <<<"$gh_part" |
             sed -E 's/^[^= ]+[= ]+@?//; s/^.*=@//; s/^["'\'']//; s/["'\'']$//')
    stripped="$(sed -E 's/(--body-file|--notes-file|--input|-F)[= ]+@?[^[:space:]]+//g' <<<"$gh_part")"
    if ! out="$("$CHECK" --text "gh command" <<<"$stripped" 2>&1)"; then
        deny "the gh command contains personal information:"$'\n'"$out"
    fi
    for f in ${files[@]+"${files[@]}"}; do
        [[ -f "$f" ]] || continue
        if ! out="$("$CHECK" --text "$(basename "$f")" <"$f" 2>&1)"; then
            deny "$(basename "$f") contains personal information:"$'\n'"$out"
        fi
    done
fi

# Making the repository public.
if [[ "$cmd" =~ $RE_GH_REPO && "$cmd" =~ $RE_PUBLIC ]]; then
    if ! out="$("$CHECK" --everything 2>&1)"; then
        deny "the history contains personal information, so the repository must not be made public:"$'\n'"$out"
    fi
    ask "This makes the GitHub repository public. check-personal.sh --everything passed on the local history. Confirm with the user first."
fi

exit 0
