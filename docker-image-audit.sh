#!/bin/bash
set -euo pipefail

# === Настройка цвета ===
USE_COLOR=1
RED=''; GREEN=''; YELLOW=''; NC=''
if [[ "${USE_COLOR}" == "1" && -t 1 ]]; then
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  NC=$(tput sgr0)
fi

log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_info()  { echo -e "${YELLOW}[INFO]${NC} $*"; }

REQUIRED_CMDS=(docker tar grep find head cut tr sed awk)
for cmd in "${REQUIRED_CMDS[@]}"; do
  command -v "$cmd" &>/dev/null || { echo "Не найдено: $cmd"; exit 2; }
done

IMAGE="${1:-}"
if [[ -z "$IMAGE" ]]; then
  echo "Usage: $0 <image_name>"
  exit 1
fi

WORKDIR=$(mktemp -d)
CONTAINER_ID=$(docker create "$IMAGE")

cleanup() {
  docker rm -f "$CONTAINER_ID" &>/dev/null || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

docker export "$CONTAINER_ID" | tar -C "$WORKDIR" -xf -

# === 1. Проверка пользователя по умолчанию ===
check_user() {
  USER_LINE=$(docker inspect --format '{{.Config.User}}' "$IMAGE")
  if [[ -z "$USER_LINE" || "$USER_LINE" == "root" || "$USER_LINE" == "0" ]]; then
    log_fail "USER по умолчанию не задан или равен root/0"
  else
    log_ok "USER по умолчанию: $USER_LINE"
    USERNAME=$(echo "$USER_LINE" | cut -d: -f1)
    if [[ -f "$WORKDIR/etc/passwd" ]]; then
      USERINFO=$(grep -E "^$USERNAME:" "$WORKDIR/etc/passwd" || true)
      if [[ -n "$USERINFO" ]]; then
        USER_UID=$(echo "$USERINFO" | cut -d: -f3)
        USER_GID=$(echo "$USERINFO" | cut -d: -f4)
        if [[ "$USER_UID" == "0" || "$USER_GID" == "0" ]]; then
          log_fail "UID или GID пользователя $USERNAME равен 0"
        else
          log_ok "UID/GID пользователя $USERNAME: $USER_UID/$USER_GID"
        fi
      else
        log_warn "Пользователь $USERNAME не найден в /etc/passwd"
      fi
    fi
  fi
}

# === 2. Проверка базового дистрибутива ===
check_base_os() {
  BASE_OS=$(grep -iEr 'redos|astralinux|alt' "$WORKDIR"/etc/*-release 2>/dev/null | head -1 || true)
  BASE_OS_REL=$(echo "$BASE_OS" | sed "s|$WORKDIR||")
  # Приводим к нижнему регистру для проверки
  BASE_OS_CHECK=$(echo "$BASE_OS" | tr '[:upper:]' '[:lower:]')
  if [[ "$BASE_OS_CHECK" =~ (redos|astralinux|alt) ]]; then
    log_ok "Базовый дистрибутив: $BASE_OS_REL"
  else
    log_fail "Базовый дистрибутив не Red OS / Astra Linux / ALT. Найдено: ${BASE_OS_REL:-'не найдено'}"
  fi
}

# === 3. Проверка на distroless ===
check_distroless() {
  DISTROLESS_SCORE=0
  DISTROLESS_FAILS=()
  if [[ ! -f "$WORKDIR/etc/os-release" && ! -f "$WORKDIR/etc/lsb-release" ]]; then
    ((DISTROLESS_SCORE++))
  else
    DISTROLESS_FAILS+=("Присутствует файл /etc/os-release или /etc/lsb-release")
  fi
  FOUND_SHELLS=$(find "$WORKDIR" -type f \( -name 'sh' -o -name 'bash' -o -name 'dash' \) 2>/dev/null)
  if [[ -z "$FOUND_SHELLS" ]]; then
    ((DISTROLESS_SCORE++))
  else
    DISTROLESS_FAILS+=("Найдены shell-утилиты:")
    while read -r f; do [[ -n "$f" ]] && DISTROLESS_FAILS+=("${f#$WORKDIR}"); done <<< "$FOUND_SHELLS"
  fi
  FOUND_PKG=$(find "$WORKDIR" -type f \( -name 'apt' -o -name 'yum' -o -name 'dnf' \) 2>/dev/null)
  FOUND_CURL=$(find "$WORKDIR" -type f -name 'curl' 2>/dev/null)
  FOUND_WGET=$(find "$WORKDIR" -type f -name 'wget' 2>/dev/null)
  if [[ -z "$FOUND_PKG" && -z "$FOUND_CURL" && -z "$FOUND_WGET" ]]; then
    ((DISTROLESS_SCORE++))
  else
    [[ -n "$FOUND_PKG" ]] && DISTROLESS_FAILS+=("Найдены package manager-утилиты: $(echo "$FOUND_PKG" | sed "s|$WORKDIR||g")")
    [[ -n "$FOUND_CURL" ]] && DISTROLESS_FAILS+=("Найден curl: $(echo "$FOUND_CURL" | sed "s|$WORKDIR||g")")
    [[ -n "$FOUND_WGET" ]] && DISTROLESS_FAILS+=("Найден wget: $(echo "$FOUND_WGET" | sed "s|$WORKDIR||g")")
  fi
  if [[ "$DISTROLESS_SCORE" -ge 2 ]]; then
    log_ok "Образ, скорее всего, distroless"
  else
    log_fail "Образ не похож на distroless, найдено:"
    for fail in "${DISTROLESS_FAILS[@]}"; do echo "    $fail"; done
  fi
}

# === 4. SUID/SGID ===
check_suid_sgid() {
  SUID_FILES=$(find "$WORKDIR" -perm -4000 2>/dev/null)
  if [[ -n "$SUID_FILES" ]]; then
    log_fail "Найдены файлы с SUID:"; echo "$SUID_FILES" | sed "s|$WORKDIR||g"
  else
    log_ok "Файлы с SUID отсутствуют"
  fi
  SGID_FILES=$(find "$WORKDIR" -perm -2000 2>/dev/null)
  if [[ -n "$SGID_FILES" ]]; then
    log_fail "Найдены файлы с SGID:"; echo "$SGID_FILES" | sed "s|$WORKDIR||g"
  else
    log_ok "Файлы с SGID отсутствуют"
  fi
}

# === 5. su/sudo ===
check_su_sudo() {
  PRIV_CMDS=$(find "$WORKDIR" -type f \( -name 'su' -o -name 'sudo' \) -executable 2>/dev/null)
  if [[ -n "$PRIV_CMDS" ]]; then
    log_fail "Найдены потенциально опасные исполняемые файлы (su/sudo):"
    echo "$PRIV_CMDS" | sed "s|$WORKDIR||g"
  else
    log_ok "su/sudo не найдены"
  fi
}

# === 6. Проверка на наличие секретов ===
check_secrets() {
  log_info "Проверка на наличие секретов..."
  SECRET_FILES=$(find "$WORKDIR" \
    \( -path "$WORKDIR/etc/ssl/certs" -o -path "$WORKDIR/usr/share/ca-certificates" \) -prune -o \
    \( -iname '*secret*' -o -iname '*password*' -o -iname '*.pem' -o -iname '*.key' -o -iname '*.crt' \) -print 2>/dev/null
  )

  # Для поиска по содержимому -- исключаем те же каталоги
  SECRET_CONTENT=$(grep -r --exclude-dir="$WORKDIR/etc/ssl/certs" --exclude-dir="$WORKDIR/usr/share/ca-certificates" \
    -i -E 'password|secret|token|api[_-]?key' "$WORKDIR" 2>/dev/null | head -n 10 || true)

  if [[ -n "$SECRET_FILES" ]]; then
    log_fail "Обнаружены потенциально секретные файлы:"
    echo "$SECRET_FILES" | sed "s|$WORKDIR||g"
  fi
  if [[ -n "$SECRET_CONTENT" ]]; then
    log_fail "Обнаружено потенциальное содержимое секретов (первые строки):"
    echo "$SECRET_CONTENT" | sed "s|$WORKDIR||g"
  fi
  if [[ -z "$SECRET_FILES" && -z "$SECRET_CONTENT" ]]; then
    log_ok "Явные секреты не найдены"
  fi
}


# === 7. Проверка на наличие root-процессов в ENTRYPOINT/CMD ===
check_entrypoint_root() {
  ENTRYPOINT=$(docker inspect --format '{{json .Config.Entrypoint}}' "$IMAGE" | tr -d '[]",' | xargs)
  CMD=$(docker inspect --format '{{json .Config.Cmd}}' "$IMAGE" | tr -d '[]",' | xargs)
  USER_LINE=$(docker inspect --format '{{.Config.User}}' "$IMAGE")
  USER="${USER_LINE:-root}"
  [[ -z "$USER" ]] && USER="root"
  if [[ "$USER" == "root" || "$USER" == "0" ]]; then
    if [[ -n "$ENTRYPOINT" ]]; then
      log_fail "ENTRYPOINT ($ENTRYPOINT) запускается под root"
    elif [[ -n "$CMD" ]]; then
      log_fail "CMD ($CMD) запускается под root"
    else
      log_fail "Процессы запускаются под root (ENTRYPOINT/CMD не определены явно)"
    fi
  else
    log_ok "Стартовые процессы запускаются НЕ под root (USER: $USER)"
  fi
}

# === 8. Проверка разрешений на чувствительные каталоги ===
check_sensitive_dirs() {
  for dir in /etc /var /root /home; do
    DIRPATH="$WORKDIR$dir"
    [[ -d "$DIRPATH" ]] || continue
    perms=$(stat -c "%a" "$DIRPATH")
    if [[ "$perms" -gt 755 ]]; then
      log_fail "Каталог $dir имеет небезопасные разрешения: $perms"
    else
      log_ok "Каталог $dir разрешения: $perms"
    fi
  done
}

# === 9. Проверка на устаревшие/небезопасные пакеты ===
check_vuln_packages() {
  log_info "Проверка на наличие известных небезопасных пакетов..."
  # Список известных опасных библиотек (добавь по мере необходимости)
  DANGEROUS_LIBS="libc\.so\.5|openssl-1\.0|libssl\.so\.1\.0|python2"
  VULN_FILES=$(find "$WORKDIR" -type f -regextype posix-extended -regex ".*($DANGEROUS_LIBS).*" 2>/dev/null)
  if [[ -n "$VULN_FILES" ]]; then
    log_fail "Обнаружены потенциально уязвимые/устаревшие пакеты:"
    echo "$VULN_FILES" | sed "s|$WORKDIR||g"
  else
    log_ok "Устаревшие/небезопасные пакеты не найдены"
  fi
}

# === Запуск всех проверок ===
check_user
check_base_os
check_distroless
check_suid_sgid
check_su_sudo
check_secrets
check_entrypoint_root
check_sensitive_dirs
check_vuln_packages
