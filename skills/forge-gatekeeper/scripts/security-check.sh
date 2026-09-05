#!/usr/bin/env bash
# security-check.sh — forge-gatekeeper step 0: deterministic security gate.
#
#   security-check.sh                 # changed files vs HEAD (staged + unstaged + untracked)
#   security-check.sh --base <ref>    # changed files in <ref>...HEAD
#   security-check.sh --all           # every tracked file (release audit)
#   security-check.sh <file>...       # exactly these files
#
# Three layers, cheapest first:
#   1. Repo hygiene   — tracked .env / key / cert files (any scope).
#   2. Built-in rules — grep -E patterns for secrets, debug leftovers, dangerous
#                       sinks (matched case-insensitively); each hit carries a GK-ID + CWE so the agent never
#                       re-litigates it. Extra project rules: <context-dir>/security-rules.txt
#                       (same format as rules.txt: ID|Severity|glob|message|regex).
#   3. External tools — gitleaks, semgrep, osv-scanner/trivy, npm audit / pip-audit,
#                       each run ONLY if installed; missing tools are reported, never fatal.
# Output, one line per hit:  file:line: GK-NNN [Severity] message (CWE-nnn)
# Exit 0 = clean, 1 = at least one hit, 2 = usage/setup error.
#
# ponytail: grep -E for built-ins; semgrep does the AST work when present.

set -eu

base=""; all=0; files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] || { echo "security-check: --base needs a ref" >&2; exit 2; }
            base=$2; shift 2 ;;
    --all)  all=1; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) files+=("$1"); shift ;;
  esac
done

ctx=""
for d in .forge context; do [ -d "$d" ] && { ctx=$d; break; }; done

if [ ${#files[@]} -eq 0 ]; then
  if [ "$all" -eq 1 ]; then
    while IFS= read -r f; do files+=("$f"); done < <(git ls-files)
  elif [ -n "$base" ]; then
    while IFS= read -r f; do files+=("$f"); done < <(git diff --name-only "$base...HEAD")
  else
    while IFS= read -r f; do files+=("$f"); done < <(
      { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)
  fi
fi
[ ${#files[@]} -gt 0 ] || { echo "security-check: no changed files"; exit 0; }

hits=0
hit() { printf '%s\n' "$1"; hits=$((hits + 1)); }

# ---- 1. repo hygiene: secret-bearing files must never be tracked ------------
while IFS= read -r f; do
  [ -n "$f" ] || continue
  hit "$f:1: GK-001 [Critical] secret-bearing file is tracked by git — remove and rotate (CWE-540)"
done < <(git ls-files 2>/dev/null | grep -E '(^|/)\.env(\.[A-Za-z0-9_-]+)?$|\.(pem|key|p12|pfx|jks)$|id_(rsa|ed25519|ecdsa)$' \
         | grep -vE '\.env\.(example|sample|template)$' || true)

# ---- 2. built-in rules (+ project security-rules.txt) ----------------------
# ID|Severity|glob|message|regex   — regex LAST so it may contain |
BUILTIN='
GK-010|Critical|*|hardcoded secret / credential assignment (CWE-798)|(api[_-]?key|secret|password|passwd|token|private[_-]?key)["'"'"']?\s*[:=]\s*["'"'"'][^"'"'"'[:space:]]{8,}["'"'"']
GK-011|Critical|*|AWS access key id literal (CWE-798)|\bAKIA[0-9A-Z]{16}\b
GK-012|Critical|*|private key block committed (CWE-321)|-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----
GK-013|Critical|*|GitHub / Slack / Stripe token literal (CWE-798)|\b(ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|xox[baprs]-[A-Za-z0-9-]{10,}|sk_live_[A-Za-z0-9]{16,})\b
GK-014|Critical|*|connection string with inline password (CWE-798)|[a-z]+://[^:/[:space:]]+:[^@/[:space:]]{4,}@[^\s"'"'"']+
GK-020|Important|*.{js,jsx,ts,tsx,mjs,cjs}|debug output left in shipped code — use the logger (CWE-489)|^\s*console\.(log|debug|trace)\(
GK-021|Important|*.py|debug output / breakpoint left in shipped code (CWE-489)|^\s*(print\(|breakpoint\(\)|import pdb|pdb\.set_trace)
GK-022|Important|*.{js,jsx,ts,tsx,py,go,rb,php}|debugger / dev-only statement left in code (CWE-489)|^\s*(debugger;?|binding\.pry|byebug)\s*$
GK-030|Critical|*.{js,jsx,ts,tsx,mjs,cjs}|eval / Function constructor on runtime data (CWE-95)|\b(eval|new Function)\s*\(
GK-031|Critical|*.{js,jsx,ts,tsx,mjs,cjs}|shell exec with string command — use execFile/spawn with args (CWE-78)|\b(child_process\.)?(exec|execSync)\s*\(\s*[`"'"'"'].*[$+]
GK-032|Critical|*.py|shell=True with interpolated command (CWE-78)|subprocess\.[a-z_]+\(.*shell\s*=\s*True
GK-033|Critical|*.py|pickle/yaml.load of untrusted data (CWE-502)|\b(pickle\.loads?\(|yaml\.unsafe_load\(|yaml\.load\([^)L]*\))
GK-034|Critical|*.{js,jsx,ts,tsx}|raw HTML sink — sanitize or use text APIs (CWE-79)|\b(dangerouslySetInnerHTML|\.innerHTML\s*=|document\.write\()
GK-035|Critical|*.{js,ts,py,go,rb,php,java,kt,cs}|SQL built by string concatenation / interpolation (CWE-89)|(SELECT|INSERT|UPDATE|DELETE)\b[^;\n]*(\+\s*[a-zA-Z_]|\$\{|%s|f["'"'"'])
GK-040|Important|*.{js,ts,mjs,cjs,py,go,yml,yaml,json,toml}|TLS verification disabled (CWE-295)|(rejectUnauthorized\s*:\s*false|NODE_TLS_REJECT_UNAUTHORIZED\s*=\s*.?0|verify\s*=\s*False|InsecureSkipVerify\s*:\s*true)
GK-041|Important|*.{js,ts,mjs,cjs,py,go,yml,yaml,json,toml}|CORS wildcard with credentials / origin reflected (CWE-942)|(Access-Control-Allow-Origin["'"'"']?\s*[:,]\s*["'"'"']\*|origin\s*:\s*true\b|cors\(\s*\)\s*;?\s*$)
GK-042|Important|*.{js,ts,py,go,rb,php,java,kt}|weak hash for security purpose (CWE-328)|\b(md5|sha1)\s*\(|createHash\(\s*["'"'"'](md5|sha1)|hashlib\.(md5|sha1)\(
'
rules_src=$(mktemp); trap 'rm -f "$rules_src"' EXIT
printf '%s\n' "$BUILTIN" > "$rules_src"
[ -n "$ctx" ] && [ -f "$ctx/security-rules.txt" ] && cat "$ctx/security-rules.txt" >> "$rules_src"

while IFS='|' read -r id sev glob msg regex; do
  case "$id" in ''|'#'*) continue ;; esac
  [ -n "$regex" ] || { echo "security-check: malformed rule line for $id (need 5 fields)" >&2; exit 2; }
  # {a,b} alternation in glob → case patterns
  pats=$glob
  if printf '%s' "$glob" | grep -q '{'; then
    pre=${glob%%\{*}; post=${glob##*\}}; inner=${glob#*\{}; inner=${inner%%\}*}
    pats=$(printf '%s' "$inner" | tr ',' '\n' | sed -e "s|^|$pre|" -e "s|\$|$post|")
  fi
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    case "$f" in *.lock|*-lock.json|*.min.js|*.map|*.snap|*.svg|*.png|*.jpg|*.gif|*.woff*|*.pdf) continue ;; esac
    case "$f" in */test/*|*/tests/*|*/__tests__/*|*.test.*|*.spec.*|*_test.go|*/fixtures/*|*/golden/*) skip_test=1 ;; *) skip_test=0 ;; esac
    match=0
    while IFS= read -r p; do
      # shellcheck disable=SC2254  # glob from the rule is meant to expand
      case "$f" in $p|*/$p) match=1; break ;; esac
    done <<< "$pats"
    [ "$match" -eq 1 ] || continue
    # generic-secret + debug-leftover rules skip test/fixture files (gitleaks covers
    # those); specific token formats and dangerous sinks always apply
    [ "$skip_test" -eq 1 ] && case "$id" in GK-010|GK-02*) continue ;; esac
    while IFS= read -r ln; do
      [ -n "$ln" ] || continue
      hit "$f:$ln: $id [$sev] $msg"
    done < <(grep -niE -- "$regex" "$f" 2>/dev/null | cut -d: -f1 || true)
  done
done < "$rules_src"

# ---- 3. external tools — best effort, only when installed ------------------
missing=()
run_tool() { # name, then command…
  local name=$1; shift
  if command -v "$name" >/dev/null 2>&1; then
    echo "security-check: running $name"
    if ! "$@" ; then hits=$((hits + 1)); fi
  else missing+=("$name"); fi
}
{
  run_tool gitleaks gitleaks detect --no-banner --redact --exit-code 1 ${base:+--log-opts "$base...HEAD"} 2>/dev/null
  run_tool semgrep semgrep scan --quiet --error --config p/owasp-top-ten --config p/secrets -- "${files[@]}"
  if command -v osv-scanner >/dev/null 2>&1; then
    run_tool osv-scanner osv-scanner scan --recursive .
  else
    run_tool trivy trivy fs --quiet --exit-code 1 --scanners vuln,secret,misconfig --severity HIGH,CRITICAL .
  fi
  [ -f package-lock.json ] && command -v npm >/dev/null 2>&1 && \
    { echo "security-check: running npm audit"; npm audit --omit=dev --audit-level=high >/dev/null 2>&1 || hit "package-lock.json:1: GK-090 [Critical] npm audit reports HIGH/CRITICAL vulnerabilities in prod deps (CWE-1395)"; }
  [ -f requirements.txt ] || [ -f pyproject.toml ] && command -v pip-audit >/dev/null 2>&1 && \
    { echo "security-check: running pip-audit"; pip-audit -q >/dev/null 2>&1 || hit "requirements:1: GK-090 [Critical] pip-audit reports known vulnerabilities (CWE-1395)"; }
}
[ ${#missing[@]} -gt 0 ] && echo "security-check: not installed, skipped: ${missing[*]} (install for full coverage)"

[ "$hits" -eq 0 ] && { echo "security-check: clean (${#files[@]} files)"; exit 0; }
echo "security-check: $hits finding(s)"
exit 1
