#!/bin/bash

#The function separates lines during code execution

function line {
    echo " "
    echo "===================================="
}

# A variable for displaying the current date
date_name=$(date '+%Y-%m-%d');

# We go through each archive in txt format
for file in /home/bitrix/www/*_log.txt; do

    echo "Перемещаю файл: $file";
    cp $file '/home/bitrix/www/php_archive_log';
line;

done

cd '/home/bitrix/www/php_archive_log' && for file in ./*_log.txt; do
    if [ "$file" != "*.bz2" ]; then
        echo  "Архивирую файл: ${file}"; 
        tar -cjvf $file."$date_name".tar.bz2 $file;
    line;
        echo "Удаляю архивируемый исходник: $file";
        rm -r $file;
        if [ -e $file ]; then
            echo "Исходник не удален"
        else
            echo "Исходник удалён"
        fi
    else
        echo "Файлов для архивирования не обнаружено!"
    fi
line;
done

echo "Чистим исходные логи";

for file in /home/bitrix/www/*_log.txt; do

    echo "Лог очищен $date_name " > $file;

done
# change the rights to the folder to the bitrix user
chown bitrix:bitrix -R /home/bitrix/www/php_archive_log
