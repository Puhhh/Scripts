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

### Конфигурационный файл
Вы можете задать параметры работы в конфиге audit.conf (или через переменную окружения AUDIT_CONFIG):
```
TRIVY_DB_URL="https://example.com/my-trivy-db.tar.gz"
```
- По умолчанию скрипт ищет файл audit.conf в текущей папке.
- Для явного указания конфига используйте переменную окружения:
```bash
AUDIT_CONFIG=/path/to/audit.conf ./docker_image_sec_check.sh <image_name>
```
### Требования
- docker
- trivy
- jq
- стандартные утилиты Unix: tar, grep, find, head, cut, tr, sed, awk

### Вывод результатов
- Все основные результаты — в консоли ([OK], [WARN], [FAIL])
- Если обнаружены уязвимости (любой уровень), подробный отчёт Trivy сохраняется в файл trivy_report_<image>.json в директории запуска скрипта