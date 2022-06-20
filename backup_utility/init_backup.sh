#!/bin/bash

# Задача: Создавать бекапы указанных объектов.
# Бекап создается и хранится в указанной папке, и если требуется, копируется на резервный диск, для бекапов.
# В основной папке бекапы храняться за каждое 1 и 15 числа - месячные, каждое воскресенье - недельные, и ежедневные.
# На резервном диске бекапы храняться дольше. Период хранения для каждого режима настраивается отдельно.
#
# (+) Каждое 1 и 15 число месяца каталог для бекапов - montly, в воскресенье - weekly, в остальные дни - daily (в порядке уменьшения приоритета).
# (+) Логирование
# (-) Ролтация логов
# (+) Уведомление по email
# (+) Уведомление через telegramm с приложеным лог-файлом
#
# (+) Каталог /etc бекапится каждый день.
# (+) Каталог /home/*.sh бекапится каждый день
# (+) Каталог /www бекапится каждое воскресенье.
# (+) Базы mysql каждый день.
# (+) Базы postgreSQL каждый день.
#
#
# (+) Папка с бекапами целиком копируется в резервное место
# (+) Удалять старые файлы из каталога бекапов
# (+) Удалять старые файлы из резервного каталога бекапов
# (+) Зашедулить скрипт в cron



# Основной каталог для бекапов
BACKUP_TARGET="/home/backup"
# Резервный каталог для бекапов (disk2tb_backup)
BACKUP_RESERV="/mnt/disk2tb_backup"

BACKUP_MODE="daily"

# Срок хранения бекапов
BACKUP_EXPIRED_DAILY="30"
BACKUP_EXPIRED_WEEKLY="90"
BACKUP_EXPIRED_MONTLY="365"
BACKUP_RESERV_EXPIRED_DAILY="90"
BACKUP_RESERV_EXPIRED_WEEKLY="365"
BACKUP_RESERV_EXPIRED_MONTLY="1800"


# Каталог с логами
LOG_DIR="${BACKUP_TARGET}/logs"
LOG_FILE="${LOG_DIR}/Backup_log_$(date +%Y-%m-%d_%H-%M-%S).log"
LOG_ERROR_FILE="${BACKUP_TARGET}/Backup_error_log_$(date +%Y-%m-%d).log"

# (-) Ротация логов
#/usr/sbin/logrotate -f /etc/logrotate.conf

CUR_DAY="$(date +%d)"
CUR_DAY_WEEK="$(date +%u)"

CUR_DATA="$(date +%Y-%m-%d)"


LAST_ERROR_CODE="0"
LAST_ERROR_MSG=""

REPORT_MAIL="1"

BACKUP_TIME_START="$(gawk 'BEGIN{print systime()}')";

mkdir -p "${LOG_DIR}"


# Задать каталог для сохранения бекапов
# Входной параметр: <Reset - восстановить каталог по умолчанию | Или наименование каталога>
change_backup_target(){
  if [[ -z "${1}" ]] || [[ "${1^^}" == "RESET" ]] || [[ "${1^^}" == "DEFAULT" ]];then
    if [[ "${CUR_DAY}" -eq 1 ]] || [[ "${CUR_DAY}" -eq 15 ]]  ; then
      # Если сегодня 1е или 15 число месяца, то бекап месячный.
      BACKUP_MODE="montly"
    else
      if [[ "${CUR_DAY_WEEK}" -eq 7 ]]  ; then
        # Если сегодня воскресенье, то бекап недельный (weekly).
        BACKUP_MODE="weekly"
      else
        # Иначе, по умолчанию бекап считается дневным (Daily).
        BACKUP_MODE="daily"
      fi
    fi
  else
    BACKUP_MODE="${1}"
  fi

  log "Backup mode: ${BACKUP_MODE}"
  CUR_BACKUP_TARGET="${BACKUP_TARGET}/${BACKUP_MODE}/${CUR_DATA}"
  log -n 2 "Backup target: ${CUR_BACKUP_TARGET}"
  mkdir -p "${CUR_BACKUP_TARGET}"
}

# Записать строку лога, и добавлениени n пустых строк.
# in param <text> [newline_count=0]
log(){
  NEWLINES="-1"
  IS_TITLE="0"
  MSG=""
  ERROR="0"
  PIPE_MSG=""

  if [[ -z "${LOG_FILE}" ]]; then
    LOG_FILE="$(dirname ${0})/$(basename ${0}).log"
  fi
  if [[ -z "${LOG_ERROR_FILE}" ]]; then
    LOG_ERROR_FILE="$(dirname ${0})/$(basename ${0})_error.log"
  fi

  while [ -n "$1" ];do
    case "$1" in
      -r | --noreturn ) NEWLINES="0";;
      -e | --error    ) ERROR="1"; ;;
      -n | --newlines ) NEWLINES="${2}"; shift ;;
      -t | --title    ) IS_TITLE="1";;
      -p | --pipe-msg ) PIPE_MSG="${2}"; shift ;;
      --) shift; break ;;
      * )  MSG="${1}";;
    esac
    shift
  done

  if [[ "${IS_TITLE}" -eq "0" ]];then
    if [[ "${ERROR}" -eq "0" ]];then
      if [[ "${NEWLINES}" -eq "0" ]];then
        echo -n "${MSG}" | tee -a "${LOG_FILE}"
      else
#        echo "${MSG}" | tee -a "${LOG_FILE}"
#        while read -t 0.1 -r log_line && [[ -n "$log_line" ]]; do
        ONE_PRINT="0"
        while read -t 0.1 -r log_line; do
          if [[ "${ONE_PRINT}" -eq "0" ]]; then
            if [[ -n "${MSG}" ]];then
              echo "${MSG}" | tee -a "${LOG_FILE}"
            fi
            ONE_PRINT="1"
          fi
          echo "${PIPE_MSG}${log_line}" | tee -a "${LOG_FILE}"
        done

        if [[ "${ONE_PRINT}" -eq "0" ]]; then
          echo "${MSG}" | tee -a "${LOG_FILE}"
          ONE_PRINT="1"
        fi


      fi
    else
      # Запись в лог информации об ошибках, и добавлениени n пустых строк. "${LOG_ERROR_FILE}"
      if [[ "${NEWLINES}" -eq "0" ]];then # "${LOG_ERROR_FILE}"
        echo -n "ERROR: ${MSG}" | tee -a "${LOG_FILE}" "${LOG_ERROR_FILE}"
      else
        echo "ERROR: ${MSG}" | tee -a "${LOG_FILE}" "${LOG_ERROR_FILE}"
      fi
    fi
  else
    # Записать в лог заголовка (банер), оформленного в символы #
    MSG="# ${MSG} #"
    EDGE="$(echo ${MSG} | sed 's/./#/g')"
    echo "${EDGE}" | tee -a "${LOG_FILE}"
    echo "${MSG}"  | tee -a "${LOG_FILE}"
    echo "${EDGE}" | tee -a "${LOG_FILE}"
  fi

  if [[ "${NEWLINES}" -gt "0" ]];then
    for i in $(seq 1 "${NEWLINES}"); do
      if [[ "${ERROR}" -eq "0" ]];then
        echo "" | tee -a "${LOG_FILE}"
      else
        echo "" | tee -a "${LOG_FILE}" "${LOG_ERROR_FILE}"
     fi
    done
  fi
}

# in param <source> [masks]
backup_tar(){
  if [[ -n "${1}" ]]; then

    MSG=""
    BKP_DST_SUBDIR=""
    FILE_LIST_CMD=""
    BKP_DST_NAME_CUSTOME=""
    BKP_DST_NAME_ADD_BEFO=""
    BKP_DST_NAME_ADD_AFTE=""
    BKP_CHANGE_DIR="0"
    BKP_TAR_ADD_CMD=""


    while [ -n "$1" ];do
      case "$1" in
        -C | --change-dir )    BKP_CHANGE_DIR="1" ;;
        -s | --dst-subdir )    BKP_DST_SUBDIR="${2}"; shift ;;
        -c | --cmd-file-list ) FILE_LIST_CMD="${2}"; shift ;;
        -a | --add-name-afte ) BKP_DST_NAME_ADD_AFTE="${2}"; shift ;;
        -b | --add-name-befo ) BKP_DST_NAME_ADD_BEFO="${2}"; shift ;;
        -n | --custom-name   ) BKP_DST_NAME_CUSTOME="${2}"; shift ;;
        --) shift; break ;;
        * )  MSG="${1}";;
      esac
      shift
    done

    TIME_START="$(gawk 'BEGIN{print systime()}')";

    BKP_TIME="$(date +%Y-%m-%d_%H-%M-%S)"
    BKP_SRC="$(realpath ${MSG})"
    BKP_DST_PATH="${CUR_BACKUP_TARGET}"

    if [[ -n "${BKP_DST_SUBDIR}" ]]; then
      BKP_DST_PATH="${CUR_BACKUP_TARGET}/${BKP_DST_SUBDIR}"
      mkdir -p "${BKP_DST_PATH}"
    fi

    if [[ -n "${BKP_DST_NAME_CUSTOME}" ]]; then
      BKP_DST_NAME="${BKP_DST_NAME_CUSTOME}"
    else
      BKP_DST_NAME="$(basename ${BKP_SRC})"
      if [[ -n "${BKP_DST_NAME_ADD_AFTE}" ]]; then BKP_DST_NAME="${BKP_DST_NAME_ADD_AFTE}_${BKP_DST_NAME}"; fi
      if [[ -n "${BKP_DST_NAME_ADD_BEFO}" ]]; then BKP_DST_NAME="${BKP_DST_NAME}_${BKP_DST_NAME_ADD_BEFO}"; fi
    fi


    BKP_DST="${BKP_DST_PATH}/backup_${BKP_DST_NAME}_${BKP_TIME}.tgz"

    log "Source: ${BKP_SRC}"
    log "Destination: ${BKP_DST}"

    if [[ -n "${BKP_DST_SUBDIR}" ]];        then log "Destination subdir: ${BKP_DST_SUBDIR}";    fi
    if [[ -n "${BKP_DST_NAME_CUSTOME}" ]];  then log "Destination custom name: ${BKP_DST_NAME_CUSTOME}";    fi
    if [[ -n "${BKP_DST_NAME_ADD_AFTE}" ]]; then log "Destination add afte name: ${BKP_DST_NAME_ADD_AFTE}"; fi
    if [[ -n "${BKP_DST_NAME_ADD_BEFO}" ]]; then log "Destination add befo name: ${BKP_DST_NAME_ADD_BEFO}"; fi




    if [[ "${BKP_CHANGE_DIR}" -eq "1" ]]; then
      BKP_TAR_ADD_CMD=" -C ${BKP_SRC%$(basename ${BKP_SRC})} "
      BKP_SRC="$(basename ${BKP_SRC})"
      log "Tar add option: ${BKP_TAR_ADD_CMD}"
    fi



    if [[ -n "${FILE_LIST_CMD}" ]]; then
      # Архивация по кастомному списку файлов
      log "File custom list CMD: ${FILE_LIST_CMD}"
      BACKUP_CMD="${FILE_LIST_CMD} 2>&1 | tar fczpP ${BKP_DST} -T - 2>&1"
    else
      # Архивация каталога целиком
      BACKUP_CMD="tar fczpP ${BKP_DST} ${BKP_TAR_ADD_CMD} ${BKP_SRC} 2>&1"
    fi

    log "Backup CMD: ${BACKUP_CMD}"
    result="$(eval ${BACKUP_CMD} 2>&1)"

    rc=$?

    BKP_SIZE="$(du -sh ${BKP_DST} | cut -f 1)"
    TIME_END="$(gawk 'BEGIN{print systime()}')";
    TIME_RESULT="$(($TIME_END-$TIME_START))";

    log "Exit code: ${rc}"
    log "Time: ${TIME_RESULT}sec"
    log "Size: ${BKP_SIZE}"
    if [[ -n "${BKP_SRC_SIZE}" ]];then
      log "SrcSize: ${BKP_SRC_SIZE}"
      unset BKP_SRC_SIZE
    fi;

    if [[ -n "${LOG_APPEND_MESSAGE}" ]];then
      log "${LOG_APPEND_MESSAGE}"
      unset LOG_APPEND_MESSAGE
    fi;

    if [[ "${rc}" -ne "0" ]];then
      LAST_ERROR_CODE="${rc}"
      LAST_ERROR_MSG="${result}"
      log --error "Backup tar $(date +%Y-%m-%d_%H-%M-%S)"
      log --error "Mode: ${BACKUP_MODE}"
      log --error "Source: ${BKP_SRC}"
      log --error "Destin: ${BKP_DST}"
      log --error "Exit code: ${rc}"
      log --error "Time: ${TIME_RESULT}"
      log --error "Backup CMD:"
      log --error "${BACKUP_CMD}"
      log --error "Result:"
      log --error -n 2 "${result}"

    else
      log -n 1
    fi
  else
    #log "Backup tar: Empty input parametr: <source> [masks]" 2
    log --error -n 2 "ERROR: Backup tar: Empty input parametr: <source> [bash command for file list]"
  fi;

}


get_size(){
  if [[ -n "${1}" ]];then
    if [[ -e "${1}" ]];then
      echo "$(du -sh ${1} | cut -f 1)"
    fi
  fi
}


backup_finish(){
#  log "Backup finish!"

  if [[ "${LAST_ERROR_CODE}" -gt 0 ]]; then
    SEND_MSG_TITLE="Backup error!"
  else
    SEND_MSG_TITLE="Backup finish!"
  fi


# Sync BACKUP_TARGET and BACKUP_RESERV
  if [[ -n "${BACKUP_RESERV}" ]]; then
    cp -fru "${BACKUP_TARGET}" "${BACKUP_RESERV}"
  fi

# Remove old backup
  log -t "Remove old backup"

  case "${BACKUP_MODE}" in
    "daily")
      remove_old_backup_one "${BACKUP_TARGET}/daily" "${BACKUP_EXPIRED_DAILY}"
      remove_old_backup_one "${BACKUP_RESERV}/backup/daily" "${BACKUP_RESERV_EXPIRED_DAILY}"
    ;;
    "weekly")
      remove_old_backup_one "${BACKUP_TARGET}/weekly" "${BACKUP_EXPIRED_WEEKLY}"
      remove_old_backup_one "${BACKUP_RESERV}/backup/weekly" "${BACKUP_RESERV_EXPIRED_WEEKLY}"
    ;;
    "montly")
      remove_old_backup_one "${BACKUP_TARGET}/montly" "${BACKUP_EXPIRED_MONTLY}"
      remove_old_backup_one "${BACKUP_RESERV}/backup/montly" "${BACKUP_RESERV_EXPIRED_MONTLY}"
    ;;
  esac

  log "Delete empty dir"
  find "${BACKUP_TARGET}" -type d -empty -print -delete | log
  find "${BACKUP_TARGET}" -type d -empty -print -delete | log -n 1


  CUR_BACKUP_SIZE="$(du -sh ${CUR_BACKUP_TARGET} | cut -f 1)"
  BACKUP_TARGET_SIZE="$(du -sh ${BACKUP_TARGET} | cut -f 1)"
  BACKUP_RESERV_SIZE="$(du -sh ${BACKUP_RESERV} | cut -f 1)"

  BACKUP_TIME_END="$(gawk 'BEGIN{print systime()}')";
  BACKUP_TIME_RESULT="$(($BACKUP_TIME_END-$BACKUP_TIME_START))sec";

  SEND_MSG="${SEND_MSG_TITLE}
Backup mode: ${BACKUP_MODE}
Backup time: ${BACKUP_TIME_RESULT}
Backup curent size: ${CUR_BACKUP_SIZE}
Backup target size: ${BACKUP_TARGET_SIZE}
Backup reserv size: ${BACKUP_RESERV_SIZE}"

  log "${SEND_MSG}"
  # Report to email
  if [[ "${REPORT_MAIL}" -eq "1" ]]; then
    cat "${LOG_FILE}" | mail -s "${SEND_MSG_TITLE}" -a "From: Backup Admin <from-backup@server.ru>" to-user@yandex.ru
  fi

  # Report to telegram, attach logfile
  telega "${SEND_MSG}" "${LOG_FILE}"


}


remove_old_backup_one() {
  if [[ ${#} -eq "2" ]];then
    log "Remove backup files in ${1} older ${2} day:"
    find "${1}" -type f -mtime +"${2}" -print -delete | log -n 1
  fi
}




print_help(){
  echo "This Help file"
  echo "--------------"
  echo \
"  -h, Print this help
  -m, change mode backup. (all, daily, weekly, montly, etc, home, mysql, psql, www, opt or other)
  -s, Status backup
"
}

print_backup_status(){
  BACKUP_TARGET_SIZE="$(du -sh ${BACKUP_TARGET} | cut -f 1)"
  BACKUP_RESERV_SIZE="$(du -sh ${BACKUP_RESERV} | cut -f 1)"

  echo "BACKUP STATUS:
Backup target size: ${BACKUP_TARGET_SIZE}; ${BACKUP_TARGET}
Backup reserv size: ${BACKUP_RESERV_SIZE}; ${BACKUP_RESERV}"
}



if [[ -n "$1" ]]; then

  while [[ -n "$1" ]];do
    case "$1" in
      -h) print_help; exit 0;;
      -m) param="$2";
          change_backup_target "${2}"
          # echo "Change backup mode to ${2}"
          shift ;;
     -s)  print_backup_status;exit 0 ;;
     -e|--no-email) REPORT_MAIL="0";;

      -c) echo "Found the -c option";;
      --) shift
    break ;;
      *) echo "$1 is not an option";;
    esac
    shift
  done

  count=1
  for param in "$@";do
    echo "Parameter #$count: $param"
    count=$(( $count + 1 ))
  done
fi

if [[ -z "${CUR_BACKUP_TARGET}" ]];then
  change_backup_target "default"
fi





