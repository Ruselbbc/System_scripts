#!/bin/sh

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

# Если оба файла найдены, выводим сообщение об успешном завершении
echo "Все необходимые файлы найдены в каталоге /opt"

InstallSoft(){
echo "Обновление ОС"
apt update
echo "--------------------------------------"

echo "Установка apache2"
apt install apache2 apache2-dev -y   
echo "--------------------------------------"

echo "Установка PHP"
apt install php php-cli php-common php-dev php-gd php-imap php-ldap php-mbstring php-mysql php-opcache php-pspell php-xml php-zip php-amqp php-apcu php-pear -y
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
    unzip astra.zip
}

UpdateNginx(){
     rsync -av /opt/astra/nginx/ /etc/nginx/
     echo "127.0.0.1 push httpd" >> /etc/hosts
     systemctl stop apache2
     systemctl --now enable nginx
}

UpdatePHP(){
    cd /opt/astra/php.d/
    cat opcache.ini >> /etc/php/8.2/apache2/conf.d/bitrix.ini
    cat zbx-bitrix.ini >> /etc/php/8.2/apache2/conf.d/bitrix.ini
    mkdir /var/log/php
    chown -R www-data:www-data /var/log/php
}

UpdateApache(){
    rsync -av /opt/astra/apache2/ /etc/apache2/
    a2dismod --force autoindex
    a2enmod rewrite
    a2enmod php8.2
    systemctl --now enable apache2
}

UpdateMariaDB(){
    su -
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
    cd /opt
    npm install --omit=dev ./push-server-0.4.0.tgz
    #added 1 package in 8s
    #16 packages are looking for funding
    #run `npm fund` for details
    ln -sf /opt/node_modules/push-server/etc/push-server /etc/push-server
    cd /opt/node_modules/push-server
    cp etc/init.d/push-server-multi /usr/local/bin/push-server-multi
    mkdir /etc/sysconfig
    cp etc/sysconfig/push-server-multi  /etc/sysconfig/push-server-multi
    cp etc/push-server/push-server.service  /etc/systemd/system/
    ln -sf /opt/node_modules/push-server /opt/push-server
    cat <<EOF >> /etc/sysconfig/push-server-multi
    GROUP=www-data
    SECURITY_KEY="${PUSH_KEY}"
    RUN_DIR=/tmp/push-server
    REDIS_SOCK=/var/run/redis/redis.sock
EOF

    useradd -g www-data bitrix
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




PUSH_KEY=$(pwgen 24 1)

echo "Установка зависимостей завершена, не забудьте установить пароль в mysql_secure_installation"
