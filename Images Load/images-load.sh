#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: $0 <path_to_directory_with_tar_images> [target_prefix]"
  exit 1
fi

IMG_DIR="$1"
TARGET_PREFIX="$2"

if [ ! -d "$IMG_DIR" ]; then
  echo "❌ Каталог '$IMG_DIR' не найден!"
  exit 1
fi

if command -v docker &>/dev/null; then
  CONTAINER_TOOL="docker"
elif command -v podman &>/dev/null; then
  CONTAINER_TOOL="podman"
else
  echo "❌ Не найден ни docker, ни podman!"
  exit 1
fi

echo "✔ Используется: $CONTAINER_TOOL"
if [ -n "$TARGET_PREFIX" ]; then
  echo "✔ Префикс для новых тегов: $TARGET_PREFIX"
else
  echo "ℹ️  Префикс не задан. Переименование образов производиться не будет."
fi

found=0
TMP_NEWTAGS="$(mktemp)"
> "$TMP_NEWTAGS"

for tarfile in "$IMG_DIR"/*.tar; do
  if [ -f "$tarfile" ]; then
    echo "➕ Импорт: $tarfile"
    LOAD_OUTPUT=$($CONTAINER_TOOL load -i "$tarfile")
    echo "$LOAD_OUTPUT"
    found=1

    # Переименовываем только если задан TARGET_PREFIX
    if [ -n "$TARGET_PREFIX" ]; then
      echo "$LOAD_OUTPUT" | grep -E "Loaded image(s)?: " | while read -r line; do
        IMGS=$(echo "$line" | sed -E 's/.*Loaded image(s)?: //')
        IFS=',' read -ra TAGS <<< "$IMGS"
        for ORIG_TAG in "${TAGS[@]}"; do
          ORIG_TAG=$(echo "$ORIG_TAG" | xargs)
          IMAGE_NAME_WITH_TAG=${ORIG_TAG##*/}
          IMAGE_NAME=${IMAGE_NAME_WITH_TAG%%:*}
          IMAGE_TAG=${IMAGE_NAME_WITH_TAG##*:}
          NEW_TAG="$TARGET_PREFIX/$IMAGE_NAME:$IMAGE_TAG"
          echo "🔄 $ORIG_TAG → $NEW_TAG"
          $CONTAINER_TOOL tag "$ORIG_TAG" "$NEW_TAG"
          echo "$NEW_TAG" >> "$TMP_NEWTAGS"
        done
      done
    fi
  fi
done

if [ "$found" -eq 0 ]; then
  echo "❗ В каталоге нет .tar файлов для импорта."
  rm -f "$TMP_NEWTAGS"
  exit 0
else
  echo "✅ Импорт$( [ -n "$TARGET_PREFIX" ] && echo " и переименование" ) завершены."
fi

# Если были переименования, спрашиваем про пуш
if [ -n "$TARGET_PREFIX" ] && [ -s "$TMP_NEWTAGS" ]; then
  read -p "👉 Запушить переименованные образы в реестр '$TARGET_PREFIX'? [Y/n]: " PUSH_ANSWER
  case "${PUSH_ANSWER,,}" in
    y|yes)
      while read -r TAG; do
        echo "🚀 Пушим $TAG"
        $CONTAINER_TOOL push "$TAG"
      done < "$TMP_NEWTAGS"
      echo "✅ Пуш завершён."
      ;;
    *)
      echo "ℹ️  Пуш отменён пользователем."
      ;;
  esac
fi

rm -f "$TMP_NEWTAGS"
