#!/usr/bin/env bash
# Case: every relative link in the documentation resolves.
#
# The docs cross-reference each other heavily ("see references/quality-gates.md"),
# and a renamed file leaves those pointers dangling with no other signal. A
# broken link in a methodology package is a wrong instruction.
set -uo pipefail

QA_TESTS_DIR="${QA_TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$QA_TESTS_DIR/.." && pwd)}"
# shellcheck source=../lib/assert.sh
. "$QA_TESTS_DIR/lib/assert.sh"

# --- collect the markdown files --------------------------------------------

MD_FILES=()
while IFS= read -r f; do
  MD_FILES+=("$f")
done < <(
  cd "$REPO_ROOT" &&
    find . -name '*.md' -not -path './.git/*' -not -path './.archify/*' \
      -not -path './node_modules/*' -not -path './test-results/*' | sort
)

assert_ne "${#MD_FILES[@]}" "0" "the repository contains markdown files"

checked=0
broken=0

for rel in "${MD_FILES[@]}"; do
  file="$REPO_ROOT/${rel#./}"
  dir="$(dirname "$file")"

  # Inline links and images: [text](target) / ![alt](target)
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    case "$target" in
      http://*|https://*|mailto:*|'#'*) continue ;;
    esac
    path="${target%%#*}"
    [[ -n "$path" ]] || continue
    case "$path" in
      *'<'*|*'>'*|*'*'*) continue ;;  # placeholder or glob, not a literal path
    esac
    checked=$((checked + 1))
    if [[ ! -e "$dir/$path" ]]; then
      broken=$((broken + 1))
      _qa_fail "link resolves: $rel -> $target" "no such path: $path"
    fi
  done < <(grep -oE '\]\([^)]+\)' "$file" 2>/dev/null | sed -e 's/^](//' -e 's/)$//')
done

assert_eq "$broken" "0" "no relative link is broken ($checked links checked)"
assert_ne "$checked" "0" "relative links were actually found"

# --- paths written in backticks -------------------------------------------
#
# Most cross-references in this repo are written as `references/foo.md` rather
# than as a markdown link, so they are invisible to the pass above. Only paths
# that clearly point inside this repository are checked; illustrative paths
# belonging to a user's project (./src/MyProject.Tests/...) are left alone.
INLINE_RE='`(references|assets|scripts|tests|diagrams)/[^`]+`'
inline_checked=0
inline_broken=0

for rel in "${MD_FILES[@]}"; do
  file="$REPO_ROOT/${rel#./}"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in
      *'<'*|*'>'*|*'*'*) continue ;;  # placeholder or glob, not a literal path
    esac
    inline_checked=$((inline_checked + 1))
    if [[ ! -e "$REPO_ROOT/$path" ]]; then
      inline_broken=$((inline_broken + 1))
      _qa_fail "path exists: $rel -> $path" "no such path in the repository"
    fi
  done < <(grep -ohE "$INLINE_RE" "$file" 2>/dev/null | sed -e 's/^`//' -e 's/`$//' | sort -u)
done

assert_eq "$inline_broken" "0" "every in-repo path named in backticks exists ($inline_checked checked)"

qa_summary
