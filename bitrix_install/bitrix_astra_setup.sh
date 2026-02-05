#!/bin/bash

#Обязательно закидываем astra.zip с conf файлами в папку /opt.
#push-server-0.4.0.tgz тоже кидаем в /opt.

# Проверяем существование файлов
if [ ! -f /opt/astra.zip ]; then
    echo "Ошибка: файл astra.zip не найден в каталоге /opt"
    exit 1
fi

if [ ! -f /opt/push-server-0.4.0.tgz ]; then
    echo "Ошибка: файл push-server-0.4.0.tgz не найден в каталоге /opt"
    exit 1
fi

read -rp "Введите версию PHP (например 7.3 или 8.1): " PHP_VERSION

case "$PHP_VERSION" in
  7.3|7.4|8.0|8.1|8.2)
    echo "Будет использован PHP $PHP_VERSION"
    ;;
  *)
    echo "Ошибка: поддерживаются только версии 7.3, 7.4, 8.0, 8.1, 8.2"
    exit 1
    ;;
esac

# Если оба файла найдены, выводим сообщение об успешном завершении
echo "Все необходимые файлы найдены в каталоге /opt"

InstallSoft(){
echo "Обновление ОС"
apt update
echo "--------------------------------------"

echo "Устанавливаем зависимости unzip, rsync, pwgen если их нет"
apt install -y unzip rsync pwgen
echo "--------------------------------------"

echo "Установка apache2"
apt install apache2 apache2-dev -y   
echo "--------------------------------------"

echo "Установка PHP"
apt install \
  php$PHP_VERSION \
  php$PHP_VERSION-cli \
  php$PHP_VERSION-common \
  php$PHP_VERSION-dev \
  php$PHP_VERSION-gd \
  php$PHP_VERSION-imap \
  php$PHP_VERSION-ldap \
  php$PHP_VERSION-mbstring \
  php$PHP_VERSION-mysql \
  php$PHP_VERSION-opcache \
  php$PHP_VERSION-pspell \
  php$PHP_VERSION-xml \
  php$PHP_VERSION-zip \
  php$PHP_VERSION-amqp \
  php$PHP_VERSION-apcu \
  php-pear -y
echo "--------------------------------------"

echo "Установка Nginx"
apt install nginx -y
echo "--------------------------------------"

echo "Установка Mariadb"
apt -y install mariadb-server mariadb-client
echo "--------------------------------------"

echo "Node и NPM (Push-сервер) — версия 18.19.0"
apt install nodejs npm -y
echo "--------------------------------------"

echo "Redis — 7.0.15"
apt install redis -y
echo "--------------------------------------"
}

UnzipAstra(){
    cd /opt
    unzip -o astra.zip
}

UpdateNginx(){
     rsync -av /opt/astra/nginx/ /etc/nginx/
     grep -qE '^127\.0\.0\.1\s+push\s+httpd$' /etc/hosts || echo "127.0.0.1 push httpd" >> /etc/hosts
     systemctl stop apache2

     nginx -t || { echo "Ошибка: nginx конфиг невалиден, reload не выполнен"; exit 1; }
     
     systemctl --now enable nginx
     systemctl reload nginx
}

UpdatePHP(){
    PHP_CONF_DIR="/etc/php/$PHP_VERSION/apache2/conf.d"
    
    cd /opt/astra/php.d/
    #cat opcache.ini >> "$PHP_CONF_DIR/bitrix.ini"
    #cat zbx-bitrix.ini >> "$PHP_CONF_DIR/bitrix.ini"
    cat opcache.ini zbx-bitrix.ini > "$PHP_CONF_DIR/99-bitrix.ini"
    
    mkdir -p /var/log/php
    chown -R www-data:www-data /var/log/php
}

UpdateApache(){
    rsync -av /opt/astra/apache2/ /etc/apache2/
    a2dismod --force autoindex
    a2enmod rewrite
    a2enmod php$PHP_VERSION
    systemctl --now enable apache2
    apachectl -t || { echo "Ошибка: apache конфиг невалиден, reload не выполнен"; exit 1; }
    systemctl reload apache2
}

UpdateMariaDB(){
    rsync -av /opt/astra/mysql/ /etc/mysql/
    systemctl --now enable mariadb
    systemctl restart mariadb
    echo "Не забудьте запустить mysql_secure_installation для установки пароля! Что выбирать указано в комментариях скрипта!"
    #mysql_secure_installation
    #...
    #Switch to unix_socket authentication [Y/n] n
    #... skipping.
    #Change the root password? [Y/n] y
    #New password:
    #Re-enter new password:
    #Password updated successfully!
    #Reloading privilege tables..
    #... Success!
    #Remove anonymous users? [Y/n] y
    #... Success!
    #Disallow root login remotely? [Y/n] y
    #... Success!
}

UpdateRedis(){
    rsync -av /opt/astra/redis/redis.conf /etc/redis/redis.conf
    usermod -g www-data redis
    chown -R redis:www-data /etc/redis /var/log/redis /var/lib/redis
    [[ ! -d /etc/systemd/system/redis-server.service.d ]] && mkdir /etc/systemd/system/redis-server.service.d
    echo -e '[Service]\nGroup=www-data' > /etc/systemd/system/redis-server.service.d/custom.conf
    systemctl daemon-reload
    systemctl enable redis-server.service
    systemctl restart redis-server.service
}

InstallPushServer(){
    PUSH_KEY=$(pwgen 24 1)
    PUSH_CFG="/etc/sysconfig/push-server-multi"

    cd /opt
    npm install --omit=dev ./push-server-0.4.0.tgz
    #added 1 package in 8s
    #16 packages are looking for funding
    #run `npm fund` for details
    ln -sf /opt/node_modules/push-server/etc/push-server /etc/push-server
    cd /opt/node_modules/push-server
    cp etc/init.d/push-server-multi /usr/local/bin/push-server-multi
    mkdir -p /etc/sysconfig
    cp etc/sysconfig/push-server-multi  /etc/sysconfig/push-server-multi
    cp etc/push-server/push-server.service  /etc/systemd/system/
    ln -sf /opt/node_modules/push-server /opt/push-server
    #cat <<EOF >> /etc/sysconfig/push-server-multi
    #GROUP=www-data
    #SECURITY_KEY="${PUSH_KEY}"
    #RUN_DIR=/tmp/push-server
    #REDIS_SOCK=/var/run/redis/redis.sock
  
    grep -q '^GROUP=' "$PUSH_CFG" || echo 'GROUP=www-data' >> "$PUSH_CFG"
    grep -q '^RUN_DIR=' "$PUSH_CFG" || echo 'RUN_DIR=/tmp/push-server' >> "$PUSH_CFG"
    grep -q '^REDIS_SOCK=' "$PUSH_CFG" || echo 'REDIS_SOCK=/var/run/redis/redis.sock' >> "$PUSH_CFG"

    if grep -q '^SECURITY_KEY=' "$PUSH_CFG"; then
      sed -i "s|^SECURITY_KEY=.*|SECURITY_KEY=\"${PUSH_KEY}\"|" "$PUSH_CFG"
    else
      echo "SECURITY_KEY=\"${PUSH_KEY}\"" >> "$PUSH_CFG"
    fi
EOF

    id -u bitrix >/dev/null 2>&1 || useradd -g www-data bitrix
    [[ ! -d /var/log/push-server ]] && mkdir /var/log/push-server
    chown bitrix:www-data /var/log/push-server
    /usr/local/bin/push-server-multi configs pub
    /usr/local/bin/push-server-multi configs sub
    echo 'd /tmp/push-server 0770 bitrix www-data -' > /etc/tmpfiles.d/push-server.conf
    systemd-tmpfiles --remove --create
    sed -i 's|User=.*|User=bitrix|;s|Group=.*|Group=www-data|;s|ExecStart=.*|ExecStart=/usr/local/bin/push-server-multi systemd_start|;s|ExecStop=.*|ExecStop=/usr/local/bin/push-server-multi stop|' /etc/systemd/system/push-server.service
    systemctl daemon-reload
    systemctl --now enable push-server
}

InstallSoft
UnzipAstra
UpdateNginx
UpdatePHP
UpdateApache
UpdateMariaDB
UpdateRedis
InstallPushServer

echo "Установка зависимостей завершена, не забудьте установить пароль в mysql_secure_installation"
