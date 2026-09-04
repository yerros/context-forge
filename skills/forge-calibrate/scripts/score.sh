#!/usr/bin/env bash
# score.sh — forge-calibrate scorer: recall and run-to-run agreement of a reviewer.
#
#   score.sh <dir>     # <dir>/expected.txt + <dir>/run-*.txt (one finding key per line)
#
# Prints per-run recall, mean recall, mean pairwise Jaccard (agreement), the keys
# never found (blind spots) and the keys found only sometimes (unstable). Lines
# starting with # and blank lines are ignored; keys are trimmed.
# Exit 0 always — the numbers are the verdict, the skill decides what to do.

set -eu
dir=${1:-}
[ -n "$dir" ] && [ -f "$dir/expected.txt" ] || { echo "usage: score.sh <dir with expected.txt + run-*.txt>" >&2; exit 2; }

norm() { sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' | sort -u; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
norm "$dir/expected.txt" > "$tmp/expected"
n_exp=$(wc -l < "$tmp/expected" | tr -d ' ')
[ "$n_exp" -gt 0 ] || { echo "score: expected.txt is empty" >&2; exit 2; }

runs=()
for r in "$dir"/run-*.txt; do
  [ -f "$r" ] || continue
  name=$(basename "$r" .txt); norm "$r" > "$tmp/$name"; runs+=("$name")
done
[ ${#runs[@]} -gt 0 ] || { echo "score: no run-*.txt in $dir" >&2; exit 2; }

echo "expected: $n_exp keys · runs: ${#runs[@]}"
sum=0
for r in "${runs[@]}"; do
  found=$(comm -12 "$tmp/expected" "$tmp/$r" | wc -l | tr -d ' ')
  extra=$(comm -13 "$tmp/expected" "$tmp/$r" | wc -l | tr -d ' ')
  pct=$((found * 100 / n_exp)); sum=$((sum + pct))
  echo "$r: recall $found/$n_exp ($pct%) · extra $extra"
done
echo "mean recall: $((sum / ${#runs[@]}))%"

if [ ${#runs[@]} -ge 2 ]; then
  jsum=0; pairs=0
  for ((i=0; i<${#runs[@]}; i++)); do
    for ((j=i+1; j<${#runs[@]}; j++)); do
      a="$tmp/${runs[$i]}"; b="$tmp/${runs[$j]}"
      inter=$(comm -12 "$a" "$b" | wc -l | tr -d ' ')
      union=$(sort -u "$a" "$b" | wc -l | tr -d ' ')
      [ "$union" -gt 0 ] && jsum=$((jsum + inter * 100 / union)) || jsum=$((jsum + 100))
      pairs=$((pairs + 1))
    done
  done
  echo "agreement (mean pairwise Jaccard): $((jsum / pairs))%"
fi

cat "$tmp"/run-* | sort | uniq -c | awk -v n="${#runs[@]}" '{c=$1; $1=""; sub(/^ /,""); print c"\t"$0}' > "$tmp/counts"
never=$(comm -23 "$tmp/expected" <(cut -f2 "$tmp/counts" | sort -u) || true)
unstable=$(awk -F'\t' -v n="${#runs[@]}" '$1 < n {print $2}' "$tmp/counts" | sort | comm -12 "$tmp/expected" - || true)
[ -n "$never" ] && { echo "never found (blind spots):"; printf '%s\n' "$never" | sed 's/^/  /'; }
[ -n "$unstable" ] && { echo "found only sometimes (unstable):"; printf '%s\n' "$unstable" | sed 's/^/  /'; }
exit 0
