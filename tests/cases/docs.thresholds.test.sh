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

# --- the static-analysis gate is the canonical table, applied ---------------
#
# The SonarQube quality gate is a copy of the numeric rows above, kept as an
# artifact so this can be checked at all. A gate that drifted from the table
# would enforce different numbers than the documents promise, and the two would
# look equally authoritative — which is exactly the failure this whole file
# exists to prevent. The gate is the copy, so the table is what has to be
# satisfied first.

GATE="$REPO_ROOT/assets/sonar-quality-gate.json"
assert_file "$GATE" "assets/sonar-quality-gate.json exists"
gate="$(cat "$GATE")"

assert_contains "$source_doc" "New-code coverage | \`>= 80%\`" \
  "the canonical table states new-code coverage at 80%"
assert_contains "$gate" '"metric": "coverage"' "the gate conditions on coverage"
assert_contains "$gate" '"error": "80"' "the gate holds coverage at the canonical 80%"

assert_contains "$source_doc" "Duplicated lines on new code | \`<= 3%\`" \
  "the canonical table states duplication at 3% on new code"
assert_contains "$gate" '"metric": "duplicated_lines_density"' "the gate conditions on duplication"
assert_contains "$gate" '"error": "3"' "the gate holds duplication at the canonical 3%"

assert_contains "$source_doc" "Security hotspots reviewed | \`100%\`" \
  "the canonical table states hotspots reviewed at 100%"
assert_contains "$gate" '"metric": "security_hotspots_reviewed"' "the gate conditions on hotspots reviewed"

assert_contains "$source_doc" "Ratings on new code" "the canonical table states the ratings gate"
for rating in new_maintainability_rating new_reliability_rating new_security_rating; do
  assert_contains "$gate" "$rating" "the gate conditions on $rating"
done

# The gate names the table it copies, so whoever finds the gate first is sent
# back to the source rather than trusting the copy.
assert_contains "$gate" "references/quality-gates.md" "the gate records the table it copies"

# --- the tier budgets ------------------------------------------------------

for budget in "30s" "5min" "15min"; do
  assert_contains "$source_doc" "$budget" "the canonical table states the $budget tier budget"
done

qa_summary
