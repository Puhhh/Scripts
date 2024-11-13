#!/bin/bash

# Ввод базового URL
echo "Не забудь / на конце URL"
read -p "Введите базовый URL(без номера сегмента и токена): " base_url

# Ввод токена
read -p "Введите токен: " token

# Ввод количества сегментов
read -p "Введите количество сегментов для скачивания: " num_segments

# Цикл по количеству сегментов
for i in $(seq 1 $num_segments); do
    # Формирование полной ссылки
    full_url="${base_url}segment${i}.ts?token=${token}"
    
    # Имя файла для сохранения
    file_name="segment${i}.ts"
    
    # Скачивание файла
    echo "Скачивание ${file_name}..."
    curl -o $file_name $full_url
done

echo "Загрузка завершена!"
