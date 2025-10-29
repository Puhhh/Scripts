# JSON Report Pretty
Скрипт облегчает разбор и анализ отчетов безопасности, сгенерированных [Trivy](https://github.com/aquasecurity/trivy) или [Grype](https://github.com/anchore/grype) в формате JSON.  

## Возможности
- Поддержка Trivy & Grype JSON-отчетов для Docker-образов, контейнеров и файлов.
- Два режима: уязвимости (`vuln`) и misconfigurations (`config`).
- Цветная подсветка уровней критичности (CRITICAL, HIGH, MEDIUM, LOW, NEGLIGIBLE, UNKNOWN).
- Фильтрация по минимальному уровню severity (`--min-severity`).
- Подсчет количества найденных проблем.
- Удобный, компактный табличный вывод.

## Использование
```bash
Usage: ./json-report-pretty.sh <config|vuln> <json-report.json> [--min-severity=LEVEL]

Modes:
  config     Show misconfigurations (policy violations)
  vuln       Show vulnerabilities

Options:
  --min-severity=LEVEL   Minimum severity to display (CRITICAL|HIGH|MEDIUM|LOW|NEGLIGIBLE|UNKNOWN)
```