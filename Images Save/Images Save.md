# Save Docker Images
Скрипт для автоматического скачивания Docker-образов и сохранения их в виде архивов.

## Возможности
- Принимает список Docker-образов через аргументы командной строки или через файл со списком.
- Позволяет задать нужную платформу для скачивания образов (по умолчанию linux/amd64).
- Скачивает (docker pull) и сохраняет (docker save) каждый образ в отдельный .tar архив.

## Использование
```bash
# Скачивание отдельных образов
./save_docker_images.sh ubuntu:22.04 nginx:1.25-alpine
./save_docker_images.sh -p linux/amd64 ubuntu:22.04 nginx:1.25-alpine
```

```bash
# Скачивание из файла со списком
./save_docker_images.sh -f images.txt

# images.txt
# ubuntu:22.04
# nginx:1.25-alpine
# redis:7
```