#!/bin/bash

set -e

usage() {
    echo "Usage:"
    echo "  $0 image1 [image2 ...]"
    echo "  $0 -f image_list.txt"
    exit 1
}

# Проверка наличия Docker
if ! command -v docker &>/dev/null; then
    echo "❌ Docker не установлен."
    exit 1
fi

# Проверка входных параметров
if [[ $# -lt 1 ]]; then
    usage
fi

IMAGES=()

# Если первый параметр -f, читаем из файла
if [[ "$1" == "-f" ]]; then
    FILE="$2"
    if [[ -z "$FILE" || ! -f "$FILE" ]]; then
        echo "❌ Файл со списком образов не найден: $FILE"
        exit 1
    fi
    # Читаем строки, пропуская пустые и комментарии
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        IMAGES+=("$line")
    done < "$FILE"
else
    IMAGES=("$@")
fi

for IMAGE in "${IMAGES[@]}"; do
    # Имя файла: заменяем все символы / и : на _
    SAFE_NAME=$(echo "$IMAGE" | sed 's#[/:]#_#g')
    ARCHIVE="${SAFE_NAME}.tar"

    echo "=========================================="
    echo "⏬ Скачиваем образ: $IMAGE"
    docker pull "$IMAGE"

    echo "💾 Сохраняем в архив: $ARCHIVE"
    docker save -o "$ARCHIVE" "$IMAGE"
    echo "✅ Готово: $ARCHIVE"
done

echo "Все образы успешно скачаны и сохранены."
