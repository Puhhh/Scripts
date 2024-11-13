#!/bin/bash

# Проверка на наличие входного файла
if [ -z "$1" ]; then
  echo "Укажите файл для обработки"
  exit 1
fi

input_file="$1"

# Убираем точку в начале имени файла, если она есть
base_name=$(basename "$input_file")
if [[ "$base_name" == .* ]]; then
  base_name="${base_name#.}"
fi

output_file="${base_name%.*}-no_comments"

# Удаление комментариев и пустых строк
grep -v '^\s*#' "$input_file" | grep -v '^\s*$' > "$output_file"

# Сообщение пользователю
echo "Комментарии удалены."
echo "Новый файл: $output_file"
