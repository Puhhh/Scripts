# Image Security Checker
Скрипт предназначен для статического анализа Docker-образов на предмет распространённых ошибок безопасности и несоответствий best practices. 

## Возможности
- Проверка пользователя по умолчанию (USER)
- Проверка базового дистрибутива (Red OS / Astra Linux / ALT Container)
- Проверка на distroless-образ
- Поиск SUID/SGID файлов
- Поиск su/sudo бинарей
- Проверка запуска root-процессов в ENTRYPOINT/CMD
- Проверка разрешений на чувствительные каталоги (/etc, /var, /root, /home)

## Использование
```bash
./docker_image_sec_check.sh <image_name>

# где <image_name> — имя или ID вашего Docker-образа (например, myrepo/myimage:latest)
```
```bash
./docker_image_sec_check.sh -f images.txt

# где images.txt — файл, в котором каждый образ на своей строке
```