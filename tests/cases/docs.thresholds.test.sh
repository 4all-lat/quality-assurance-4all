#!/usr/bin/env bash
# Case: the documentation quotes one set of numbers.
#
# The same threshold is restated in SKILL.md, the checklist, the per-stack
# reference and README. Before this test existed, P95 was written as "< 2s" in
# one file and "< 2000ms" in three others, and the error-rate gate as "0% errors"
# in one place against "< 0.1%" everywhere else. Readers of a methodology
# package act on these numbers, so a divergence is a wrong instruction.
#
# references/quality-gates.md holds the canonical table and is the source; it is
# excluded from the scan. Everywhere else, a line that states one of these
# metrics must state the canonical value, in the canonical unit.
set -uo pipefail

QA_TESTS_DIR="${QA_TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$QA_TESTS_DIR/.." && pwd)}"
# shellcheck source=../lib/assert.sh
. "$QA_TESTS_DIR/lib/assert.sh"

SOURCE="$REPO_ROOT/references/quality-gates.md"

# --- the canonical table exists --------------------------------------------

assert_file "$SOURCE" "references/quality-gates.md exists"
source_doc="$(cat "$SOURCE")"
for metric in "Line coverage" "Mutation score" "P50 latency" "P95 latency" "P99 latency" \
              "Throughput" "Error rate" "Tier budget — Smoke" "Tier budget — Regression" \
              "Tier budget — Full"; do
  assert_contains "$source_doc" "| $metric |" "the canonical table lists $metric"
done

# --- the numbers everywhere else -------------------------------------------

DOC_FILES=()
while IFS= read -r f; do
  case "$f" in
    ./references/quality-gates.md) continue ;;
    ./tests/*) continue ;;
  esac
  DOC_FILES+=("$REPO_ROOT/${f#./}")
done < <(
  cd "$REPO_ROOT" &&
    find . -name '*.md' -not -path './.git/*' -not -path './.archify/*' \
      -not -path './node_modules/*' -not -path './test-results/*' | sort
)

assert_ne "${#DOC_FILES[@]}" "0" "there are documents to lint besides the source"

# check_metric <label-regex> <extract-units> <canonical-unit> <allowed-values> <label>
#
# Every number on a line that names the metric, in that metric's unit family,
# must be one of the allowed values AND written in the canonical unit. The
# extraction pattern is deliberately wider than the canonical unit, so a line
# that states P95 as "5s" is extracted and then rejected for its unit rather
# than being skipped for not looking like a millisecond value.
check_metric() {
  local label="$1" extract="$2" canonical="$3" allowed="$4" name="$5"
  local file line value num unit line_bad

  for file in "${DOC_FILES[@]}"; do
    while IFS= read -r line; do
      line_bad=0
      while IFS= read -r value; do
        [[ -n "$value" ]] || continue
        if [[ "$value" =~ ^([0-9]+(\.[0-9]+)?)[[:space:]]*(.+)$ ]]; then
          num="${BASH_REMATCH[1]}"
          unit="${BASH_REMATCH[3]}"
        else
          continue
        fi
        if ! printf '%s' "$unit" | grep -qE "^($canonical)$"; then
          line_bad=1
        elif ! printf ' %s ' "$allowed" | grep -qF " $num "; then
          line_bad=1
        fi
      done < <(printf '%s' "$line" | grep -oE "[0-9]+(\.[0-9]+)?[[:space:]]*($extract)" || true)
      if [[ "$line_bad" -eq 1 ]]; then
        _qa_fail "$name uses the canonical value" \
          "$(basename "$file"): $(printf '%s' "$line" | sed 's/^ *//')"
      fi
    done < <(grep -iE "$label" "$file" 2>/dev/null || true)
  done
}

check_metric 'P50 latency'  'ms|s'      'ms'    '500'        'P50 latency'
check_metric 'P95 latency'  'ms|s'      'ms'    '2000 5000'  'P95 latency'
check_metric 'P99 latency'  'ms|s'      'ms'    '10000'      'P99 latency'
check_metric 'throughput'   'req/s'     'req/s' '20'         'Throughput'
check_metric 'error rate'   '%'         '%'     '0.1 1'      'Error rate'
check_metric 'availability' '%'         '%'     '99.9 99.5'  'Availability'

# The two historical divergences, asserted directly so the intent survives any
# refactor of the scanner above.
all_docs="$(cat "${DOC_FILES[@]}")"
assert_not_contains "$all_docs" "P95 latency | < 2s" "no file writes P95 as seconds"
assert_not_contains "$all_docs" "0% errors" "no file writes the error-rate gate as 0%"

# --- the tier budgets ------------------------------------------------------

for budget in "30s" "5min" "15min"; do
  assert_contains "$source_doc" "$budget" "the canonical table states the $budget tier budget"
done

qa_summary
