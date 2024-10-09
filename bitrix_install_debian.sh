#!/bin/bash

function line {
    echo " "
    echo "===================================="
}

su - 
#Обновления системы
echo "Обновляю систему"
apt update && apt upgrade

line
#Отключение SELinux
echo "Отключаю SELINUX"
echo 'SELINUX=disabled' >> /etc/selinux/semanage.conf

line
#Reboot
Reboot

#Установка первых пакетов транспортировки шифрования и сертификтов
echo "Устанавливаю пакеты"
apt install -y lsb-release ca-certificates apt-transport-https software-properties-common gnupg2


#Блок установки репозитория и проброса ключа
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | \
    sudo tee /etc/apt/sources.list.d/sury-php.list
wget -qO - https://packages.sury.org/php/apt.gpg | \
    sudo apt-key add -
apt update

#Установка apache и php, nginx, mariadb, nodejs, redis
 apt install apache2 -y
 apt install php8.0 php8.0-cli \
    php8.0-common php8.0-gd php8.0-ldap \
    php8.0-mbstring php8.0-mysql \
    php8.0-opcache \
    php-pear php8.0-apcu php-geoip \
    php8.0-mcrypt php8.0-memcache\
    php8.0-zip php8.0-pspell php8.0-xml -y
apt install nginx -y
apt -y install mariadb-server mariadb-common
apt install nodejs npm -y
apt install redis -y

line

#Синхронизация nginx, если есть откуда стянуть (раскомментировать при необходимости):
#echo "Синхронизирую nginx"
#su -
#rsync -av debian/nginx/ /etc/nginx/

#line

#Блок вставки кода для nginx
cat << \EOF > /etc/nginx/nginx.conf
######################################### Конфигурация nginx
#Рабочий каталог для сайта - /var/www/html/bx-site.
#Конфигурация nginx сервера:
# /etc/nginx/nginx.conf                                       # основной конфигурационный файл
#            |_conf.d/upstreams.conf                         # конфигурация для upstream серверов: apache && push-server
#            |_conf.d/maps-composite_settings.conf           # параменные используемые для кеша
#            |_conf.d/maps.conf                              # дополнительные переменные
#            |_conf.d/http-add_header.conf                   # CORS заголовки
#            |_sites-available/*.conf                        # подключаем сайты
#                              |_default.conf                # сайт по умолчанию (настраиваем только 80 порт)
#                                    |_conf.d/bx_temp.conf   # конфигурация BX_TEMPORARY_FILES_DIRECTOR
#                                    |_conf.d/bitrix.conf    # дефолтная конфигурация сайта
#                              |_rtc.conf                    # проксирование запросов на push-server (публикация)
#Дефолтная конфигурация сайта:
# conf.d/bitrix.conf                                         # основный блоки со включенным по умолчанию кешем в файлах
#        |_conf.d/bitrix_general.conf                        # отдача статики, быстрая отдача для внешних хранилищ и прочее
#                |_conf.d/errors.conf                        # обработка ошибок
#                |_conf.d/im_subscrider.conf                 # проксирование запросов на push-server (получение)
#                |_conf.d/bitrix_block.conf                  # блокировки по умолчанию
#
######################################### Конфигурация nginx
user www-data www-data;

worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 2048;
    multi_accept on;
    use epoll;
}

http {
	include /etc/nginx/mime.types;
	default_type application/force-download;
	server_names_hash_bucket_size 128;

	# log formats
    log_format json escape=json
    '{'
	'"ru":"$remote_user",'
	'"ts":"$time_iso8601",'
	'"p":"$host",'
	'"rl":$request_length,'
	'"rm":"$request_method",'
	'"ru":"$request_uri",'
	'"st":"$status",'
   	'"bs":$bytes_sent,'
	'"ref":"$http_referer",'
	'"ua":"$http_user_agent",'
	'"rt":"$request_time",'
	'"urt":"$upstream_response_time",'
	'"uct":"$upstream_connect_time",'
	'"uad":"$upstream_addr",'
	'"us":"$upstream_status",'
	'"uid":"$cookie_qmb",'
	'"sslp":"$ssl_protocol",'
	'"sp":"$server_protocol"'
    '}';

    # backend upstream servers
    include conf.d/upstreams.conf;

    # common composite and file cache settings
    include conf.d/maps-composite_settings.conf;
    include conf.d/maps.conf;

    # add_header
    include conf.d/http-add_header.conf;

	# Enable logging
	access_log /var/log/nginx/access.log  json;

	sendfile			on;
	tcp_nopush			on;
	tcp_nodelay			on;

	client_max_body_size		1024m;
	client_body_buffer_size		4m;

	# Parameters for back-end request proxy
	proxy_connect_timeout		300;
	proxy_send_timeout		    300;
	proxy_read_timeout		    300;
	proxy_buffer_size		    64k;
	proxy_buffers			    8 256k;
	proxy_busy_buffers_size		256k;
	proxy_temp_file_write_size	10m;

	types_hash_max_size	4096;

	# Assign default error handlers
	error_page 500 502 503 504 /500.html;
	error_page 404 = /404.html;

	# Content compression parameters
	gzip				    on;
	gzip_proxied			any;
	gzip_static			    on;
	gzip_http_version		1.0;
	gzip_types			    application/x-javascript application/javascript text/css;
	include sites-available/*.conf;

}
\EOF

line

#Проверка на наличие папок nginx
if [ -e /etc/nginx/conf.d ]  then
        echo "Папка conf.d существует";
    else
        echo "Папки не существует. Создаю папку conf.d";
        mkdir /etc/nginx/conf.d;
    fi

if [ -e /etc/nginx/sites-available ]  then
        echo "Папка существует";
    else
        echo "Папки не существует. Создаю папку site-available";
        mkdir /etc/nginx/sites-available;
    fi

#Создаём и вписываем файлы внутри nginx
echo "Создаю и вписываю файл default.conf в /etc/nginx/site-available"
cat <<\EOF > /etc/nginx/site-available/default.conf
# Default website
server {

    listen 80 default_server;
    server_name _;
    server_name_in_redirect off;

    proxy_set_header	X-Real-IP        $remote_addr;
    proxy_set_header	X-Forwarded-For  $proxy_add_x_forwarded_for;
    proxy_set_header	Host $host;

    proxy_redirect ~^(http://[^:]+):\d+(/.+)$ $1$2;
    proxy_redirect ~^(https://[^:]+):\d+(/.+)$ $1$2;

    set $docroot		"/var/www/html/bx-site";

    index index.php;
    root "/var/www/html/bx-site";

    # BXTEMP - personal settings
    include conf.d/bx_temp.conf;

    # Include parameters common to all websites
    include conf.d/bitrix.conf;

}
\EOF

line

echo "Создаю и вписываю файл rtc.conf в /etc/nginx/site-available"
cat <<\EOF > /etc/nginx/site-available/rtc.conf
server {
    listen 127.0.0.1:8895 default_server;
    server_name _;

    access_log off;

    add_header "X-Content-Type-Options" "nosniff";

    location /bitrix/pub/ {
        # IM doesn't wait
        proxy_ignore_client_abort on;
        proxy_pass http://nodejs_pub;
    }

    include conf.d/im_subscrider.conf;

    location / {
    	deny all;
    }

}
\EOF

line

echo "Создаю и вписываю файл bitrix.conf в /etc/nginx/conf.d"
cat <<\EOF > /etc/nginx/conf.d/bitrix.conf 
# cache condition variable
set $usecache "";
if ($is_global_cache = 1)                     { set $usecache "${usecache}A"; }

# main config without processing cache pages
include conf.d/bitrix_general.conf;

# php file processing
location ~ \.php$ {

  set $cache_file "bitrix/html_pages$general_key@$args.html";

  # test file conditions
  if (-f "$docroot/bitrix/html_pages/.enabled") { set $usecache "${usecache}B"; }
  if (-f "$docroot/$cache_file")                { set $usecache "${usecache}C"; }
  
  # create rewrite if cache-file exists
  if ($usecache = "ABC" ) { rewrite .* /$cache_file last; }

  proxy_pass http://apache;
}

# directories page processing
location ~ /$ {
  
  set $cache_file "bitrix/html_pages$general_key/index@$args.html";

  # test file conditions
  if (-f "$docroot/bitrix/html_pages/.enabled") { set $usecache "${usecache}B"; }
  if (-f "$docroot/$cache_file")                { set $usecache "${usecache}C"; }

  # create rewrite if cache-file exists
  if ($usecache = "ABC" ) { rewrite .* /$cache_file last; }

  proxy_pass http://apache;
}

# Main location
location / {
  proxy_pass http://apache;
}
\EOF

echo "Создаю и вписываю файл bitrix_block.conf в /etc/nginx/conf.d"
cat <<\EOF > /etc/nginx/conf.d/bitrix_block.conf 
#
# block this locations for any installation
#

# ht(passwd|access)
location ~* /\.ht  { deny all; }

# repositories
location ~* /\.(svn|hg|git) { deny all; }

# bitrix internal locations
location ~* ^/bitrix/(modules|local_cache|stack_cache|managed_cache|php_interface) {
  deny all;
}

location ~* ^/bitrix/\.settings\.php {
    deny all;
}

# upload files
location ~* ^/upload/1c_[^/]+/ { deny all; }

# use the file system to access files outside the site (cache)
location ~* /\.\./ { deny all; }
location ~* ^/bitrix/html_pages/\.config\.php { deny all; }
location ~* ^/bitrix/html_pages/\.enabled { deny all; }
\EOF

echo "Создаю и вписываю файл bitrix_general.conf в /etc/nginx/conf.d"
cat <<\EOF > /etc/nginx/conf.d/bitrix_general.conf 
#
# Main configuration file for site with Bitrix CMS.
# It doesn't contain configuration for .php and / 
# as their treatment depends on the type of caching on the site:
# - general cache - default option
# - composite cache + file - can be enabled in the menu
# - composite cache + memcached -  can be enabled in the menu
#

# Assign error handler
include	conf.d/errors.conf;

# Include im subscrider handlers
include conf.d/im_subscrider.conf;

# Deny external access to critical areas
include conf.d/bitrix_block.conf;

# Intenal locations
location ^~ /upload/support/not_image	{ internal; }

# Cache location: composite and general site
location ~* @.*\.html$ {
  internal;
  # disable browser cache, php manage file
  expires -1y;
  add_header X-Bitrix-Composite "Nginx (file)";
}

# Player options, disable no-sniff
location ~* ^/bitrix/components/bitrix/player/mediaplayer/player$ {
  add_header Access-Control-Allow-Origin *;
}

# Process dav request on
# main company
# extranet
# additional departments
# locations that ends with / => directly to apache 
location ~ ^(/[^/]+)?(/docs|/workgroups|/company/profile|/bitrix/tools|/company/personal/user|/mobile/webdav|/contacts/personal).*/$ {
  proxy_pass http://apache;
}

# Add / to request
location ~ ^(/[^/]+)?(/docs|/workgroups|/company/profile|/bitrix/tools|/company/personal/user|/mobile/webdav|/contacts/personal) {

  set $addslash "";
  if (-d $request_filename)   { set $addslash "${addslash}Y"; }
  if ($is_args != '?')    { set $addslash "${addslash}Y"; }
  if ($addslash = "YY" )    { proxy_pass http://apache$request_uri/; }

  proxy_pass http://apache;
}

# Accept access for merged css and js
location ~* ^/bitrix/cache/(css/.+\.css|js/.+\.js)$ {
  expires 30d; 
  error_page 404 /404.html;
}

# Disable access for other assets in cache location
location ~* ^/bitrix/cache		{ deny all; }

# Excange and Outlook
location ~ ^/bitrix/tools/ws_.*/_vti_bin/.*\.asmx$	{ proxy_pass http://apache; }

# Groupdav
location ^~ /bitrix/groupdav.php 			{ proxy_pass http://apache; }

# Use nginx to return static content from s3 cloud storage
# /upload/bx_cloud_upload/<schema>.<backet_name>.<s3_point>.amazonaws.com/<path/to/file>
location ^~ /upload/bx_cloud_upload/ {

    location ~ ^/upload/bx_cloud_upload/(http[s]?)\.([^/:\s]+)\.(s3|s3-us-west-1|s3-eu-west-1|s3-ap-southeast-1|s3-ap-northeast-1)\.amazonaws\.com/([^\s]+)$ {
        internal;
        resolver 8.8.8.8;
        proxy_method GET;
        proxy_set_header	X-Real-IP		$remote_addr;
        proxy_set_header	X-Forwarded-For		$proxy_add_x_forwarded_for;
        proxy_set_header	X-Forwarded-Server	$host;
        #proxy_max_temp_file_size 0;
        proxy_pass $1://$2.$3.amazonaws.com/$4;
    }

    location ~ ^/upload/bx_cloud_upload/(http[s]?)\.([^/:\s]+)\.([^/:\s]+)\.([^/:\s]+)\.rackcdn\.com/([^\s]+)$ {
        internal;
        resolver 8.8.8.8;
        proxy_method GET;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Server $host;
        #proxy_max_temp_file_size 0;
        proxy_pass $1://$2.$3.$4.rackcdn.com/$5;
    }

    location ~ ^/upload/bx_cloud_upload/(http[s]?)\.([^/:\s]+)\.clodo\.ru\:(80|443)/([^\s]+)$ {
        internal;
        resolver 8.8.8.8;
        proxy_method GET;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Server $host;
        #proxy_max_temp_file_size 0;
        proxy_pass $1://$2.clodo.ru:$3/$4;
    }

    location ~ ^/upload/bx_cloud_upload/(http[s]?)\.([^/:\s]+)\.commondatastorage\.googleapis\.com/([^\s]+)$ {
        internal;
        resolver 8.8.8.8;
        proxy_method GET;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Server $host;
        #proxy_max_temp_file_size 0;
        proxy_pass $1://$2.commondatastorage.googleapis.com/$3;
    }

    location ~ ^/upload/bx_cloud_upload/(http[s]?)\.([^/:\s]+)\.selcdn\.ru/([^\s]+)$ {
        internal;
        resolver 8.8.8.8;
        proxy_method GET;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Server $host;
        #proxy_max_temp_file_size 0;
        proxy_pass $1://$2.selcdn.ru/$3;
    }

    location ~* .*$	{ deny all; }
}

# Static content
location ~* ^/(upload|bitrix/images|bitrix/tmp) { 
  if ( $upstream_http_x_accel_redirect = ''  ) {
          expires 30d;
  }
}

location  ~* \.(css|js|gif|png|jpg|jpeg|ico|ogg|ttf|woff|eot|otf|svg|woff2)$ {
  error_page 404 /404.html;
  expires 30d;
}

# Nginx server status page
location ^~ /nginx-status {
  stub_status on;
  allow 127.0.0.0/24;
  deny all;
}

# pub & online
# telephony and voximplant
location ~* ^/(pub/|online/|services/telephony/info_receiver.php|/bitrix/tools/voximplant/) {

    add_header X-Frame-Options '' always;
    location ~* ^/(pub/imconnector/|pub/imbot.php|services/telephony/info_receiver.php|bitrix/tools/voximplant/) {
        proxy_ignore_client_abort on;
        proxy_pass http://apache;
    }

    proxy_pass http://apache;
}

# Bitrix setup script
location ^~ ^(/bitrixsetup\.php)$ { proxy_pass http://apache; proxy_buffering off; }
\EOF

echo "Создаю и вписываю файл bx_temp.conf в /etc/nginx/conf.d"
cat <<\EOF > /etc/nginx/conf.d/bx_temp.conf 
# Settings BX_TEMPORARY_FILES_DIRECTORY
location ~* ^/bx_tmp_download/ {
    internal;
    rewrite /bx_tmp_download/(.+) /.bx_temp/default/$1 last;
}

location ~* ^/.bx_temp/default/ {
    internal;
    root /usr/share/nginx/html;
}
\EOF

echo "Создаю и вписываю файл errors.conf в /etc/nginx/conf.d"
cat <<\EOF > /etc/nginx/conf.d/errors.conf 
# Set error handlers
error_page 403 /403.html;
error_page 404 = @fallback;
error_page 500 /500.html;
error_page 502 /502.html;
error_page 503 /503.html;
error_page 504 /504.html;

# Custom pages for BitrixEnv errors
location ^~ /500.html	{ root /srv/www/htdocs/bitrixenv_error; }
location ^~ /502.html	{ root /srv/www/htdocs/bitrixenv_error; }
location ^~ /503.html	{ root /srv/www/htdocs/bitrixenv_error; }
location ^~ /504.html	{ root /srv/www/htdocs/bitrixenv_error; }
location ^~ /403.html	{ root /srv/www/htdocs/bitrixenv_error; }
location ^~ /404.html	{ root /srv/www/htdocs/bitrixenv_error; }
location @fallback	{ proxy_pass http://apache; }
\EOF

echo "Создаю и вписываю файл http-add_header.conf в /etc/nginx/conf.d"
cat <<\EOF > /etc/nginx/conf.d/http-add_header.conf 
add_header "X-Content-Type-Options" "nosniff";
add_header X-Frame-Options SAMEORIGIN;
\EOF

echo "Создаю и вписываю файл im_subscrider.conf в /etc/nginx/conf.d"
cat <<\EOF > /etc/nginx/conf.d/im_subscrider.conf
# Ansible managed
location ~* ^/bitrix/subws/ {
     access_log /var/log/nginx/im_access.log  json;
     error_log /var/log/nginx/im_error.log warn;

    proxy_pass http://nodejs_sub;
    # http://blog.martinfjordvald.com/2013/02/websockets-in-nginx/
    # 12h+0.5
    proxy_max_temp_file_size 0;
    proxy_read_timeout  43800;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $replace_upgrade;
    proxy_set_header Connection $connection_upgrade;
}

location ~* ^/bitrix/sub/ {
     access_log /var/log/nginx/im_access.log  json;
     error_log /var/log/nginx/im_error.log warn;


    rewrite ^/bitrix/sub/(.*)$ /bitrix/subws/$1 break;
    proxy_pass http://nodejs_sub;
    proxy_max_temp_file_size 0;
    proxy_read_timeout  43800;
}

location ~* ^/bitrix/rest/ {
     access_log /var/log/nginx/im_access.log  json;
     error_log /var/log/nginx/im_error.log warn;


    proxy_pass http://nodejs_pub;
    proxy_max_temp_file_size 0;
    proxy_read_timeout  43800;
}
\EOF

echo "Создаю и вписываю файл maps.conf в /etc/nginx/conf.d"
cat <<\EOF > /etc/nginx/conf.d/maps.conf
# if connection ti not set
map $http_upgrade $connection_upgrade {
  default upgrade;
  '' 'close';
}

map $http_upgrade  $replace_upgrade {
  default $http_upgrade;
  ''      "websocket";
}
\EOF

echo "Создаю и вписываю файл maps-composite_settings.conf в /etc/nginx/conf.d"
cat <<\EOF > /etc/nginx/conf.d/maps-composite_settings.conf
#################### compisite cache keys
## /path/to/asset             => /path/to/asset
## /path/to/asset/            => /path/to/asset
## /path/to/dir/index.php     => /path/to/dir
map $uri $composite_key {
  default                         $uri;
  ~^(/|/index.php|/index.html)$   "";
  ~^(?P<non_slash>.+)/$           $non_slash;
  ~^(?P<non_index>.+)/index.php$  $non_index;
  ~^(?P<non_index>.+)/index.html$ $non_index;
}

# disable composite cache if BX_ACTION_TYPE exists
map $http_bx_action_type $not_bx_action_type {
  default "0";
  ''      "1";
}

# disable composite cache if BX_AJAX
map $http_bx_ajax $not_bx_ajax {
  default "0";
  ''      "1";
}

# disable composite cache if method != GET
map $request_method $is_get {
  default "0";
  "GET"   "1";
}

# disable compisite cache if there next query string in agrs
# ncc
map $arg_ncc $non_arg_ncc {
  default "0";
  ''      "1";
}

# bxajaxid
map $arg_bxajaxid $non_arg_bxajaxid {
  default "0";
  ''      "1";
}

# sessid
map $arg_sessid $non_arg_sessid {
  default "0";
  ''      "1";
}

# test IE
map $http_user_agent $is_modern {
  default           "1";
  "~MSIE [5-9]"     "0";
}

# add common limit by uri path
map $uri $is_good_uri {
  default                 "1";
  ~^/bitrix/              "0";
  ~^/index_controller.php "0";
}

# not found NCC
map $cookie_BITRIX_SM_NCC $non_cookie_ncc {
  default     "0";
  ""          "1";
}

# complex test
# BITRIX_SM_LOGIN, BITRIX_SM_UIDH - hold values and BITRIX_SM_CC is empty
map $cookie_BITRIX_SM_LOGIN $is_bx_sm_login {
  default     "1";
  ""          "0";
}

map $cookie_BITRIX_SM_UIDH $is_bx_sm_uidh {
  default     "1";
  ""          "0";
}

map $cookie_BITRIX_SM_CC $is_bx_sm_cc {
  default     "1";
  "Y"         "0";
}

map "${is_bx_sm_login}${is_bx_sm_uidh}${is_bx_sm_cc}" $is_storedAuth {
  default     "1";
  "111"       "0";
}

# test all global conditions
map "${not_bx_action_type}${not_bx_ajax}${is_get}${non_arg_ncc}${non_arg_bxajaxid}${non_arg_sessid}${is_modern}${is_good_uri}${non_cookie_ncc}${is_storedAuth}" $is_global_composite {
  default     "1";
  ~0          "0";
}

##
#################### /compisite cache keys

#################### general cache setting
## /path/to/dir       => /path/to/dir/index
## /path/to/dir/      => /path/to/dir/index
## /path/to/file.php  => /path/to/php
map $uri $general_key {
  default                         $uri;
  ~^(?P<non_slash>.+)/$           $non_slash;
  ~^(?P<php_path>.+).php$         $php_path;
}

# if exists cookie PHPSESSID disable
map $cookie_PHPSESSID $non_cookie_phpsessid {
  default      "0";
  ''           "1";
}

# main condition for general cache
map "${is_get}${cookie_PHPSESSID}" $is_global_cache {
  default       "1";
  ~0            "0";
}
\EOF

echo "Создаю и вписываю файл upstreams.conf в /etc/nginx/conf.d"
cat <<\EOF > /etc/nginx/conf.d/upstreams.conf
# Apache/httpd server
upstream apache {
    server httpd:8090;
}

# Push/sub server
upstream nodejs_sub {
  ip_hash;
  keepalive 1024;
  server push:8010;
  server push:8011;
  server push:8012;
  server push:8013;
  server push:8014;
  server push:8015;
}

# Push/pub server
upstream nodejs_pub {
  ip_hash;
  keepalive 1024;
  server push:9010;
  server push:9011;
}
\EOF

line

echo "вписываю push httpd на localhost"
echo "127.0.0.1 push httpd" >> /etc/hosts

line

#Останавливаем apache перед запуском nginx
echo "Останавливаю apache"
systemctl stop apache2

line

echo "Запускаю nginx"
systemctl --now enable nginx

line

#Проверка папки mods-available;
echo "Конфигурирую mods-available;"

if [ -e /etc/php/8.0//mods-available]  then
        echo "Папка mods-available; существует";
    else
        echo "Папки не существует. Создаю папку mods-available;";
        mkdir /etc/php/8.0/mods-available;
    fi

echo "Создаю и вписываю файл opcache.ini в /etc/php/8.0/mods-available"
cat <<\EOF > /etc/php/8.0/mods-available/opcache.ini
zend_extension=opcache.so
opcache.enable=1
opcache.memory_consumption=1859
opcache.interned_strings_buffer=464
opcache.max_accelerated_files=100000
opcache.max_wasted_percentage=1
opcache.validate_timestamps=1
opcache.revalidate_freq=0
opcache.fast_shutdown=1
opcache.save_comments=1
opcache.load_comments=1
opcache.blacklist_filename=/etc/php.d/opcache*.blacklist
\EOF

echo "Создаю и вписываю файл zbx-bitrix.ini в /etc/php/8.0/mods-available"
cat <<\EOF > /etc/php/8.0/mods-available/zbx-bitrix.ini
display_errors = Off
error_reporting = E_ALL
error_log = '/var/log/php/error.log'

; Set some more PHP parameters
enable_dl = Off
short_open_tag = On
allow_url_fopen = On

# Security headers
mail.add_x_header = Off
expose_php = Off

; Change default values of important constants
max_input_vars = 10000
max_file_uploads = 100
max_execution_time = 300
post_max_size = 1024M
upload_max_filesize = 1024M
pcre.backtrack_limit = 1000000
pcre.recursion_limit = 14000
realpath_cache_size = 4096k

; Utf-8 support
default_charset = UTF-8

; Configure PHP sessions
session.entropy_length = 128
session.entropy_file = /dev/urandom
session.cookie_httponly = On

; Set directory for temporary files
memory_limit = 512M

date.timezone = UTC
\EOF

line

#Создаю линки для /etc/php/8.0/mods-available/zbx-bitrix.ini
ln -sf /etc/php/8.0/mods-available/zbx-bitrix.ini  /etc/php/8.0/apache2/conf.d/99-bitrix.ini
ln -sf /etc/php/8.0/mods-available/zbx-bitrix.ini  /etc/php/8.0/cli/conf.d/99-bitrix.ini

line

#Конфигурируем apache2
echo "Конфигурируем apache2"
echo "Проверяем папку apache2/sites-available"
if [ -e /etc/apache2/sites-available]  then
        echo "Папка sites-available существует";
    else
        echo "Папки не существует. Создаю папку sites-available";
        mkdir /etc/apache2/sites-available;
    fi

echo "Создаю и вписываю файл 000-default.conf в /etc/apache2/sites-available"
cat <<\EOF > /etc/apache2/sites-available/000-default.conf
ServerName redos
ServerAdmin webmaster@localhost

<VirtualHost *:8090>
DocumentRoot  /var/www/html/bx-site

ErrorLog ${APACHE_LOG_DIR}/error_log
LogLevel warn
   CustomLog ${APACHE_LOG_DIR}/access.log combined

<IfModule mod_rewrite.c>
	#Nginx should have "proxy_set_header HTTPS YES;" in location
	RewriteEngine On
	RewriteCond %{HTTP:HTTPS} =YES
	RewriteRule .* - [E=HTTPS:on,L]
</IfModule>

<Directory />
	Options FollowSymLinks
	AllowOverride None
</Directory>

<DirectoryMatch .*\.svn/.*>
       Require all denied
</DirectoryMatch>

<DirectoryMatch .*\.git/.*>
	 Require all denied
</DirectoryMatch>

<DirectoryMatch .*\.hg/.*>
	 Require all denied
</DirectoryMatch>

<Directory /var/www/html/bx-site>
	Options Indexes FollowSymLinks MultiViews
	AllowOverride All
	DirectoryIndex index.php index.html index.htm

       Require all granted

	</Directory>

	<Directory /var/www/html/bx-site/bitrix/cache>
		AllowOverride none
        Require all denied
	</Directory>

	<Directory /var/www/html/bx-site/bitrix/managed_cache>
		AllowOverride none
        Require all denied
	</Directory>

	<Directory /var/www/html/bx-site/bitrix/local_cache>
		AllowOverride none
        Require all denied
	</Directory>

	<Directory /var/www/html/bx-site/bitrix/stack_cache>
		AllowOverride none
        Require all denied
	</Directory>

	<Directory /var/www/html/bx-site/upload>
		AllowOverride none
		AddType text/plain php,php3,php4,php5,php6,phtml,pl,asp,aspx,cgi,dll,exe,ico,shtm,shtml,fcg,fcgi,fpl,asmx,pht
		php_value engine off
	</Directory>

	<Directory /var/www/html/bx-site/upload/support/not_image>
		AllowOverride none
        Require all denied
	</Directory>

	<Directory /var/www/html/bx-site/bitrix/images>
		AllowOverride none
		AddType text/plain php,php3,php4,php5,php6,phtml,pl,asp,aspx,cgi,dll,exe,ico,shtm,shtml,fcg,fcgi,fpl,asmx,pht
		php_value engine off
	</Directory>

	<Directory /var/www/html/bx-site/bitrix/tmp>
		AllowOverride none
		AddType text/plain php,php3,php4,php5,php6,phtml,pl,asp,aspx,cgi,dll,exe,ico,shtm,shtml,fcg,fcgi,fpl,asmx,pht
		php_value engine off
	</Directory>

</VirtualHost>
\EOF

line

echo "Создаю и вписываю файл ports.conf в /etc/apache2/"
cat <<\EOF > /etc/apache2/ports.conf
# If you just change the port or add more ports here, you will likely also
# have to change the VirtualHost statement in
# /etc/apache2/sites-enabled/000-default.conf
 
Listen 8090

# vim: syntax=apache ts=4 sw=4 sts=4 sr noet
\EOF

line

#Отключаем листинг каталогов Apache2
echo "Отключаем листинг каталогов Apache"
a2dismod --force autoindex

line

#Включаем модуль rewrite
echo "Включаем модуль rewrite" 
a2enmod rewrite

line

#Запускаем apache
echo "Запускаем apache" 
systemctl --now enable apache2

#Конфигурируем базу данных mariadb
echo "Конфигурируем БД"

if [ -e /etc/mysql/my-bx.d ]  then
        echo "Папка /etc/mysql/my-bx.d существует";
    else
        echo "Папки не существует. Создаю папку my-bx.d";
        mkdir /etc/mysql/my-bx.d;
    fi

echo "Создаю и вписываю файл zbx-custom.cnf в /etc/mysql/my-bx.d"
cat <<\EOF > /etc/mysql/my-bx.d/zbx-custom.cnf
[mysqld]
transaction-isolation = READ-COMMITTED
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
thread_cache_size = 4
\EOF

line

echo "Создаю и вписываю файл my.cnf в /etc/mysql/"
cat <<\EOF > /etc/mysql/my.cnf
# The MariaDB configuration file
#
# The MariaDB/MySQL tools read configuration files in the following order:
# 0. "/etc/mysql/my.cnf" symlinks to this file, reason why all the rest is read.
# 1. "/etc/mysql/mariadb.cnf" (this file) to set global defaults,
# 2. "/etc/mysql/conf.d/*.cnf" to set global options.
# 3. "/etc/mysql/mariadb.conf.d/*.cnf" to set MariaDB-only options.
# 4. "~/.my.cnf" to set user-specific options.
#
# If the same option is defined multiple times, the last one will apply.
#
# One can use all long options that the program supports.
# Run program with --help to get a list of available options and with
# --print-defaults to see which it would actually understand and use.
#
# If you are new to MariaDB, check out https://mariadb.com/kb/en/basic-mariadb-articles/

#
# This group is read both by the client and the server
# use it for options that affect everything
#
[client-server]
# Port or socket location where to connect
# port = 3306
socket = /run/mysqld/mysqld.sock

# Import all .cnf files from configuration directory
!includedir /etc/mysql/conf.d/
!includedir /etc/mysql/mariadb.conf.d/
!includedir /etc/mysql/my-bx.d/
\EOF

line

#Запуск сервиса mariadb

echo "Запуск сервиса mariadb"
systemctl --now enable mariadb
systemctl restart mariadb

line

#Далее устанавливаем БД как указано ниже
: '
mysql_secure_installation
...
Switch to unix_socket authentication [Y/n] n
 ... skipping.
Change the root password? [Y/n] y
New password:
Re-enter new password:
Password updated successfully!
Reloading privilege tables..
 ... Success!
Remove anonymous users? [Y/n] y
'

#Конфигурируем Redis
echo "Конфигурируем Redis"
echo "Создаю и вписываю файл redis.conf в /etc/redis/redis.conf"
cat <<\EOF > /etc/redis/redis.conf
unixsocket /var/run/redis/redis.sock

bind 127.0.0.1
port 6379
tcp-backlog 511
unixsocketperm 770
timeout 0
tcp-keepalive 300
daemonize yes
loglevel notice
databases 16
rdbcompression yes
rdbchecksum yes
appendonly no
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
lua-time-limit 5000
notify-keyspace-events ""
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
activerehashing yes
hz 10
aof-rewrite-incremental-fsync yes
maxmemory-policy allkeys-lru
\EOF

line 

echo "Меняем конфиг, делаем директорию"

usermod -g www-data redis
chown root:www-data /etc/redis/ /var/log/redis/
[[ ! -d /etc/systemd/system/redis.service.d ]] && mkdir /etc/systemd/system/redis.service.d
echo -e '[Service]\nGroup=www-data' > /etc/systemd/system/redis.service.d/custom.conf
systemctl daemon-reload

line

echo "Запускаем redis"
systemctl enable redis-server.service
systemctl restart redis-server.service

line

#Конфигурация push-server

#Скачиваем и устанавливаем push-server
echo "Переходим в /opt, скачиваем и устанавливаем push-server"
cd /opt
wget https://repo.bitrix.info/vm/push-server-0.3.0.tgz
npm install --production ./push-server-0.3.0.tgz

#Должно закончиться так:
: '
added 1 package, and audited 145 packages in 13s
16 packages are looking for funding
  run `npm fund` for details '

line

# Создаём символ линк
ln -sf /opt/node_modules/push-server/etc/push-server /etc/push-server

#Копируем конфигурационные файлы в основной конфиг
echo "Копируем конфигурационные файлы в основной конфиг"

cd /opt/node_modules/push-server
cp etc/init.d/push-server-multi /usr/local/bin/push-server-multi
mkdir /etc/sysconfig
cp etc/sysconfig/push-server-multi  /etc/sysconfig/push-server-multi
cp etc/push-server/push-server.service  /etc/systemd/system/
ln -sf /opt/node_modules/push-server /opt/push-server

line


