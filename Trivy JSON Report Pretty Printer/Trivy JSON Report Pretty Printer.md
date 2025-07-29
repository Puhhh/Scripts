# Trivy JSON Report Pretty Printer
Скрипт облегчает разбор и анализ отчетов безопасности, сгенерированных [Trivy](https://github.com/aquasecurity/trivy) в формате JSON.  

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