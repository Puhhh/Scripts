#!/bin/bash

set -e

usage() {
  cat <<EOF
Usage: $0 <config|vuln> <trivy-json-report.json> [--min-severity=LEVEL]

Modes:
  config     Show misconfigurations (policy violations)
  vuln       Show vulnerabilities (Trivy or Grype JSON)

Options:
  --min-severity=LEVEL   Minimum severity to display (CRITICAL|HIGH|MEDIUM|LOW|NEGLIGIBLE|UNKNOWN)
EOF
}

# Если нет обязательных параметров — показать usage
if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

MODE=$1
FILE=$2
MIN_SEV="LOW"
shift 2

# Parse extra options
for arg in "$@"; do
  case $arg in
    --min-severity=*)
      MIN_SEV="${arg#*=}"
      ;;
    *)
      usage; exit 1
      ;;
  esac
done

to_upper() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

MIN_SEV=$(to_upper "$MIN_SEV")
case "$MIN_SEV" in
  CRITICAL|HIGH|MEDIUM|LOW|NEGLIGIBLE|UNKNOWN)
    ;;
  *)
    echo -e "\033[1;31m❌ Unsupported severity level: $MIN_SEV\033[0m"
    exit 1
    ;;
esac

if [[ "$MODE" != "config" && "$MODE" != "vuln" ]]; then
  usage; exit 1
fi

if [[ ! -f "$FILE" ]]; then
  echo -e "\033[1;31m❌ File not found: $FILE\033[0m"
  exit 1
fi

for dep in jq column; do
  if ! command -v "$dep" &>/dev/null; then
    echo -e "\033[1;31m❌ '$dep' not installed. Install with: sudo apt install $dep\033[0m"
    exit 1
  fi
done

# Цвета для разных уровней severity
map_color() {
  case "$1" in
    CRITICAL) echo '\033[1;31m' ;; # Красный
    HIGH)     echo '\033[1;33m' ;; # Желтый
    MEDIUM)   echo '\033[1;34m' ;; # Синий
    LOW)      echo '\033[1;32m' ;; # Зеленый
    NEGLIGIBLE) echo '\033[0;37m' ;;
    UNKNOWN)  echo '\033[0;37m' ;; # Серый
    *)        echo '\033[0m'   ;; # Сброс
  esac
}
ENDC='\033[0m'

# Фильтрация по severity в jq (через объекты)
SEVERITY_JQ_OBJ='{"CRITICAL":1,"HIGH":2,"MEDIUM":3,"LOW":4,"NEGLIGIBLE":5,"UNKNOWN":6}'

# Функция печати строк с цветом по severity
print_table_with_colors() {
  local severity_index=$1
  while IFS=$'\t' read -r -a cols; do
    (( ${#cols[@]} == 0 )) && continue
    local sev="${cols[$((severity_index-1))]}"
    local color
    color=$(map_color "$(to_upper "$sev")")
    printf "%b" "$color"
    for i in "${!cols[@]}"; do
      (( i > 0 )) && printf "\t"
      printf "%s" "${cols[$i]}"
    done
    printf "%b\n" "$ENDC"
  done | column -t -s $'\t'
}

case "$MODE" in
  config)
    echo -e "\033[1;36m🔧 Misconfigurations:\033[0m"
    COUNT=$(jq --arg min_sev "$MIN_SEV" --argjson order "$SEVERITY_JQ_OBJ" '
      [ .Results[]?.Misconfigurations[]?
        | select(($order[.Severity] // 6) <= ($order[$min_sev] // 4))
      ] | length
    ' "$FILE")
    if [[ $COUNT -eq 0 ]]; then
      echo -e "\033[1;32m✅ No misconfigurations found (severity >= $MIN_SEV).\033[0m"
      exit 0
    fi
    jq -r --arg min_sev "$MIN_SEV" --argjson order "$SEVERITY_JQ_OBJ" '
      [ .Results[]?.Misconfigurations[]?
        | select(($order[.Severity] // 6) <= ($order[$min_sev] // 4))
        | {
          id: .ID,
          severity: .Severity,
          title: .Title,
          message: .Message,
          resolution: .Resolution
        }
      ]
      | sort_by($order[.severity])
      | .[]
      | [ .id, .severity, .title, .message, .resolution ] | @tsv
    ' "$FILE" | print_table_with_colors 2
    echo -e "\033[1;36m▶ Total: $COUNT\033[0m"
    ;;
  vuln)
    echo -e "\033[1;36m🛡 Vulnerabilities:\033[0m"
    if jq -e '.Results? | length > 0' "$FILE" &>/dev/null; then
      COUNT=$(jq --arg min_sev "$MIN_SEV" --argjson order "$SEVERITY_JQ_OBJ" '
        def to_upper($s):
          ($s | tostring | explode
               | map(if . >= 97 and . <= 122 then . - 32 else . end)
               | implode);
        [ .Results[]?.Vulnerabilities[]?
          | select(($order[to_upper(.Severity // "UNKNOWN")] // 999) <= ($order[$min_sev] // 999))
        ] | length
      ' "$FILE")
      if [[ $COUNT -eq 0 ]]; then
        echo -e "\033[1;32m✅ No vulnerabilities found (severity >= $MIN_SEV).\033[0m"
        exit 0
      fi
      jq -r --arg min_sev "$MIN_SEV" --argjson order "$SEVERITY_JQ_OBJ" '
        def to_upper($s):
          ($s | tostring | explode
               | map(if . >= 97 and . <= 122 then . - 32 else . end)
               | implode);
        [ .Results[]?.Vulnerabilities[]?
          | select(($order[to_upper(.Severity // "UNKNOWN")] // 999) <= ($order[$min_sev] // 999))
          | {
            id: .VulnerabilityID,
            pkg: .PkgName,
            ver: .InstalledVersion,
            severity: (.Severity // "UNKNOWN"),
            title: (.Title // "N/A")
          }
        ]
        | sort_by($order[to_upper(.severity)])
        | .[]
        | [ .id, .pkg, .ver, .severity, .title ] | @tsv
      ' "$FILE" | print_table_with_colors 4
      echo -e "\033[1;36m▶ Total: $COUNT\033[0m"
    elif jq -e '.matches? | length > 0' "$FILE" &>/dev/null; then
      COUNT=$(jq --arg min_sev "$MIN_SEV" --argjson order "$SEVERITY_JQ_OBJ" '
        def to_upper($s):
          ($s | tostring | explode
               | map(if . >= 97 and . <= 122 then . - 32 else . end)
               | implode);
        [ .matches[]?
          | select(($order[to_upper(.vulnerability.severity // "UNKNOWN")] // 999) <= ($order[$min_sev] // 999))
        ] | length
      ' "$FILE")
      if [[ $COUNT -eq 0 ]]; then
        echo -e "\033[1;32m✅ No vulnerabilities found (severity >= $MIN_SEV).\033[0m"
        exit 0
      fi
      jq -r --arg min_sev "$MIN_SEV" --argjson order "$SEVERITY_JQ_OBJ" '
        def to_upper($s):
          ($s | tostring | explode
               | map(if . >= 97 and . <= 122 then . - 32 else . end)
               | implode);
        def ten_pow($n):
          reduce range(0; $n) as $i (1; . * 10);
        def format_fixed($value; $digits):
          if ($value | type) == "number" then
            (ten_pow($digits) as $factor
             | (($value * $factor) | round) / $factor
             | tostring)
          else
            $value | tostring
          end;
        [ .matches[]?
          | select(($order[to_upper(.vulnerability.severity // "UNKNOWN")] // 999) <= ($order[$min_sev] // 999))
          | {
            id: .vulnerability.id,
            pkg: .artifact.name,
            ver: .artifact.version,
            severity: (.vulnerability.severity // "UNKNOWN"),
            epss: format_fixed(.vulnerability.epss[0]?.epss // "N/A"; 5),
            risk: format_fixed(.vulnerability.risk // "N/A"; 4)
          }
        ]
        | sort_by($order[to_upper(.severity)])
        | .[]
        | [ .id,
            (.pkg // "N/A"),
            (.ver // "N/A"),
            .severity,
            .epss,
            .risk
          ] | @tsv
      ' "$FILE" | print_table_with_colors 4
      echo -e "\033[1;36m▶ Total: $COUNT\033[0m"
    else
      echo -e "\033[1;31m❌ Unsupported report format. Supported: Trivy (.Results) or Grype (.matches).\033[0m"
      exit 1
    fi
    ;;
esac
