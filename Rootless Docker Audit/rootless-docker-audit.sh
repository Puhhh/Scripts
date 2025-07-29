#!/bin/bash

set -euo pipefail

#########################################
#            ФУНКЦИИ ЛОГОВ              #
#########################################

STATUS_SUMMARY=()

log()    { echo -e "$@"; }
ok()     { log "✅ $@"; STATUS_SUMMARY+=("[OK] $@"); }
warn()   { log "⚠️ $@"; STATUS_SUMMARY+=("[WARN] $@"); }
fail()   { log "❌ $@"; STATUS_SUMMARY+=("[FAIL] $@"); }
step()   { log "\n$@"; }

show_summary() {
    log "\n--------------------------------------------"
    log "📋 Итоговая таблица аудита:"
    for status in "${STATUS_SUMMARY[@]}"; do
        echo "$status"
    done
    log "--------------------------------------------"
}

#########################################
#               СКРИПТ                  #
#########################################

if [[ "${1-}" =~ ^-h|--help$ ]]; then
    echo "Usage: $0
Проводит аудит rootless Docker.
"
    exit 0
fi

CURRENT_USER=$(whoami)
KERNEL_VERSION=$(uname -r)
CONFIG_FILE="/boot/config-$KERNEL_VERSION"

log "🔍 Rootless Docker Audit Script"
log "👤 Текущий пользователь: $CURRENT_USER"
log "🧠 Ядро: $KERNEL_VERSION"
log "--------------------------------------------"

# Проверка необходимых бинарников
step "[A] Проверка зависимостей..."
for bin in pgrep ps stat grep uname awk lsns unshare command docker; do
    if ! command -v "$bin" &>/dev/null; then
        fail "Не найдена утилита: $bin"
        [ "$bin" != "docker" ] && exit 1 # Без docker можно продолжать
    fi
done

# 0. Проверка владельца процесса dockerd
step "[0] Проверка пользователя dockerd:"
DOCKERD_PID=$(pgrep -xo dockerd 2>/dev/null || true)
if [ -z "$DOCKERD_PID" ]; then
    fail "Процесс dockerd не найден. Возможно, Docker не запущен"
    show_summary; exit 1
fi

DOCKERD_USER=$(ps -o user= -p "$DOCKERD_PID")
log "🔹 dockerd запущен пользователем: $DOCKERD_USER"
if [ "$DOCKERD_USER" != "root" ]; then
    ok "dockerd запущен без root (rootless mode)"
else
    fail "dockerd работает как root. Аудит rootless невозможен."
    show_summary; exit 1
fi

if [ "$CURRENT_USER" != "$DOCKERD_USER" ]; then
    fail "Скрипт выполняется не тем пользователем, что и dockerd ($CURRENT_USER vs $DOCKERD_USER)!"
    warn "Запустите аудит от имени: $DOCKERD_USER"
    show_summary; exit 1
fi

# Проверка, не запущен ли dockerd от root одновременно
OTHER_DOCKERD_PID=$(pgrep -xo -u root dockerd 2>/dev/null || true)
if [ -n "$OTHER_DOCKERD_PID" ]; then
    warn "Найден обычный dockerd, запущенный от root (PID: $OTHER_DOCKERD_PID). Возможен конфликт портов и сокетов."
fi

log "--------------------------------------------"

# 1. Проверка CONFIG_USER_NS
step "[1] Проверка CONFIG_USER_NS:"
if [ -f "$CONFIG_FILE" ]; then
    if grep -q "CONFIG_USER_NS=y" "$CONFIG_FILE"; then
        ok "CONFIG_USER_NS включён"
    else
        fail "CONFIG_USER_NS выключен! Rootless Docker не будет работать"
    fi
else
    warn "Конфигурация ядра не найдена в $CONFIG_FILE"
fi

# 2. Проверка /etc/subuid и /etc/subgid
step "[2] Проверка /etc/subuid и /etc/subgid:"
SUBUID_LINE=$(grep "^$CURRENT_USER:" /etc/subuid 2>/dev/null || true)
SUBGID_LINE=$(grep "^$CURRENT_USER:" /etc/subgid 2>/dev/null || true)
if [ -n "$SUBUID_LINE" ]; then
    ok "Запись в /etc/subuid для $CURRENT_USER: $SUBUID_LINE"
else
    fail "Нет записи в /etc/subuid для $CURRENT_USER"
fi
if [ -n "$SUBGID_LINE" ]; then
    ok "Запись в /etc/subgid для $CURRENT_USER: $SUBGID_LINE"
else
    fail "Нет записи в /etc/subgid для $CURRENT_USER"
fi

# 3. Проверка утилит, необходимых для rootless Docker
step "[3] Проверка дополнительных утилит:"
for bin in slirp4netns fuse-overlayfs newuidmap newgidmap; do
    if command -v "$bin" &> /dev/null; then
        ok "$bin найден"
    else
        fail "$bin не найден"
    fi
done

# 4. Проверка cgroup
step "[4] Проверка cgroup:"
CGROUP_FS=$(stat -fc %T /sys/fs/cgroup/ 2>/dev/null || echo "none")
if [ "$CGROUP_FS" = "cgroup2fs" ]; then
    ok "Используется cgroup v2"
else
    warn "Используется cgroup v1 — рекомендуется использовать cgroup v2"
fi

# 5. Проверка user namespace
step "[5] Проверка user namespace (unshare):"
if unshare -Ur true &> /dev/null; then
    ok "User namespaces работают (unshare -Ur)"
else
    fail "Не удалось создать user namespace (unshare -Ur)"
fi

# Дополнительная диагностика user namespaces
step "[5.1] Поддержка user namespaces в системе:"
if lsns | grep -q user; then
    ok "User namespaces обнаружены в текущей сессии"
else
    warn "User namespaces отсутствуют в списке пространств имён"
fi

# 6. Проверка docker info и режим работы
step "[6] Проверка docker info:"
if command -v docker &> /dev/null; then
    log "Версия docker: $(docker --version)"
    if docker info --format '{{json .SecurityOptions}}' | grep -q rootless; then
        ok "Docker работает в rootless режиме (SecurityOptions)"
    else
        fail "Docker НЕ работает в rootless режиме (SecurityOptions)"
    fi
    # Проверка Docker host env
    if [[ "${DOCKER_HOST:-}" == "unix://"* ]]; then
        ok "DOCKER_HOST использует unix socket: $DOCKER_HOST"
    else
        warn "DOCKER_HOST переменная не определена или использует нестандартный сокет"
    fi
else
    fail "Docker не установлен"
fi

# 7. Проверка переменных окружения
step "[7] Проверка окружения и сокетов:"
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    ok "XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
else
    warn "XDG_RUNTIME_DIR не установлен"
fi

if [ -S "$XDG_RUNTIME_DIR/docker.sock" ]; then
    ok "docker.sock обнаружен: $XDG_RUNTIME_DIR/docker.sock"
else
    fail "docker.sock не найден по пути $XDG_RUNTIME_DIR/docker.sock"
fi

# 8. Проверка сокетов dockerd
step "[8] Проверка сокетов dockerd:"
for sock in "/run/user/$(id -u)/docker.sock" "$XDG_RUNTIME_DIR/docker.sock"; do
    if [ -S "$sock" ]; then
        ok "Сокет найден: $sock"
    else
        warn "Сокет не найден: $sock"
    fi
done

# 9. Проверка прав на критичные файлы
step "[9] Проверка прав на /etc/subuid, /etc/subgid:"
for file in /etc/subuid /etc/subgid; do
    if [ -f "$file" ]; then
        PERM=$(stat -c "%a" "$file")
        [ "$PERM" -le 644 ] && ok "$file имеет права $PERM" || warn "$file имеет слишком открытые права ($PERM), рекомендуется <=644"
    else
        warn "$file не найден"
    fi
done

# 10. Проверка окружения пользователя на наличие нестандартных переменных docker
step "[10] Проверка окружения пользователя:"
for var in DOCKER_DRIVER DOCKER_ROOTLESS_ROOTLESSKIT_PORT_DRIVER; do
    if [ -n "${!var:-}" ]; then
        ok "Переменная $var установлена: ${!var}"
    fi
done

# 11. Рекомендации по устранению проблем (вывод только если есть FAIL/WARN)
SHOW_RECOMMEND=0
for status in "${STATUS_SUMMARY[@]}"; do
    [[ "$status" =~ "\[FAIL\]" || "$status" =~ "\[WARN\]" ]] && SHOW_RECOMMEND=1
done
if [ "$SHOW_RECOMMEND" = 1 ]; then
    log "\n🚑 Рекомендации:"
    [[ "$(grep -q 'CONFIG_USER_NS' <<<"${STATUS_SUMMARY[*]}" || true)" ]] && \
        log "  - Включите поддержку user namespaces в ядре (CONFIG_USER_NS=y)"
    [[ "$(grep -q '/etc/subuid' <<<"${STATUS_SUMMARY[*]}" || true)" ]] && \
        log "  - Добавьте строку '$CURRENT_USER:100000:65536' в /etc/subuid и /etc/subgid"
    [[ "$(grep -q 'cgroup v1' <<<"${STATUS_SUMMARY[*]}" || true)" ]] && \
        log "  - Переключитесь на cgroup v2 для лучшей поддержки rootless Docker"
    [[ "$(grep -q 'slirp4netns не найден' <<<"${STATUS_SUMMARY[*]}" || true)" ]] && \
        log "  - Установите slirp4netns, fuse-overlayfs, newuidmap, newgidmap для rootless режима"
    [[ "$(grep -q 'docker.sock не найден' <<<"${STATUS_SUMMARY[*]}" || true)" ]] && \
        log "  - Проверьте запуск dockerd rootless: https://docs.docker.com/engine/security/rootless/"
fi

show_summary

log "\n🔚 Аудит завершён"
