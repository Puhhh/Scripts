
#!/bin/bash

# Проверка наличия аргумента
if [ -z "$1" ]; then
    echo "Использование: $0 <cert_name>"
    exit 1
fi

cert_name=$1

# Выполнение команд
echo "Извлечение сертификата..."
openssl pkcs12 -in "${cert_name}.pfx" -clcerts -nokeys -out "${cert_name}.crt"

echo "Извлечение зашифрованного ключа..."
openssl pkcs12 -in "${cert_name}.pfx" -nocerts -out "${cert_name}-encrypted.key"

echo "Дешифровка ключа..."
openssl rsa -in "${cert_name}-encrypted.key" -out "${cert_name}.key"

echo "Кодирование сертификата в base64..."
crt_base64=$(cat "${cert_name}.crt" | base64 | tr -d '\n')
echo "Сертификат (base64):"
echo "$crt_base64"

echo "Кодирование ключа в base64..."
key_base64=$(cat "${cert_name}.key" | base64 | tr -d '\n')
echo "Ключ (base64):"
echo "$key_base64"

echo "Удаление временных файлов..."
rm ${cert_name}*

echo "Готово!"
