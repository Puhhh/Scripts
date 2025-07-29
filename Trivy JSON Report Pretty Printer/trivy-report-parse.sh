#!/bin/bash

set -e

usage() {
  cat <<EOF
Usage: $0 <config|vuln> <trivy-json-report.json> [--min-severity=LEVEL]

Modes:
  config     Show misconfigurations (policy violations)
  vuln       Show vulnerabilities

Options:
  --min-severity=LEVEL   Minimum severity to display (CRITICAL|HIGH|MEDIUM|LOW|UNKNOWN)
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
    UNKNOWN)  echo '\033[0;37m' ;; # Серый
    *)        echo '\033[0m'   ;; # Сброс
  esac
}
ENDC='\033[0m'

# Фильтрация по severity в jq (через объекты)
SEVERITY_JQ_OBJ='{"CRITICAL":1,"HIGH":2,"MEDIUM":3,"LOW":4,"UNKNOWN":5}'

# Функция печати строк с цветом по severity
print_table_with_colors() {
  mode="$1"
  while IFS=$'\t' read -r col1 col2 col3 col4 col5; do
    if [[ "$mode" == "vuln" ]]; then
      sev="$col4"
      color=$(map_color "$sev")
      printf "${color}%s\t%s\t%s\t%s\t%s${ENDC}\n" "$col1" "$col2" "$col3" "$col4" "$col5"
    else
      sev="$col2"
      color=$(map_color "$sev")
      printf "${color}%s\t%s\t%s\t%s\t%s${ENDC}\n" "$col1" "$col2" "$col3" "$col4" "$col5"
    fi
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
    ' "$FILE" | print_table_with_colors config
    echo -e "\033[1;36m▶ Total: $COUNT\033[0m"
    ;;
  vuln)
    echo -e "\033[1;36m🛡 Vulnerabilities:\033[0m"
    COUNT=$(jq --arg min_sev "$MIN_SEV" --argjson order "$SEVERITY_JQ_OBJ" '
      [ .Results[]?.Vulnerabilities[]?
        | select(($order[.Severity] // 6) <= ($order[$min_sev] // 4))
      ] | length
    ' "$FILE")
    if [[ $COUNT -eq 0 ]]; then
      echo -e "\033[1;32m✅ No vulnerabilities found (severity >= $MIN_SEV).\033[0m"
      exit 0
    fi
    jq -r --arg min_sev "$MIN_SEV" --argjson order "$SEVERITY_JQ_OBJ" '
      [ .Results[]?.Vulnerabilities[]?
        | select(($order[.Severity] // 6) <= ($order[$min_sev] // 4))
        | {
          id: .VulnerabilityID,
          pkg: .PkgName,
          ver: .InstalledVersion,
          severity: .Severity,
          title: (.Title // "N/A")
        }
      ]
      | sort_by($order[.severity])
      | .[]
      | [ .id, .pkg, .ver, .severity, .title ] | @tsv
    ' "$FILE" | print_table_with_colors vuln
    echo -e "\033[1;36m▶ Total: $COUNT\033[0m"
    ;;
esac
