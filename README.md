# Rootless Docker Audit Script
Этот скрипт выполняет автоматизированный аудит системы на соответствие требованиям для работы Docker в режиме rootless (без root-доступа).

## Возможности
- Проверка, действительно ли Docker Engine работает в rootless-режиме
- Контроль пользователя, под которым запущен `dockerd`, и текущего пользователя оболочки
- Анализ конфигурации ядра (наличие опции `CONFIG_USER_NS`)
- Проверка файлов `/etc/subuid` и `/etc/subgid`
- Проверка наличия и корректных прав необходимых утилит (`slirp4netns`, `fuse-overlayfs`, `newuidmap`, `newgidmap`)
- Определение версии и типа cgroups (`v1` или `v2`)
- Диагностика поддержки user namespaces
- Проверка переменных окружения и Docker socket
- Контроль прав на критически важные файлы
- Итоговая таблица статусов и рекомендации по устранению проблем

## Использование
Выполните под тем же пользователем, что и rootless Docker (обычно НЕ root):

```bash
bash rootless-docker-audit.sh
```

---
# Docker Image Static Security Checker
Этот скрипт предназначен для статического анализа Docker-образов на предмет распространённых ошибок безопасности и несоответствий best practices. 

## Возможности
- Проверка пользователя по умолчанию (USER)
- Проверка базового дистрибутива (Red OS / Astra Linux / ALT Container)
- Проверка на distroless-образ
- Поиск SUID/SGID файлов
- Поиск su/sudo бинарей
- Поиск секретов (в названиях и содержимом файлов)
- Проверка запуска root-процессов в ENTRYPOINT/CMD
- Проверка разрешений на чувствительные каталоги (/etc, /var, /root, /home)
- Поиск устаревших или небезопасных библиотек (например, libc.so.5, openssl-1.0 и др.)

## Использование
```bash
./docker_image_sec_check.sh <image_name>

# где <image_name> — имя или ID вашего Docker-образа (например, myrepo/myimage:latest)
```

---
# Trivy JSON Report Pretty Printer
Этот скрипт облегчает разбор и анализ отчетов безопасности, сгенерированных [Trivy](https://github.com/aquasecurity/trivy) в формате JSON.  

## Возможности
- Поддержка Trivy JSON-отчетов для Docker-образов, контейнеров и файлов.
- Два режима: уязвимости (`vuln`) и misconfigurations (`config`).
- Цветная подсветка уровней критичности (CRITICAL, HIGH, MEDIUM, LOW, UNKNOWN).
- Фильтрация по минимальному уровню severity (`--min-severity`).
- Подсчет количества найденных проблем.
- Удобный, компактный табличный вывод.

## Использование
```bash
Usage: ./trivy-pretty.sh <config|vuln> <trivy-json-report.json> [--min-severity=LEVEL]

Modes:
  config     Show misconfigurations (policy violations)
  vuln       Show vulnerabilities

Options:
  --min-severity=LEVEL   Minimum severity to display (CRITICAL|HIGH|MEDIUM|LOW|UNKNOWN)
```

---
# Save Docker Images
Скрипт для автоматического скачивания Docker-образов и сохранения их в виде архивов.

## Возможности
- Принимает список Docker-образов через аргументы командной строки или через файл со списком.
- Скачивает (docker pull) и сохраняет (docker save) каждый образ в отдельный .tar архив.

## Использование
```bash
# Скачивание отдельных образов
./save_docker_images.sh ubuntu:22.04 nginx:1.25-alpine redis:7
```

```bash
# Скачивание из файла со списком
./save_docker_images.sh -f images.txt
```
```
# images.txt

ubuntu:22.04
nginx:1.25-alpine
redis:7
```