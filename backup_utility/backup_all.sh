#!/bin/bash

source "$(dirname $0)/init_backup.sh"


# Backup /etc
case "${BACKUP_MODE}" in "all"|"montly"|"weekly"|"daily"|"file"|"etc")
  log -t "Backup /etc"
  backup_tar "/etc"
  ;;
esac




# Backup /home, from command find,  mask '*.sh' '*.key'
case "${BACKUP_MODE}" in "all"|"montly"|"weekly"|"daily"|"file"|"home")
  log -t "Backup /home"
  backup_tar --cmd-file-list "find /home -type f -name '*.sh' -o -name '*.key'" "/home"
  ;;
esac


# Backup MySQL
case "${BACKUP_MODE}" in "all"|"montly"|"weekly"|"daily"|"sql"|"mysql")
  log -t "Backup MySQL"

  MYSQL_DB_USER="xxxxxx"
  MYSQL_DB_PASSWORD="XXXXXXXXXXXXXXXX"

  MYSQL_BACKUP_TARGET="${CUR_BACKUP_TARGET}/mysql"

  mkdir -p "${MYSQL_BACKUP_TARGET}"

  for i in $(mysql -u${MYSQL_DB_USER} -p${MYSQL_DB_PASSWORD} -e'show databases;' | grep -v information_schema | grep -v Database | grep -v performance_schema);
  do
    sql_file="${i}_$(date +%Y-%m-%d_%H-%M).sql"
    log -r "Backup DB ${i} "
    mysqldump --lock-tables -h localhost -u"${MYSQL_DB_USER}" -p"${MYSQL_DB_PASSWORD}" -f "${i}" > "${MYSQL_BACKUP_TARGET}/${sql_file}"
    tar czpPf "${MYSQL_BACKUP_TARGET}/backup_sql_${sql_file}.tgz" -C "${MYSQL_BACKUP_TARGET}" "${sql_file}"
    log "$(printf '(%s->%s)' $(get_size ${MYSQL_BACKUP_TARGET}/${sql_file}) $(get_size ${MYSQL_BACKUP_TARGET}/backup_sql_${sql_file}.tgz))"
    rm "${MYSQL_BACKUP_TARGET}/${sql_file}"
  done

  log -n 2 "Backup MYSQL Finish!"
  ;;
esac


# Backup PostgreSQL
case "${BACKUP_MODE}" in "all"|"montly"|"weekly"|"daily"|"sql"|"psql")
  log -t "Backup PostgreSQL"

  PG_BACKUP_TARGET="${CUR_BACKUP_TARGET}/postgresql"
  mkdir -p "${PG_BACKUP_TARGET}"
  chown postgres:postgres -R "${PG_BACKUP_TARGET}"

  for i in ""$(sudo -u postgres psql -q -c "SELECT datname FROM pg_database;" | sed -n 3,/\eof/p | grep -v строк\) | grep -v rows\) | grep -v template0 | grep -v '^$' | awk {'print $1'})""; do
    sql_file="${i}_$(date +%Y-%m-%d_%H-%M).sql"
    log -r "Backup DB ${i} "
    sudo -u postgres pg_dump "${i}" > "${PG_BACKUP_TARGET}/${sql_file}"
    tar czpPf "${PG_BACKUP_TARGET}/backup_sql_${sql_file}.tgz" -C "${PG_BACKUP_TARGET}" "${sql_file}"
    log "$(printf '(%s->%s)' $(get_size ${PG_BACKUP_TARGET}/${sql_file}) $(get_size ${PG_BACKUP_TARGET}/backup_sql_${sql_file}.tgz))"
    rm "${PG_BACKUP_TARGET}/${sql_file}"

  done

  log -n 2 "Backup PostgreSQL Finish!"
  ;;
esac


# Backup /www
case "${BACKUP_MODE}" in "all"|"montly"|"weekly"|"www")
  log -t "Backup WWW"
  for ONE_DIR in /var/www/*;do
    backup_tar --dst-subdir "www" "${ONE_DIR}"
  done
  ;;
esac


# Backup /otp
case "${BACKUP_MODE}" in "all"|"montly"|"weekly"|"opt")
  log -t "Backup opt"
  for ONE_DIR in /opt/*;do
    backup_tar --dst-subdir "opt" "${ONE_DIR}"
  done
  ;;
esac



# Report, and sync reserve
backup_finish


exit 0



