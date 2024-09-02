#!/bin/bash
#Переменные
USER_DB="postgres"
export PGPASSWORD="postgres"
DB_SCHEME="postgres"
COUNT_ROW=''
PATH_SCRIPT="/home/postgres/tnodes"
MAX_DF_SIZE_PERCENT=99

#Функция удаления IP-адреса из файла со списком серверов
function removeipaddr() {
        sed -i "/$1/d" $PATH_SCRIPT/ipaddr.txt
}

#Функция логгирования отключения серверов
function logger_expire_server() {
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') -- Hostname $1 ($2) disabled!\n\tUsed\tAvailable\tParted\n\t$3\t\t$4\t/mnt/sda: $5%\n\t$6\t\t$7\t/mnt/sda1: $8%\n" >> $PATH_SCRIPT/log/tnodes.log
}

#Проверка существования файла ipaddr.txt и создание директорий. (Первый запуск скрипта)
if [[ ! -e $PATH_SCRIPT/ipaddr.txt ]]; then
        touch $PATH_SCRIPT/ipaddr.txt
        if [[ ! -d $PATH_SCRIPT/log ]]; then
                mkdir $PATH_SCRIPT/log
        fi
        if [[ ! -d $PATH_SCRIPT/tmp ]]; then
                mkdir $PATH_SCRIPT/tmp
        fi
fi

#Проверка существования файла ipaddr.txt и вычисления количества IP-адресов серверов
if [[ -e $PATH_SCRIPT/ipaddr.txt ]]; then
        COUNT_ROW=$(cat $PATH_SCRIPT/ipaddr.txt | wc -l)
        if [[ $COUNT_ROW -eq 0 ]]; then
                psql -h localhost -t -U $USER_DB -d $DB_SCHEME -c "SELECT ip FROM table_servers WHERE available = true;" | sed -e '$d' > $PATH_SCRIPT/ipaddr.txt
        fi
fi
#Основные вычисления скрипта Проверка количества строк в файле ipaddr.txt. Получение доступного дискового пространства на удаленных серверах. Логгирование
if [[ $COUNT_ROW -ge 1 ]]; then
        for IP in $(cat $PATH_SCRIPT/ipaddr.txt); do
                #Подключение к удаленным серверам
                ssh user@$IP "df -h | grep /mnt/sda | sort && hostname" > $PATH_SCRIPT/tmp/df_nodes.txt


                HOSTNAME=$(cat $PATH_SCRIPT/tmp/df_nodes.txt | tail -1)
                SDA=$(cat $PATH_SCRIPT/tmp/df_nodes.txt | head -1 | awk '{print $5}' | sed 's/.$//')
                SDA1=$(cat $PATH_SCRIPT/tmp/df_nodes.txt | grep "/mnt/sda1" | awk '{print $5}' | sed 's/.$//')

                #Объявление переменных для метрик
                DF_REMOTE_SDA_SIZE=$(cat $PATH_SCRIPT/tmp/df_nodes.txt | head -1 | awk '{print $2}')
                DF_REMOTE_SDA_AVL=$(cat $PATH_SCRIPT/tmp/df_nodes.txt | head -1 | awk '{print $4}')
                DF_REMOTE_SDA_USED=$(cat $PATH_SCRIPT/tmp/df_nodes.txt | head -1 | awk '{print $3}')
                DF_REMOTE_SDA1_SIZE=$(cat $PATH_SCRIPT/tmp/df_nodes.txt | grep "/mnt/sda1" | awk '{print $2}')
                DF_REMOTE_SDA1_AVL=$(cat $PATH_SCRIPT/tmp/df_nodes.txt | grep "/mnt/sda1" | awk '{print $4}')
                DF_REMOTE_SDA1_USED=$(cat $PATH_SCRIPT/tmp/df_nodes.txt | grep "/mnt/sda1" | awk '{print $3}')


                if [[ ! -z $SDA ]] && [[ ! -z $SDA1 ]]; then
                        echo -e "$(date '+%Y-%m-%d %H:%M:%S') -- $HOSTNAME ($IP)\n\tSize\tUsed\tAvailable\tParted\n\t$DF_REMOTE_SDA_SIZE\t$DF_REMOTE_SDA_USED\t$DF_REMOTE_SDA_AVL\t\t/mnt/meta: $SDA%\n\t$DF_REMOTE_SDA1_SIZE\t$DF_REMOTE_SDA1_USED\t$DF_REMOTE_SDA1_AVL\t\t/mnt/meta1: $SDA1%\n" >> $PATH_SCRIPT/log/tnodes.log
                else
                        removeipaddr $IP
                fi


                if [[ $SDA -ge $MAX_DF_SIZE_PERCENT ]] || [[ $SDA1 -ge $MAX_DF_SIZE_PERCENT ]]; then
                        psql -h localhost -t -U $USER_DB -d $DB_SCHEME -c "UPDATE table_servers SET available = false WHERE ip = '$IP';" 2>&1 > /dev/null
                        logger_expire_store $HOSTNAME $IP $DF_REMOTE_SDA_AVL $DF_REMOTE_SDA_USED $SDA $DF_REMOTE_SDA1_AVL $DF_REMOTE_SDA1_USED $SDA1
                        removeipaddr $IP
                fi
        done
fi

unset PGPASSWORD
