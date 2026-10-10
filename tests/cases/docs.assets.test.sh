#!/usr/bin/env bash
# Case: the assets in assets/ are usable as shipped.
#
# These four files are what a consumer copies into their project, so a defect
# here is copied too. Two were already broken: coverage-config.xml told the
# reader to paste it "inside <PropertyGroup>" while its root element already
# was one, and the BDD template grouped its scenarios with plain comments
# (`# Smoke Scenarios`) instead of Gherkin tags, so no runner could select a
# tier from it.
#
# This case needs no shims: it reads files, it does not run the scaffolder.
set -uo pipefail

QA_TESTS_DIR="${QA_TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$QA_TESTS_DIR/.." && pwd)}"
# shellcheck source=../lib/assert.sh
. "$QA_TESTS_DIR/lib/assert.sh"

FEATURE="$REPO_ROOT/assets/bdd-feature-template.feature"
COVERAGE_XML="$REPO_ROOT/assets/coverage-config.xml"
SPEC_TEMPLATE="$REPO_ROOT/assets/ai-spec-template.md"
CHECKLIST="$REPO_ROOT/assets/pre-production-checklist.md"

# ===========================================================================
# The Gherkin template can be filtered by tier
# ===========================================================================

assert_file "$FEATURE" "assets/bdd-feature-template.feature exists"

TIERS="Smoke Regression Concurrency SecurityPR Security Property"

# 1. Every scenario carries a tier tag.
untagged="$(awk '
  /^[[:space:]]*@/ { tag = 1; next }
  /^[[:space:]]*(Scenario|Scenario Outline):/ { if (!tag) print NR": "$0; tag = 0; next }
  { if ($0 !~ /^[[:space:]]*($|#)/) tag = 0 }
' "$FEATURE")"
if [[ -z "$untagged" ]]; then
  _qa_pass "every scenario carries a tier tag"
else
  _qa_fail "every scenario carries a tier tag" "untagged scenarios:
$untagged"
fi

# 2. Only the known tier and category tags are used.
unknown_tags="$(grep -oE '^[[:space:]]*@[A-Za-z]+' "$FEATURE" | tr -d ' @' | sort -u |
  while IFS= read -r t; do
    printf ' %s ' "$TIERS" | grep -qF " $t " || echo "$t"
  done)"
if [[ -z "$unknown_tags" ]]; then
  _qa_pass "only the known tier and category tags are used"
else
  _qa_fail "only the known tier and category tags are used" "unknown tags: $unknown_tags"
fi

# 3. Every tier is actually used, and the header says how to select it.
for tier in $TIERS; do
  assert_contains "$(cat "$FEATURE")" "@$tier" "the template uses the @$tier tag"
done

feature_doc="$(cat "$FEATURE")"
assert_contains "$feature_doc" "Category=Smoke" "the template documents .NET tag selection"
assert_contains "$feature_doc" "cucumber-js --tags" "the template documents Cucumber.js tag selection"
assert_contains "$feature_doc" "behave --tags" "the template documents Behave tag selection"

# 4. The old comment-only grouping is gone: it looked like a tier marker but
#    nothing could filter on it.
assert_not_contains "$feature_doc" "# Smoke Scenarios —" \
  "the template no longer marks tiers with comments alone"

# ===========================================================================
# coverage-config.xml is well-formed and its instructions match its content
# ===========================================================================

assert_file "$COVERAGE_XML" "assets/coverage-config.xml exists"

if command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])' "$COVERAGE_XML" 2>/dev/null; then
    _qa_pass "coverage-config.xml is well-formed XML"
  else
    _qa_fail "coverage-config.xml is well-formed XML" "$(python3 -c 'import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])' "$COVERAGE_XML" 2>&1 | tail -2)"
  fi
else
  qa_skip "coverage-config.xml XML well-formedness: python3 is not available"
fi

root_element="$(grep -m1 -oE '^[[:space:]]*<[A-Za-z]+' "$COVERAGE_XML" | tr -d ' <')"
assert_eq "$root_element" "PropertyGroup" "the snippet's root element is <PropertyGroup>"
assert_not_contains "$(cat "$COVERAGE_XML")" "inside <PropertyGroup>" \
  "the instructions do not tell the reader to nest it inside a <PropertyGroup>"

# ===========================================================================
# The spec template covers the whole OWASP API Top 10
# ===========================================================================

assert_file "$SPEC_TEMPLATE" "assets/ai-spec-template.md exists"
spec_doc="$(cat "$SPEC_TEMPLATE")"
for n in 1 2 3 4 5 6 7 8 9 10; do
  assert_contains "$spec_doc" "- [ ] API$n:" "the spec template covers API$n"
done

# ===========================================================================
# The pre-production checklist covers the gates the pipeline declares
# ===========================================================================

assert_file "$CHECKLIST" "assets/pre-production-checklist.md exists"
checklist_doc="$(cat "$CHECKLIST")"
for section in "Performance" "Coverage" "Mutation" "Security"; do
  assert_contains "$checklist_doc" "$section" "the checklist has a $section section"
done

qa_summary
