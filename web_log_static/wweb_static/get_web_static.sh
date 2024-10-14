#!/bin/bash

#
# Считываем кол-во запросов по IP адресам из лога Nginx
# Без параметров количество запосов по IP, запрашиваемых URL, ошибках, http коды ответа за последние 60 минут
# Опционально 1 параметром - время за которое выводим данные лога, в минутах
#

#Делаем страховку на повторный вызов
LOCKFILE=/tmp/get_static_web

already_locked() {
  echo "lock is already held, exiting"
  exit 1
}

exec 200>$LOCKFILE
flock -n 200 || already_locked 
echo "lock obtained, proceeding"
sleep 5
echo "releasing lock, done"

#Создаём нужные файлы для логов (введите другой путь, если хотите использовать другую директорию)
path_to_log="$HOME/system_scripts/test_zone/log_web.txt";
path_to_static="$HOME/system_scripts/test_zone/static_web.txt";

export LC_ALL=en_US.UTF-8
export LC_NUMERIC=C

function line {
    echo " "
    echo "===================================="
}

#Проверка на целое число
re='^[0-9]+$'
if ! [[ $1 =~ $re ]] ; then
   echo "error: Not a integer" >&2; exit 1
fi

if [ -z "$1" ]
then
    MNT="60"    #За какое количество минут. По умолчанию 60
else
    MNT="$1"
fi
 
# Максимальное количество строк в выводе
# По умолчанию 100
CNT="100"
 
TMS="$(date +%s)"
STR=""
STX=""
PYT=""

let "SEK = MNT * 60"
let "EXP = TMS - SEK"
let "PYT = $MNT / 60"

while :
do   
     
    STR="$STR$STX$(date -d @$EXP +'%d/%h/%Y:%H:%M')"
    let "EXP = EXP + 60"
    STX="|"
     
    if [ "$EXP" == "$TMS" ]
    then
        break
    fi
         
done

# shellcheck disable=SC2088
if [[ -f $path_to_log ]]; then
        echo "Файл найден"
    else
        echo "Файл не найден, создаю файл log_web.txt"
        touch $path_to_log
    fi

# shellcheck disable=SC2088
if [[ -f $path_to_static ]]; then
        echo "Файл найден"
    else
        echo "Файл не найден, создаю файл static_web.txt"
        touch $path_to_static
    fi

echo "Выгружаю ip адреса"
echo "IP адреса" > $path_to_log
line >> $path_to_log 
echo "$(cat /var/log/nginx/access.log | grep -E $STR | awk '{print "ip: "$1}'| sort | uniq -c | sort -nr | head -n$CNT)" >> $path_to_log                 #Показать пулл айпи адресов
line

echo "Выгружаю запрашиваемые URL"
echo "URL" >> $path_to_log
line >> $path_to_log 
echo "$(cat /var/log/nginx/access.log | grep -E $STR | awk '{print "URL: "$10}'| sort | uniq -c | sort -nr | head -n$CNT)" >> $path_to_log               #Показать пулл запрашиваемых URL адресов
line

python get_log.py /var/log/nginx/error.log $path_to_static $PYT
echo "Выгружаю ошибки"
echo "Errors" >> $path_to_log   
line >> $path_to_log 
cat $path_to_static >> $path_to_log                                                                                                                      #Показать ошибки веб-сервиса

line
echo "Выгружаю response codes"  
echo "Response codes" >> $path_to_log 
line >> $path_to_log
echo "$(cat /var/log/nginx/access.log | grep -E $STR | awk '{print "response code: "$8}'| sort | uniq -c | sort -nr | head -n$CNT)" >> $path_to_log      #Показать коды ответа http

#Расскоментировать блок отправки email, если он нужен.
#cat $path_to_log | mail -s "Test title" ruslan_lutov@otus.ru
