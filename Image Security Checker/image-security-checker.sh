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

WORKDIR=""
CONTAINER_ID=""

cleanup() {
  if [[ -n "$CONTAINER_ID" ]]; then
    docker rm -f "$CONTAINER_ID" &>/dev/null || true
  fi
  if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

REQUIRED_CMDS=(docker tar grep find cut tr sed awk stat)
for cmd in "${REQUIRED_CMDS[@]}"; do
  command -v "$cmd" &>/dev/null || { echo "Не найдено: $cmd"; exit 2; }
done

if ! docker info &>/dev/null; then
  log_fail "Docker демон не запущен или недоступен"
  exit 2
fi

show_usage() {
  echo "Usage: $0 <image_name> | -f <image_list_file>"
  echo "  <image_name>           - имя или ID Docker-образа"
  echo "  -f <image_list_file>   - файл со списком образов (по одному в строке)"
  exit 1
}

if [[ $# -eq 0 ]]; then
  show_usage
fi

IMAGES=()
if [[ "$1" == "-f" ]]; then
  [[ $# -ne 2 ]] && show_usage
  [[ ! -f "$2" ]] && { echo "Файл не найден: $2"; exit 2; }
  # Пропускаем пустые строки и комментарии
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    IMAGES+=("$line")
  done < "$2"
else
  IMAGES=("$1")
fi

run_check() {
  local check_func="$1"
  shift
  set +e
  "$check_func" "$@"
  local status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    log_warn "Проверка ${check_func} не выполнена (код $status)"
  fi
}

check_image() {
  local IMAGE="$1"
  echo -e "\n${YELLOW}============================================"
  echo    "   Проверка Docker-образа: $IMAGE"
  echo -e "============================================${NC}\n"

  WORKDIR=$(mktemp -d)
  CONTAINER_ID=$(docker create "$IMAGE") || { log_fail "Не удалось создать контейнер из образа $IMAGE"; return; }

  docker export "$CONTAINER_ID" | tar -C "$WORKDIR" -xf - || return 1

  # === 1. Проверка пользователя по умолчанию ===
  check_user() {
    USER_LINE=$(docker inspect --format '{{.Config.User}}' "$IMAGE") || return 1
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
    return 0
  }

  # === 2. Проверка базового дистрибутива ===
  check_base_os() {
    BASE_OS=$(grep -iEr 'redos|astralinux|alt' "$WORKDIR"/etc/*-release 2>/dev/null | head -1 || true)
    BASE_OS_REL=$(echo "$BASE_OS" | sed "s|$WORKDIR||")
    if [[ -n "$BASE_OS_REL" ]]; then
      BASE_OS_CHECK=$(echo "$BASE_OS_REL" | tr '[:upper:]' '[:lower:]')
      if [[ "$BASE_OS_CHECK" =~ (redos|astralinux|alt) ]]; then
        log_ok "Базовый дистрибутив: $BASE_OS_REL"
      else
        log_fail "Базовый дистрибутив не Red OS / Astra Linux / ALT. Найдено: $BASE_OS_REL"
      fi
    else
      OTHER_OS=$(grep -iE 'id=|distr|os=' "$WORKDIR"/etc/*-release 2>/dev/null | head -1 | sed "s|$WORKDIR||")
      if [[ -n "$OTHER_OS" ]]; then
        log_fail "Базовый дистрибутив не Red OS / Astra Linux / ALT. Найдено: $OTHER_OS"
      else
        log_fail "Базовый дистрибутив не Red OS / Astra Linux / ALT. Найдено: ничего не найдено"
      fi
    fi
    return 0
  }


  # === 3. Проверка на distroless ===
  check_distroless() {
    DISTROLESS_SCORE=0
    DISTROLESS_FAILS=()
    FOUND_SHELLS=$(find "$WORKDIR" -type f \( -name 'sh' -o -name 'bash' -o -name 'dash' \) 2>/dev/null)
    if [[ -z "$FOUND_SHELLS" ]]; then
      ((DISTROLESS_SCORE++))
    else
      DISTROLESS_FAILS+=("Найдены shell-утилиты:")
      while read -r f; do [[ -n "$f" ]] && DISTROLESS_FAILS+=("${f#$WORKDIR}"); done <<< "$FOUND_SHELLS"
    fi
    FOUND_PKG=$(find "$WORKDIR" -type f \( -name 'apt' -o -name 'yum' -o -name 'dnf' -o -name 'apk' \) 2>/dev/null)
    FOUND_CURL_WGET=$(find "$WORKDIR" -type f \( -name 'curl' -o -name 'wget' \) 2>/dev/null)
    FOUND_BUSYBOX=$(find "$WORKDIR" -type f -name 'busybox' 2>/dev/null)
    if [[ -z "$FOUND_PKG" && -z "$FOUND_CURL_WGET" && -z "$FOUND_BUSYBOX" ]]; then
      ((DISTROLESS_SCORE++))
    else
      [[ -n "$FOUND_PKG" ]] && DISTROLESS_FAILS+=("Найдены package manager-утилиты: $(echo "$FOUND_PKG" | sed "s|$WORKDIR||g")")
      [[ -n "$FOUND_CURL_WGET" ]] && DISTROLESS_FAILS+=("Найден curl/wget: $(echo "$FOUND_CURL_WGET" | sed "s|$WORKDIR||g")")
      [[ -n "$FOUND_BUSYBOX" ]] && DISTROLESS_FAILS+=("Найден busybox: $(echo "$FOUND_BUSYBOX" | sed "s|$WORKDIR||g")")
    fi
    if [[ "$DISTROLESS_SCORE" -ge 2 ]]; then
      log_ok "Образ, скорее всего, distroless"
    else
      log_fail "Образ не похож на distroless, найдено:"
      for fail in "${DISTROLESS_FAILS[@]}"; do echo "    $fail"; done
    fi
    return 0
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
    return 0
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
    return 0
  }

  # === 6. Проверка на наличие root-процессов в ENTRYPOINT/CMD ===
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
    return 0
  }

  # === 7. Проверка разрешений на чувствительные каталоги ===
  check_sensitive_dirs() {
    get_perms() {
      local path="$1"
      if stat -f "%p" "$path" >/dev/null 2>&1; then
        stat -f "%Lp" "$path" | awk '{print substr($0,length($0)-2,3)}'
      elif stat -c "%a" "$path" >/dev/null 2>&1; then
        stat -c "%a" "$path"
      else
        echo "???"
      fi
    }
    for dir in /etc /var /root /home; do
      DIRPATH="$WORKDIR$dir"
      [[ -d "$DIRPATH" ]] || continue
      perms=$(get_perms "$DIRPATH")
      if [[ "$perms" == "???" ]]; then
        log_warn "Не удалось определить права для каталога $dir"
        continue
      fi
      if [[ "$perms" -gt 755 ]]; then
        log_fail "Каталог $dir имеет небезопасные разрешения: $perms"
      else
        log_ok "Каталог $dir разрешения: $perms"
      fi
    done
    return 0
  }

  # === Запуск всех проверок ===
  run_check check_user
  run_check check_base_os
  run_check check_distroless
  run_check check_suid_sgid
  run_check check_su_sudo
  run_check check_entrypoint_root
  run_check check_sensitive_dirs
  trap - EXIT
  cleanup
}

# ==== Запуск для всех образов ====
for IMAGE in "${IMAGES[@]}"; do
  check_image "$IMAGE"
done
