#!/bin/bash

set -e

usage() {
    echo "Usage:"
    echo "  $0 [-p platform] image1 [image2 ...]"
    echo "  $0 [-p platform] -f image_list.txt"
    echo "Options:"
    echo "  -p platform   Платформа для pull/save (по умолчанию: linux/amd64)"
    exit 1
}

# Проверка наличия Docker
if ! command -v docker &>/dev/null; then
    echo "❌ Docker не установлен."
    exit 1
fi

PLATFORM="linux/amd64"
IMAGES=()
FILE=""

# Парсим аргументы
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p)
            PLATFORM="$2"
            shift 2
            ;;
        -f)
            FILE="$2"
            shift 2
            ;;
        -*)
            usage
            ;;
        *)
            IMAGES+=("$1")
            shift
            ;;
    esac
done

# Если выбран файл
if [[ -n "$FILE" ]]; then
    if [[ ! -f "$FILE" ]]; then
        echo "❌ Файл со списком образов не найден: $FILE"
        exit 1
    fi
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        IMAGES+=("$line")
    done < "$FILE"
fi

if [[ ${#IMAGES[@]} -eq 0 ]]; then
    usage
fi

for IMAGE in "${IMAGES[@]}"; do
    SAFE_NAME=$(echo "$IMAGE" | sed 's#[/:]#_#g')
    ARCHIVE="${SAFE_NAME}.tar"

    echo "=========================================="
    echo "⏬ Скачиваем образ: $IMAGE для платформы $PLATFORM"
    docker pull --platform "$PLATFORM" "$IMAGE"

    echo "💾 Сохраняем в архив: $ARCHIVE"
    docker save -o "$ARCHIVE" "$IMAGE"
    echo "✅ Готово: $ARCHIVE"
done

echo "Все образы успешно скачаны и сохранены."
