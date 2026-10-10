#!/usr/bin/env bash
# Case: the draw.io diagram still describes the pipeline the documents describe.
#
# diagrams/README.md states the maintenance rule — "Si cambia un gate o una
# métrica en SKILL.md o en references/, actualiza la pestaña correspondiente del
# diagrama en el mismo cambio" — and nothing enforced it. The diagram is plain
# XML precisely so that this can be checked, and so that its diffs are readable.
#
# The assertions below are deliberately coarse: the diagram may phrase a gate in
# its own words, but it must not contradict the canonical table, and it must not
# keep a claim the documents have since retired.
set -uo pipefail

QA_TESTS_DIR="${QA_TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$QA_TESTS_DIR/.." && pwd)}"
# shellcheck source=../lib/assert.sh
. "$QA_TESTS_DIR/lib/assert.sh"

DRAWIO="$REPO_ROOT/diagrams/qa-pipeline-4all.drawio"

assert_file "$DRAWIO" "diagrams/qa-pipeline-4all.drawio exists"

doc="$(cat "$DRAWIO")"

# --- it is still a readable, single-file diagram ---------------------------

if command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])' "$DRAWIO" 2>/dev/null; then
    _qa_pass "the diagram is well-formed XML"
  else
    _qa_fail "the diagram is well-formed XML" \
      "$(python3 -c 'import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])' "$DRAWIO" 2>&1 | tail -2)"
  fi

  tabs="$(python3 - "$DRAWIO" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
print(len(root.findall("diagram")))
PY
)"
  assert_eq "$tabs" "11" "the diagram still has one tab per phase group"

  dups="$(python3 - "$DRAWIO" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
out = []
for d in root.findall("diagram"):
    pg = d.find("mxGraphModel")
    ids = [c.get("id") for c in pg.iter("mxCell")]
    out += [i for i in dict.fromkeys(ids) if ids.count(i) > 1 and i not in ("0", "1")]
print(" ".join(out))
PY
)"
  assert_eq "$dups" "" "no cell id is duplicated inside a tab"
else
  qa_skip "diagram XML checks: python3 is not available"
fi

# --- the diagram does not contradict the canonical thresholds --------------
#
# The canonical table (references/quality-gates.md) fixes the tier budgets at
# 30s / 5min / 15min. The diagram is prose, so it may write "~30 s", but the
# number must be the same one.

assert_match "$doc" "30 s" "the Smoke tier is stated as 30 s in the diagram"
assert_match "$doc" "5 min" "the Regression tier is stated as 5 min in the diagram"
assert_match "$doc" "15 min" "the Full tier is stated as 15 min in the diagram"

# --- the gates the pipeline added are reflected ----------------------------
#
# Each string below is a gate that a document declares and the diagram used to
# omit. They exist so the diagram cannot silently drift behind the pipeline.

for needle in \
  "abuse cases" \
  "STRIDE" \
  "Concurrencia e idempotencia" \
  "escaneos estáticos" \
  "--enforce-budget" \
  "SecurityPR"
do
  assert_contains "$doc" "$needle" "the diagram carries the gate: $needle"
done

# --- and it no longer repeats claims the documents retired ------------------

retired=(
  "Sin seguridad ni rendimiento"
  "Estos tests se ejecutan en el nivel &lt;b&gt;Full&lt;/b&gt; (nightly / pre-release), no en el nivel Smoke ni en cada PR"
)
for claim in "${retired[@]}"; do
  assert_not_contains "$doc" "$claim" "the diagram dropped the retired claim: $claim"
done

qa_summary
