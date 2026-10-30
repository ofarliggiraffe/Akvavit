#!/usr/bin/env bash
# Stops personal information from entering the repository or reaching GitHub.
#
#   akvavit/scripts/check-personal.sh --staged          the index, before `git commit` records it
#   akvavit/scripts/check-personal.sh --message <file>  a commit message (commit-msg hook)
#   akvavit/scripts/check-personal.sh --commits <range> commits about to be pushed: every file
#                                                       they add or change, messages, author,
#                                                       committer
#   akvavit/scripts/check-personal.sh --tag <object>    an annotated tag: tagger and message
#   akvavit/scripts/check-personal.sh --all             every file in HEAD that differs from Madeira
#   akvavit/scripts/check-personal.sh --everything      --all, plus every commit and tag of ours on
#                                                       every branch, tag and remote ref (CI, and
#                                                       before publishing)
#   akvavit/scripts/check-personal.sh --text <label>    text on stdin (PR and issue bodies)
#
# Akvavit is a fork of Madeira, so only what we add on top of Madeira is checked:
#   - commits: those not in Madeira's history (refs/remotes/upstream/*);
#   - files that Madeira also has: only findings that Madeira's version of the file
#     (at the merge base) doesn't contain already, binary files included;
#   - an exact copy of one of Madeira's files under a new name: only the name;
#   - files that only we have: the whole file.
# Madeira's own history has its authors' real email addresses, and its project file
# its team ID; they are Madeira's to publish, not ours.
#
# It refuses:
#   - files that must never be tracked: local.config, signing material, crash logs,
#     Xcode user data, build output, Wine prefixes, Steam login data;
#   - changed copies of Madeira's binary files in a commit (local builds rewrite them,
#     with build paths inside); AKVAVIT_ALLOW_BINARY=1 allows one on purpose;
#   - generic patterns: device UDIDs, home directory paths (macOS, Linux, Wine), real
#     email addresses (GitHub noreply, noreply@anthropic.com and example.com are
#     allowed), Xcode team IDs, "<name>'s iPhone" device and host names, private keys
#     and access tokens;
#   - the values in local.config (git-ignored): TEAM_ID, BUNDLE_ID and its prefix,
#     DEVICE_UDID with and without its hyphen, and PERSONAL_WORDS, in any case;
#   - commit authors, committers and taggers without a GitHub noreply address.
# NUL bytes are removed before scanning, which also makes UTF-16 text readable.
#
# local.config is required, except in CI, which runs the generic checks alone (with a
# warning) unless a PERSONAL_CONFIG secret holds the same values. In CI, findings name
# the place and the rule but never the matched text, because the Actions logs of a
# public repository are public.
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Madeira's branch that Akvavit is based on (akvavit/scripts/setup.sh adds the remote).
UPSTREAM="${AKVAVIT_UPSTREAM:-upstream/main}"

# Paths that must never be tracked, whatever they contain.
FORBIDDEN_PATHS=(
    '(^|/)local\.config$'
    '(^|/)CLAUDE\.local\.md$'
    '(^|/)Signing\.local\.xcconfig$'
    '(^|/)\.claude/settings\.local\.json$'
    '(^|/)\.DS_Store$'
    '(^|/)xcuserdata/'
    '\.xcuserstate$'
    '(^|/)(\.build|build-logs|DerivedData)/'
    '\.(mobileprovision|provisionprofile|p12|pfx|cer|p8|pem|key|keychain-db)$'
    '\.(ips|crash|ipa)$'
    '\.(xcarchive|dSYM)/'
    '(^|/)drive_c/'
    '(^|/)(loginusers|config)\.vdf$'
    '(^|/)ssfn[0-9]+$'
)

# Generic rules: a name, an extended regex, and a regex for matches that are fine.
RULE_NAMES=() RULE_PATTERNS=() RULE_ALLOW=()
rule() { RULE_NAMES+=("$1"); RULE_PATTERNS+=("$2"); RULE_ALLOW+=("${3:-}"); }
rule "device UDID"          '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}'
rule "macOS home directory" '/Users/[A-Za-z0-9._-]+' '^/Users/Shared$'
rule "Linux home directory" '/home/[A-Za-z0-9._-]+'
rule "Windows user folder"  '([A-Za-z]:\\+|drive_c/)[Uu]sers[\\/]+[A-Za-z0-9._-]+' \
                            '[\\/](madeira|mobile|steamuser|public|default|name)$'
rule "email address"        '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
                            '(@users\.noreply\.github\.com|^noreply@anthropic\.com|^git@github\.com|@example\.(com|org|net))$'
rule "Xcode team ID"        'DEVELOPMENT_TEAM["[:space:]]*[=:][[:space:]"]*[A-Z0-9]{10}' 'XXXXXXXXXX$'
rule "team ID prefix"       '(^|[^A-Za-z0-9])[A-Z0-9]{10}\.(com|org|net|io|dev|app|me)\.[A-Za-z0-9-]+' 'XXXXXXXXXX\.'
rule "device name"          "[A-Za-z]+('|’)s (iPhone|iPad|MacBook|iMac|Mac|Apple Watch)" \
                            "^(user|owner|tester|developer|someone|person|player|everyone|Apple|Madeira)('|’)s"
rule "host name"            '[A-Za-z]+s-(iPhone|iPad|MacBook|iMac|Mac-mini|Mac-Studio|Mac-Pro)'
rule "private key"          '-----BEGIN ([A-Z]+ )*PRIVATE KEY-----'
rule "GitHub token"         '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{50,}'
rule "JSON web token"       'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+'

failures=0
report() { printf 'check-personal: %s\n' "$*" >&2; failures=$((failures + 1)); }
die() { printf 'check-personal: %s\n' "$*" >&2; exit 1; }

need_upstream() {
    git rev-parse -q --verify "$UPSTREAM^{commit}" >/dev/null ||
        die "Madeira's $UPSTREAM is missing, so what is ours can't be told apart. Run akvavit/scripts/setup.sh, or: git remote add upstream https://github.com/willfaust/madeira.git && git fetch upstream"
}
# The newest Madeira commit that $1 contains.
upstream_base() { git merge-base "$1" "$UPSTREAM"; }

# Values from local.config (or the PERSONAL_CONFIG secret in CI), with the key each
# came from.
PERSONAL_KEYS=() PERSONAL_VALUES=()
personal() {
    [[ ${#2} -ge 3 && "$2" != XXXXXXXXXX && "$2" != com.example* ]] || return 0
    PERSONAL_KEYS+=("$1"); PERSONAL_VALUES+=("$2")
}
load_personal() {
    local cfg
    if [[ -f local.config ]]; then
        cfg=local.config
    elif [[ -n "${PERSONAL_CONFIG:-}" ]]; then
        cfg="$(mktemp)"
        printf '%s\n' "$PERSONAL_CONFIG" >"$cfg"
    elif [[ -n "${CI:-}" ]]; then
        echo "::warning::PERSONAL_CONFIG secret not set: only the generic privacy checks run."
        return 0
    else
        die "local.config is missing, so the values in it can't be checked. Copy local.config.example to local.config and fill it in."
    fi
    TEAM_ID="" BUNDLE_ID="" DEVICE_UDID="" PERSONAL_WORDS=""
    # shellcheck disable=SC1090
    source "$cfg"
    [[ "$cfg" == local.config ]] || rm -f "$cfg"
    [[ -n "$PERSONAL_WORDS" ]] || die "PERSONAL_WORDS in local.config is empty: list your name, username and email address."
    personal TEAM_ID "$TEAM_ID"
    personal BUNDLE_ID "$BUNDLE_ID"
    [[ "$BUNDLE_ID" == *.*.* ]] && personal "BUNDLE_ID prefix" "${BUNDLE_ID%.*}"
    personal DEVICE_UDID "$DEVICE_UDID"
    personal DEVICE_UDID "${DEVICE_UDID//-/}"
    local w
    for w in $PERSONAL_WORDS; do personal PERSONAL_WORDS "$w"; done
}

# macOS's bash 3.2 has crashed in fork() after holding whole files in variables, so
# scan() keeps the text in temporary files that grep reads.
SCAN_FILE="$(mktemp)" BASE_FILE="$(mktemp)" BASE_BLOBS="$(mktemp)" BASE_BLOBS_OF=""
trap 'rm -f "$SCAN_FILE" "$BASE_FILE" "$BASE_BLOBS"' EXIT

# Scans text on stdin; $1 names where it came from. With $2 = base, a finding is
# reported only when BASE_FILE (Madeira's version of the same file) doesn't contain it.
scan() {
    local where="$1" with_base="${2:-}" i h line match allow
    tr -d '\000' >"$SCAN_FILE"
    [[ -s "$SCAN_FILE" ]] || return 0
    for i in "${!RULE_NAMES[@]}"; do
        allow="${RULE_ALLOW[$i]}"
        while IFS= read -r h; do
            [[ -z "$h" ]] && continue
            line="${h%%:*}" match="${h#*:}"
            if [[ -n "$allow" ]] && printf '%s\n' "$match" | grep -qiE -- "$allow"; then continue; fi
            if [[ -n "$with_base" ]] && grep -qaF -- "$match" "$BASE_FILE"; then continue; fi
            if [[ -n "${CI:-}" ]]; then
                report "$where: line $line: ${RULE_NAMES[$i]}"
            else
                report "$where: line $line: ${RULE_NAMES[$i]}: $match"
            fi
        done < <(grep -anEo -- "${RULE_PATTERNS[$i]}" "$SCAN_FILE" || true)
    done
    for i in ${PERSONAL_VALUES[@]+"${!PERSONAL_VALUES[@]}"}; do
        if [[ -n "$with_base" ]] && grep -qaiF -- "${PERSONAL_VALUES[$i]}" "$BASE_FILE"; then continue; fi
        line="$(grep -naiF -- "${PERSONAL_VALUES[$i]}" "$SCAN_FILE" | cut -d: -f1 | head -5 | paste -sd, - || true)"
        if [[ -n "$line" ]]; then
            report "$where: line $line: contains a value from local.config (${PERSONAL_KEYS[$i]})"
        fi
    done
    return 0
}

FORBIDDEN_RE="$(IFS='|'; echo "${FORBIDDEN_PATHS[*]}")"
check_path() {
    if printf '%s\n' "$1" | grep -qE -- "$FORBIDDEN_RE"; then
        report "'$1' must never be committed"
    fi
    printf '%s\n' "$1" | scan "file name '$1'"
}

# $1 describes who, $2 is "Name <email>".
check_ident() {
    local who="$1" ident="$2"
    case "$ident" in
      *@users.noreply.github.com\>) ;;
      *) report "$who email is not a GitHub noreply address (git config user.email)" ;;
    esac
    printf '%s\n' "$ident" | scan "$who"
}

# Whether blob $1 is one of Madeira's files at commit $2 (a copy or a renamed file).
madeira_blob() {
    if [[ "$BASE_BLOBS_OF" != "$2" ]]; then
        git ls-tree -r "$2" | awk '{print $3}' | sort -u >"$BASE_BLOBS"
        BASE_BLOBS_OF="$2"
    fi
    grep -qxF -- "$1" "$BASE_BLOBS"
}

# Scans the new blob $3 of path $2; $1 labels the findings, $4 is the Madeira commit
# to compare with.
check_blob() {
    local label="$1" path="$2" sha="$3" base="$4"
    if madeira_blob "$sha" "$base"; then
        check_path "$path"
    elif git cat-file -e "$base:$path" 2>/dev/null; then
        git cat-file blob "$base:$path" | tr -d '\000' >"$BASE_FILE"
        scan "$label$path" base < <(git cat-file blob "$sha")
    else
        check_path "$path"
        scan "$label$path" < <(git cat-file blob "$sha")
    fi
}

# Scans every file that a `git ... --raw -z --no-renames` diff adds or changes, by its
# new blob. $1 labels the findings, $2 is the Madeira commit to compare with; the rest
# is the git command.
scan_changes() {
    local label="$1" base="$2" meta path mode sha fields
    shift 2
    while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
        # meta is ":<old mode> <new mode> <old sha> <new sha> <status>"
        fields=($meta)
        mode="${fields[1]}" sha="${fields[3]}"
        [[ "$mode" == 160000 ]] && continue   # submodule pointer
        check_blob "$label" "$path" "$sha" "$base"
    done < <(git "$@")
}

check_commit() {
    local c="$1" short="${1:0:9}" an ae cn ce
    { IFS= read -r an; IFS= read -r ae; IFS= read -r cn; IFS= read -r ce; } \
        < <(git log -1 --format='%an%n%ae%n%cn%n%ce' "$c")
    check_ident "commit $short author" "$an <$ae>"
    check_ident "commit $short committer" "$cn <$ce>"
    scan "commit $short message" < <(git log -1 --format=%B "$c")
    # -m: a merge is compared with each parent, so nothing it brings in is skipped;
    # what a merge brings in from Madeira is in Madeira's version too.
    scan_changes "commit $short: " "$(upstream_base "$c")" diff-tree -r -m --root \
        --no-commit-id --raw -z --no-renames --no-abbrev --diff-filter=ACMRT "$c"
}

check_tag() {
    local t="$1" short="${1:0:9}"
    check_ident "tag $short tagger" "$(git cat-file -p "$t" | sed -n 's/^tagger \(.*>\).*/\1/p')"
    scan "tag $short" < <(git cat-file -p "$t")
}

# Changed copies of Madeira's binary files in the index.
check_staged_binaries() {
    local added deleted path
    [[ "${AKVAVIT_ALLOW_BINARY:-}" == 1 ]] && return 0
    while IFS=$'\t' read -r -d '' added deleted path; do
        [[ "$added" == - && "$deleted" == - ]] || continue
        git cat-file -e "$1:$path" 2>/dev/null || continue
        report "'$path' is Madeira's binary file, changed (a local build output?). Restore it with: git restore --staged --worktree '$path'"
    done < <(git diff --cached --numstat -z --no-renames --diff-filter=M)
}

mode="${1:-}"
case "$mode" in
  --staged|--message|--commits|--tag|--all|--everything|--text) load_personal ;;
esac
case "$mode" in
  --staged|--commits|--all|--everything) need_upstream ;;
esac

case "$mode" in
  --staged)
    if git rev-parse -q --verify HEAD >/dev/null; then base="$(upstream_base HEAD)"; else base="$UPSTREAM"; fi
    check_staged_binaries "$base"
    scan_changes "staged " "$base" diff --cached --raw -z --no-renames --no-abbrev --diff-filter=ACMRT
    check_ident author "$(git var GIT_AUTHOR_IDENT | sed 's/>.*/>/')"
    check_ident committer "$(git var GIT_COMMITTER_IDENT | sed 's/>.*/>/')"
    ;;
  --message)
    scan "commit message" < <(grep -v '^#' "${2:?usage: check-personal.sh --message <file>}" || true)
    ;;
  --commits)
    range="${2:?usage: check-personal.sh --commits <range>}"
    # The range may be several rev-list arguments ("<sha> --not --remotes").
    # shellcheck disable=SC2086
    for c in $(git rev-list $range --not "$UPSTREAM" --remotes=upstream); do check_commit "$c"; done
    ;;
  --tag)
    check_tag "${2:?usage: check-personal.sh --tag <object>}"
    ;;
  --all|--everything)
    base="$(upstream_base HEAD)"
    scan_changes "" "$base" diff-tree -r --raw -z --no-renames --no-abbrev --diff-filter=ACMRT "$base" HEAD
    if [[ "$mode" == --everything ]]; then
        for c in $(git rev-list --branches --tags --remotes --not "$UPSTREAM" --remotes=upstream); do
            check_commit "$c"
        done
        # Annotated tags of ours; Madeira's own tags point into Madeira's history.
        while read -r obj type; do
            [[ "$type" == tag ]] || continue
            [[ -n "$(git rev-list -1 "$obj^{commit}" --not "$UPSTREAM" --remotes=upstream)" ]] || continue
            check_tag "$obj"
        done < <(git for-each-ref --format='%(objectname) %(objecttype)' refs/tags)
    fi
    ;;
  --text)
    scan "${2:-text}"
    ;;
  *)
    echo "usage: $0 --staged | --message <file> | --commits <range> | --tag <object> | --all | --everything | --text <label>" >&2
    exit 2
    ;;
esac

if ((failures)); then
    echo "check-personal: $failures problem(s) found; nothing personal may enter this repository." >&2
    exit 1
fi
