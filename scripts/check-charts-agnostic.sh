#!/usr/bin/env bash
# check-charts-agnostic.sh — fail when site-specific config leaks into chart
# defaults. Enforces docs/CHART_CONVENTIONS.md: chart values.yaml files carry
# app-generic config only; site identity (domains, TZ, cluster FQDNs, secret
# names) is consumer-supplied. Scope: charts/*/values.yaml only — READMEs may
# legitimately show site examples.
set -euo pipefail

cd "$(dirname "$0")/.."

RULE_NAMES=(
  "site-name    (references to this site's names/domains)"
  "cluster-fqdn (in-cluster service FQDNs)"
  "tz-key       (charts must omit TZ entirely; consumers set it)"
  "tz-value     (IANA Region/City timezone values)"
)
RULE_PATTERNS=(
  'boaboa'
  'svc[.]cluster[.]local'
  '^[[:space:]]*TZ:'
  '(Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific|Etc)/'
)

shopt -s nullglob
files=(charts/*/values.yaml)
if [ ${#files[@]} -eq 0 ]; then
  echo "check-charts-agnostic: no charts/*/values.yaml found" >&2
  exit 1
fi

fail=0
for f in "${files[@]}"; do
  for i in "${!RULE_PATTERNS[@]}"; do
    if matches=$(grep -nE "${RULE_PATTERNS[$i]}" "$f" || true); then
      if [ -n "$matches" ]; then
        echo "FAIL [${RULE_NAMES[$i]}] $f"
        printf '%s\n' "$matches" | sed 's/^/  /'
        fail=1
      fi
    fi
  done
done

if [ "$fail" -ne 0 ]; then
  echo "check-charts-agnostic: site-specific config found in chart defaults — move it to consumer values (docs/CHART_CONVENTIONS.md)" >&2
  exit 1
fi
echo "check-charts-agnostic: all ${#files[@]} chart(s) site-agnostic"
