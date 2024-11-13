#!/bin/bash

# Проверяем, передан ли аргумент
if [ -z "$1" ]; then
    echo "Использование: $0 name.example.com"
    exit 1
fi

# Получаем URL из первого аргумента
url="$1"

# Извлекаем имя из URL (например, 'name' из 'name.example.com')
name=$(echo "$url" | cut -d. -f1)

# Генерация приватного ключа
openssl genpkey -algorithm RSA -out "${name}.key" -pkeyopt rsa_keygen_bits:2048

# Создание запроса на сертификат (CSR)
openssl req -new -key "${name}.key" -out "${name}.csr" -subj "/C=RU/ST=Moscow/L=Moscow/O=MyOrganization/OU=IT/CN=${url}"

# Создание файла расширений для сертификата
cat > "${name}.ext" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${url}
EOF

# Подписываем сертификат с использованием промежуточного CA
openssl x509 -req -in "${name}.csr" -CA ../Intermediate/intermediate.crt -CAkey ../Intermediate/intermediate.key -CAcreateserial -out "${name}.crt" -days 365 -sha256 -extfile "${name}.ext"

# Вывод результата
echo "Сертификат создан: ${name}.crt"
