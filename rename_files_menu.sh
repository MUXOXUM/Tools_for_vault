#!/usr/bin/env bash

# ===============================================
# media_renamer.sh - Утилита для массового переименования медиафайлов
# Версия: 1.5
# Описание: Скрипт с меню для рекурсивного переименования
# ===============================================

# --- Конфигурация цветов ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# --- Глобальные переменные ---
SCRIPT_NAME="$(basename "$0")"
LOG_FILE=""

# --- Расширения медиафайлов ---
IMAGE_EXTENSIONS="jpg jpeg png gif bmp tiff tif webp heic heif avif"
VIDEO_EXTENSIONS="mp4 mkv avi mov wmv flv m4v mpg mpeg webm 3gp 3g2 ogv"

# --- Обработка сигналов ---
cleanup() {
    printf "\n${YELLOW}Получен сигнал завершения. Выход...${NC}\n"
    log_msg "INFO" "Получен сигнал завершения, выход."
    exit 0
}
trap cleanup INT TERM

# --- Очистка экрана ---
clear_screen() {
    printf "\033[2J\033[H"
}

# --- Логирование ---
init_logging() {
    ts=$(date +"%Y%m%d_%H%M%S")
    LOG_FILE="./media_renamer_${ts}.log"

    if ! : > "$LOG_FILE"; then
        printf "${RED}Ошибка: не удалось создать лог-файл: %s${NC}\n" "$LOG_FILE"
        return 1
    fi

    log_msg "INFO" "Скрипт запущен. PID=$$"
    log_msg "INFO" "Текущая директория: $(pwd)"
    return 0
}

log_msg() {
    level="$1"
    shift
    message="$*"
    now=$(date +"%Y-%m-%d %H:%M:%S")

    if [ -n "$LOG_FILE" ]; then
        printf '[%s] [%s] %s\n' "$now" "$level" "$message" >> "$LOG_FILE"
    fi
}

# --- Подтверждение запуска режима ---
confirm_mode() {
    mode_title="$1"
    mode_description="$2"

    clear_screen
    printf "${PURPLE}=== %s ===${NC}\n\n" "$mode_title"
    printf "%s\n\n" "$mode_description"
    printf "${YELLOW}Продолжить? [Y/n]: ${NC}"
    read -r answer

    case "$answer" in
        ""|Y|y|yes|YES)
            log_msg "INFO" "Подтвержден запуск режима: $mode_title"
            return 0
            ;;
        *)
            log_msg "INFO" "Отменен запуск режима: $mode_title"
            printf "\n${YELLOW}Операция отменена.${NC}\n"
            printf "\n${PURPLE}Нажмите Enter для возврата в меню...${NC}"
            read -r dummy
            return 1
            ;;
    esac
}

# --- Проверка наличия утилиты ---
check_dependency() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf "${RED}Ошибка: Утилита '%s' не найдена.${NC}\n" "$1"
        return 1
    fi
    return 0
}

# --- Проверка, является ли файл медиафайлом (фото или видео) ---
is_media_file() {
    filename="$1"
    ext=$(echo "$filename" | sed 's/.*\.//' | tr '[:upper:]' '[:lower:]')

    # Проверяем по спискам расширений
    for image_ext in $IMAGE_EXTENSIONS; do
        if [ "$ext" = "$image_ext" ]; then
            return 0
        fi
    done

    for video_ext in $VIDEO_EXTENSIONS; do
        if [ "$ext" = "$video_ext" ]; then
            return 0
        fi
    done

    return 1
}

# --- Функция для безопасного переименования с защитой от дубликатов ---
# Теперь добавляет миллисекунды и инкрементирует их при конфликтах
safe_rename() {
    src="$1"
    dst="$2"
    base_name="$3"  # Базовое имя без расширения для отображения

    # Если исходный и целевой файлы совпадают - пропускаем
    if [ "$src" = "$dst" ]; then
        log_msg "INFO" "Пропуск переименования (имя не изменилось): '$src'"
        return 2
    fi

    # Проверяем существование целевого файла
    if [ ! -e "$dst" ]; then
        if mv "$src" "$dst" 2>/dev/null; then
            log_msg "INFO" "Переименован: '$src' -> '$dst'"
            return 0
        else
            log_msg "ERROR" "Ошибка mv: '$src' -> '$dst'"
            return 1
        fi
    fi

    # Целевой файл существует - извлекаем компоненты
    dir=$(dirname "$dst")
    filename=$(basename "$dst")
    base="${filename%.*}"
    ext="${filename##*.}"
    ext=".$ext"

    # Проверяем, есть ли уже миллисекунды в имени
    if echo "$base" | grep -qE '_([0-9]{1,3})$'; then
        # Извлекаем существующие миллисекунды
        current_ms=$(echo "$base" | sed -n 's/.*_\([0-9]\{1,3\}\)$/\1/p')
        base_without_ms=$(echo "$base" | sed 's/_[0-9]\{1,3\}$//')

        # Инкрементируем миллисекунды
        new_ms=$((current_ms + 1))
        # Ограничиваем до 999 (максимум 3 цифры)
        if [ $new_ms -gt 999 ]; then
            new_ms=1
            # Если переполнение, добавляем счетчик в формате _1, _2 и т.д.
            counter=1
            while [ -e "${dir}/${base_without_ms}_${new_ms}_${counter}${ext}" ]; do
                counter=$((counter + 1))
            done
            new_dst="${dir}/${base_without_ms}_${new_ms}_${counter}${ext}"
            if mv "$src" "$new_dst" 2>/dev/null; then
                printf "${BLUE}Файл существовал, переименован в: %s (добавлен счетчик %d)${NC}\n" "$(basename "$new_dst")" "$counter"
                log_msg "INFO" "Коллизия имени, переименован: '$src' -> '$new_dst'"
                return 0
            else
                log_msg "ERROR" "Ошибка mv при коллизии: '$src' -> '$new_dst'"
                return 1
            fi
        fi

        new_base="${base_without_ms}_${new_ms}"
    else
        # Нет миллисекунд - добавляем 1
        new_base="${base}_1"
    fi

    new_dst="${dir}/${new_base}${ext}"

    # Проверяем, не существует ли новое имя
    if [ -e "$new_dst" ]; then
        # Рекурсивно вызываем снова для обработки коллизии
        safe_rename "$src" "$new_dst" "$base_name"
        return $?
    fi

    if mv "$src" "$new_dst" 2>/dev/null; then
        printf "${BLUE}Файл существовал, переименован в: %s${NC}\n" "$(basename "$new_dst")"
        log_msg "INFO" "Коллизия имени, переименован: '$src' -> '$new_dst'"
        return 0
    else
        log_msg "ERROR" "Ошибка mv при коллизии: '$src' -> '$new_dst'"
        return 1
    fi
}

# --- Извлечение даты и времени из имени файла ---
extract_datetime_from_name() {
    filename="$1"
    basename_str=$(basename "$filename" | sed 's/\.[^.]*$//')

    # Шаблоны для скриншотов
    # Шаблон: Снимок экрана YYYY-MM-DD HHMMSS
    if echo "$basename_str" | grep -qE '^Снимок экрана [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{6}'; then
        date_part=$(echo "$basename_str" | sed -n 's/^Снимок экрана \([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\) \([0-9]\{6\}\).*$/\1 \2/p')
        if [ -n "$date_part" ]; then
            formatted_date=$(echo "$date_part" | sed 's/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\) \([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1_\2:\3:\4/')
            echo "$formatted_date"
            return 0
        fi
    fi

    # Шаблон: Снимок экрана_YYYYMMDD_HHMMSS
    if echo "$basename_str" | grep -qE '^Снимок экрана_[0-9]{8}_[0-9]{6}'; then
        date_part=$(echo "$basename_str" | sed -n 's/^Снимок экрана_\([0-9]\{8\}\)_\([0-9]\{6\}\).*$/\1 \2/p')
        if [ -n "$date_part" ]; then
            formatted_date=$(echo "$date_part" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\) \([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3_\4:\5:\6/')
            echo "$formatted_date"
            return 0
        fi
    fi

    # Шаблон: Снимок экрана YYYY-MM-DD HH-MM-SS
    if echo "$basename_str" | grep -qE '^Снимок экрана [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}-[0-9]{2}-[0-9]{2}'; then
        echo "$basename_str" | sed -n 's/^Снимок экрана \([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\) \([0-9]\{2\}\)-\([0-9]\{2\}\)-\([0-9]\{2\}\).*$/\1_\2:\3:\4/p'
        return 0
    fi

    # Шаблон: YYYY-MM-DD_HH.MM.SS
    if echo "$basename_str" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}\.[0-9]{2}\.[0-9]{2}'; then
        echo "$basename_str" | sed -n 's/^\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)_\([0-9]\{2\}\)\.\([0-9]\{2\}\)\.\([0-9]\{2\}\).*$/\1_\2:\3:\4/p'
        return 0
    fi

    # Шаблон: Capture YYYY-MM-DD HH_MM_SS
    if echo "$basename_str" | grep -qE '^Capture [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}_[0-9]{2}_[0-9]{2}'; then
        echo "$basename_str" | sed -n 's/^Capture \([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\) \([0-9]\{2\}\)_\([0-9]\{2\}\)_\([0-9]\{2\}\).*$/\1_\2:\3:\4/p'
        return 0
    fi

    # Шаблон: Capture_YYYY-MM-DD_HH_MM_SS
    if echo "$basename_str" | grep -qE '^Capture_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}_[0-9]{2}_[0-9]{2}'; then
        echo "$basename_str" | sed -n 's/^Capture_\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)_\([0-9]\{2\}\)_\([0-9]\{2\}\)_\([0-9]\{2\}\).*$/\1_\2:\3:\4/p'
        return 0
    fi

    # Шаблон: ScreenshotYYYYMMDD-HHMMSSxxx
    if echo "$basename_str" | grep -qE '^Screenshot[0-9]{8}-[0-9]{6}'; then
        date_part=$(echo "$basename_str" | sed -n 's/^Screenshot\([0-9]\{8\}\)-\([0-9]\{6\}\).*$/\1 \2/p')
        if [ -n "$date_part" ]; then
            formatted_date=$(echo "$date_part" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\) \([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3_\4:\5:\6/')
            echo "$formatted_date"
            return 0
        fi
    fi

    # Шаблон: Screenshot YYYYMMDD HHMMSS
    if echo "$basename_str" | grep -qE '^Screenshot [0-9]{8} [0-9]{6}'; then
        date_part=$(echo "$basename_str" | sed -n 's/^Screenshot \([0-9]\{8\}\) \([0-9]\{6\}\).*$/\1 \2/p')
        if [ -n "$date_part" ]; then
            formatted_date=$(echo "$date_part" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\) \([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3_\4:\5:\6/')
            echo "$formatted_date"
            return 0
        fi
    fi

    # Шаблон: Screenshot_YYYYMMDD_HHMMSS
    if echo "$basename_str" | grep -qE '^Screenshot_[0-9]{8}_[0-9]{6}'; then
        date_part=$(echo "$basename_str" | sed -n 's/^Screenshot_\([0-9]\{8\}\)_\([0-9]\{6\}\).*$/\1 \2/p')
        if [ -n "$date_part" ]; then
            formatted_date=$(echo "$date_part" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\) \([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3_\4:\5:\6/')
            echo "$formatted_date"
            return 0
        fi
    fi

    # Шаблоны для унификации IMG/VID/photo/video
    # [IMG|VID]_YYYYMMDD_HHMMSS
    if echo "$basename_str" | grep -qE '^(IMG|VID)_[0-9]{8}_[0-9]{6}'; then
        date_part=$(echo "$basename_str" | sed -n 's/^[A-Z]\{3\}_\([0-9]\{8\}\)_\([0-9]\{6\}\).*$/\1 \2/p')
        if [ -n "$date_part" ]; then
            formatted_date=$(echo "$date_part" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\) \([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3_\4:\5:\6/')
            echo "$formatted_date"
            return 0
        fi
    fi

    # [IMG|VID]_YYYYMMDD_HHMMSS_999
    if echo "$basename_str" | grep -qE '^(IMG|VID)_[0-9]{8}_[0-9]{6}_[0-9]{1,3}'; then
        date_part=$(echo "$basename_str" | sed -n 's/^[A-Z]\{3\}_\([0-9]\{8\}\)_\([0-9]\{6\}\)_[0-9]\{1,3\}$/\1 \2/p')
        if [ -n "$date_part" ]; then
            formatted_date=$(echo "$date_part" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\) \([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3_\4:\5:\6/')
            ms=$(echo "$basename_str" | sed -n 's/^[A-Z]\{3\}_[0-9]\{8\}_[0-9]\{6\}_\([0-9]\{1,3\}\)$/\1/p')
            echo "${formatted_date}_${ms}"
            return 0
        fi
    fi

    # [IMG|VID]_YYYYMMDD_HH-MM-SS
    if echo "$basename_str" | grep -qE '^(IMG|VID)_[0-9]{8}_[0-9]{2}-[0-9]{2}-[0-9]{2}'; then
        echo "$basename_str" | sed -n 's/^[A-Z]\{3\}_\([0-9]\{8\}\)_\([0-9]\{2\}\)-\([0-9]\{2\}\)-\([0-9]\{2\}\).*$/\1 \2:\3:\4/p' | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\) /\1-\2-\3_/'
        return 0
    fi

    # [IMG|VID]_YYYY-MM-DD_HH-MM-SS
    if echo "$basename_str" | grep -qE '^(IMG|VID)_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}'; then
        echo "$basename_str" | sed -n 's/^[A-Z]\{3\}_\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)_\([0-9]\{2\}\)-\([0-9]\{2\}\)-\([0-9]\{2\}\).*$/\1_\2:\3:\4/p'
        return 0
    fi

    # photo/video_YYYY-MM-DD_HH-MM-SS
    if echo "$basename_str" | grep -qE '^(photo|video)_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}'; then
        echo "$basename_str" | sed -n 's/^[a-z]\{5\}_\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)_\([0-9]\{2\}\)-\([0-9]\{2\}\)-\([0-9]\{2\}\).*$/\1_\2:\3:\4/p'
        return 0
    fi

    # Photo_YYYY-MM-DD-HHMMSS или Video_YYYY-MM-DD-HHMMSS
    if echo "$basename_str" | grep -qE '^(Photo|Video)_[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}'; then
        echo "$basename_str" | sed -n 's/^[Pp]hoto_\|^[Vv]ideo_//p' | sed 's/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1_\2:\3:\4/'
        return 0
    fi

    return 1
}

# --- Функция для получения даты из метаданных файла ---
get_file_dates() {
    file="$1"

    # Получаем дату создания (birth time) если доступна, иначе дату изменения
    if [ "$(uname)" = "Linux" ]; then
        # Для Linux используем stat с разными опциями
        # Полная дата с наносекундами для создания
        create_full=$(stat -c %w "$file" 2>/dev/null)
        if [ "$create_full" = "-" ] || [ -z "$create_full" ]; then
            # Если дата создания недоступна, используем дату изменения
            create_full=$(stat -c %y "$file" 2>/dev/null)
        fi
        # Извлекаем дату и время без наносекунд
        create_date=$(echo "$create_full" | cut -d' ' -f1,2 | sed 's/\.[0-9]*//' | sed 's/ /_/')

        # Дата изменения с наносекундами
        modify_full=$(stat -c %y "$file" 2>/dev/null)
        modify_date=$(echo "$modify_full" | cut -d' ' -f1,2 | sed 's/\.[0-9]*//' | sed 's/ /_/')

        # Сохраняем наносекунды для возможного использования
        create_nano=$(echo "$create_full" | grep -o '\.[0-9]*' | cut -c2-)
        modify_nano=$(echo "$modify_full" | grep -o '\.[0-9]*' | cut -c2-)

        # Возвращаем даты и наносекунды
        echo "${create_date}|${modify_date}|${create_nano}|${modify_nano}"

    elif [ "$(uname)" = "Darwin" ]; then
        # Для macOS (менее точное, только секунды)
        create_date=$(stat -f %B "$file" 2>/dev/null | xargs -I {} date -r {} +"%Y-%m-%d_%H:%M:%S")
        modify_date=$(stat -f %m "$file" 2>/dev/null | xargs -I {} date -r {} +"%Y-%m-%d_%H:%M:%S")
        echo "${create_date}|${modify_date}||"
    else
        # Для других систем используем дату изменения
        create_date=$(date -r "$file" +"%Y-%m-%d_%H:%M:%S" 2>/dev/null)
        modify_date="$create_date"
        echo "${create_date}|${modify_date}||"
    fi
}

# --- Функция для сравнения дат и выбора наиболее ранней ---
get_earliest_date() {
    date1="$1"
    date2="$2"

    if [ -z "$date1" ] && [ -z "$date2" ]; then
        echo ""
        return 1
    elif [ -z "$date1" ]; then
        echo "$date2"
        return 0
    elif [ -z "$date2" ]; then
        echo "$date1"
        return 0
    fi

    # Преобразуем даты в секунды для сравнения (для Linux)
    if [ "$(uname)" = "Linux" ]; then
        date1_sec=$(date -d "$(echo "$date1" | sed 's/_/ /')" +%s 2>/dev/null)
        date2_sec=$(date -d "$(echo "$date2" | sed 's/_/ /')" +%s 2>/dev/null)
    else
        # Для macOS/BSD
        date1_sec=$(date -j -f "%Y-%m-%d_%H:%M:%S" "$date1" +%s 2>/dev/null)
        date2_sec=$(date -j -f "%Y-%m-%d_%H:%M:%S" "$date2" +%s 2>/dev/null)
    fi

    if [ -n "$date1_sec" ] && [ -n "$date2_sec" ]; then
        if [ "$date1_sec" -le "$date2_sec" ]; then
            echo "$date1"
        else
            echo "$date2"
        fi
    elif [ -n "$date1_sec" ]; then
        echo "$date1"
    else
        echo "$date2"
    fi

    return 0
}

# --- Проверка, нужно ли пропускать файл для переименования по метаданным ---
should_skip_for_metadata() {
    filename="$1"
    basename_str=$(basename "$filename")

    # Пропускаем сам скрипт
    if [ "$basename_str" = "$SCRIPT_NAME" ]; then
        return 0
    fi

    # Проверяем, является ли файл медиафайлом
    if ! is_media_file "$filename"; then
        return 0
    fi

    # Пропускаем уже переименованные по шаблону ns_YYYY-MM-DD_HH:MM:SS.*
    # (с двоеточиями, без миллисекунд)
    if echo "$basename_str" | grep -qE '^ns_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}:[0-9]{2}:[0-9]{2}\.[^.]+$'; then
        return 0
    fi

    # Пропускаем уже переименованные по шаблону ns_YYYY-MM-DD_HH:MM:SS_XXX.ext
    # (с миллисекундами от 1 до 3 цифр)
    if echo "$basename_str" | grep -qE '^ns_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}:[0-9]{2}:[0-9]{2}_[0-9]{1,3}\.[^.]+$'; then
        return 0
    fi

    # Пропускаем уже переименованные по шаблону ns_YYYY-MM-DD_HH:MM:SS_XXX_YYY.ext
    # (с миллисекундами и дополнительным счетчиком)
    if echo "$basename_str" | grep -qE '^ns_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}:[0-9]{2}:[0-9]{2}_[0-9]{1,3}_[0-9]+\.[^.]+$'; then
        return 0
    fi

    # Пропускаем файлы, которые УЖЕ имеют правильный формат даты YYYY-MM-DD_HH:MM:SS (без префикса ns_)
    # (с двоеточиями, без миллисекунд)
    if echo "$basename_str" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}:[0-9]{2}:[0-9]{2}\.[^.]+$'; then
        return 0
    fi

    # Пропускаем файлы, которые УЖЕ имеют правильный формат даты с миллисекундами YYYY-MM-DD_HH:MM:SS_XXX.ext
    # (с миллисекундами от 1 до 3 цифр, без префикса ns_)
    if echo "$basename_str" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}:[0-9]{2}:[0-9]{2}_[0-9]{1,3}\.[^.]+$'; then
        return 0
    fi

    return 1
}

# --- Пункт 1: Переименование по EXIF ---
mode_exif() {
    if ! confirm_mode \
        "РЕЖИМ 1: Переименование по EXIF" \
        "Как работает режим:
- Обрабатывает только фотофайлы с EXIF-датой.
- Переименовывает в формат: YYYY-MM-DD_HH:MM:SS.ext
- Если есть SubSec, добавляет миллисекунды: YYYY-MM-DD_HH:MM:SS_123.ext
- При конфликте имен использует безопасное авто-добавление суффикса."; then
        return
    fi

    clear_screen
    printf "${PURPLE}=== РЕЖИМ 1: Переименование по EXIF ===${NC}\n\n"
    log_msg "INFO" "Запуск режима 1 (EXIF)"

    # Проверка наличия exiftool
    if ! check_dependency "exiftool"; then
        printf "${YELLOW}Для использования этого режима установите exiftool:${NC}\n"
        printf "${BLUE}  sudo apt install exiftool${NC}\n"
        printf "${BLUE}  или${NC}\n"
        printf "${BLUE}  sudo yum install exiftool${NC}\n"
        printf "\n${PURPLE}Нажмите Enter для возврата в меню...${NC}"
        read -r dummy
        return
    fi

    # Счетчики
    processed=0
    renamed=0
    skipped=0
    errors=0

    # Временный файл для хранения статистики
    stats_file=$(mktemp)
    echo "0 0 0 0" > "$stats_file"

    # Поиск и обработка файлов
    for ext in $IMAGE_EXTENSIONS; do
        # Поиск без учета регистра
        find . -type f -iname "*.$ext" -print0 | while IFS= read -r -d '' file; do
            # Читаем текущие значения
            read p r s e < "$stats_file"
            p=$((p + 1))

            # Получаем директорию и расширение файла
            dir=$(dirname "$file")
            filename=$(basename "$file")
            file_ext="${filename##*.}"

            # Извлечение даты из EXIF
            datetime=$(exiftool -d "%Y-%m-%d_%H:%M:%S" -DateTimeOriginal -SubSecTimeOriginal -CreateDate -d "%Y-%m-%d_%H:%M:%S" "$file" 2>/dev/null | head -1 | sed 's/^.*: //')
            subsec=$(exiftool -SubSecTimeOriginal "$file" 2>/dev/null | head -1 | sed 's/^.*: //')

            if [ -z "$subsec" ]; then
                subsec=$(exiftool -SubSecCreateDate "$file" 2>/dev/null | head -1 | sed 's/^.*: //' | cut -d'.' -f2)
            fi

            if [ -n "$datetime" ]; then
                # Формируем новое имя
                if [ -n "$subsec" ] && [ ${#subsec} -gt 0 ]; then
                    ms=$(echo "$subsec" | cut -c1-3 | sed 's/^0*//')
                    new_name="${datetime}_${ms}.${file_ext}"
                else
                    new_name="${datetime}.${file_ext}"
                fi

                new_path="$dir/$new_name"

                # Переименовываем с использованием улучшенной safe_rename
                safe_rename "$file" "$new_path" "$filename"
                rc=$?
                case "$rc" in
                    0)
                        printf "${GREEN}  ✓ %s -> %s${NC}\n" "$filename" "$(basename "$new_path")"
                        r=$((r + 1))
                        ;;
                    1)
                        printf "${RED}  ✗ Ошибка переименования: %s${NC}\n" "$filename"
                        e=$((e + 1))
                        ;;
                    2)
                        # Уже имеет правильное имя - не выводим
                        s=$((s + 1))
                        ;;
                esac
            else
                # Нет EXIF данных - пропускаем без вывода
                s=$((s + 1))
            fi

            # Сохраняем обновленные значения
            echo "$p $r $s $e" > "$stats_file"
        done
    done

    # Читаем финальную статистику
    read processed renamed skipped errors < "$stats_file"
    rm -f "$stats_file"

    # Итоговая статистика
    printf "\n${PURPLE}=== ИТОГ РЕЖИМА 1 ===${NC}\n"
    printf "${BLUE}Обработано: %d${NC}\n" "$processed"
    printf "${GREEN}Переименовано: %d${NC}\n" "$renamed"
    printf "${YELLOW}Пропущено: %d${NC}\n" "$skipped"
    printf "${RED}Ошибок: %d${NC}\n" "$errors"
    log_msg "INFO" "Итог режима 1: processed=$processed renamed=$renamed skipped=$skipped errors=$errors"

    printf "\n${PURPLE}Нажмите Enter для возврата в меню...${NC}"
    read -r dummy
}

# --- Пункт 2: Переименование по шаблонам имен (скриншоты + IMG/VID/photo/video) ---
mode_name_patterns() {
    if ! confirm_mode \
        "РЕЖИМ 2: Переименование по шаблонам имен" \
        "Как работает режим:
- Обрабатывает только фото и видео.
- Переименовывает ТОЛЬКО файлы с именами в одном из форматов:
  1) Снимок экрана YYYY-MM-DD HHMMSS
  2) Снимок экрана_YYYYMMDD_HHMMSS
  3) Снимок экрана YYYY-MM-DD HH-MM-SS
  4) YYYY-MM-DD_HH.MM.SS
  5) Capture YYYY-MM-DD HH_MM_SS
  6) Capture_YYYY-MM-DD_HH_MM_SS
  7) ScreenshotYYYYMMDD-HHMMSSxxx
  8) Screenshot YYYYMMDD HHMMSS
  9) Screenshot_YYYYMMDD_HHMMSS
  10) IMG_YYYYMMDD_HHMMSS / VID_YYYYMMDD_HHMMSS
  11) IMG_YYYYMMDD_HHMMSS_999 / VID_YYYYMMDD_HHMMSS_999
  12) IMG_YYYYMMDD_HH-MM-SS / VID_YYYYMMDD_HH-MM-SS
  13) IMG_YYYY-MM-DD_HH-MM-SS / VID_YYYY-MM-DD_HH-MM-SS
  14) photo_YYYY-MM-DD_HH-MM-SS / video_YYYY-MM-DD_HH-MM-SS
  15) Photo_YYYY-MM-DD-HHMMSS / Video_YYYY-MM-DD-HHMMSS
- Переименовывает в единый формат: YYYY-MM-DD_HH:MM:SS.ext
- Если в исходном имени есть миллисекунды, сохраняет их: ..._123.ext
- При конфликте имен использует безопасное авто-добавление суффикса."; then
        return
    fi

    clear_screen
    printf "${PURPLE}=== РЕЖИМ 2: Переименование по шаблонам имен ===${NC}\n\n"
    log_msg "INFO" "Запуск режима 2 (шаблоны имен)"

    processed=0
    renamed=0
    skipped=0
    errors=0

    img_count=0
    vid_count=0
    photo_count=0
    video_count=0

    stats_file=$(mktemp)
    echo "0 0 0 0 0 0 0 0" > "$stats_file"

    find . -type f -print0 | while IFS= read -r -d '' file; do
        # Проверяем, является ли файл медиафайлом
        if ! is_media_file "$file"; then
            continue
        fi

        read p r s e img vid photo video < "$stats_file"
        p=$((p + 1))
        basename_str=$(basename "$file")

        # Определяем тип исходного формата
        if echo "$basename_str" | grep -qE '^IMG_'; then
            img=$((img + 1))
        elif echo "$basename_str" | grep -qE '^VID_'; then
            vid=$((vid + 1))
        elif echo "$basename_str" | grep -qE '^photo_'; then
            photo=$((photo + 1))
        elif echo "$basename_str" | grep -qE '^video_'; then
            video=$((video + 1))
        fi

        datetime=$(extract_datetime_from_name "$file")

        if [ -n "$datetime" ]; then
            dir=$(dirname "$file")
            ext="${basename_str##*.}"

            # Проверяем наличие миллисекунд
            if echo "$basename_str" | grep -qE '_[0-9]{1,3}\.'; then
                ms=$(echo "$basename_str" | sed -n 's/.*_\([0-9]\{1,3\}\)\..*$/\1/p')
                new_name="${datetime}_${ms}.${ext}"
            else
                new_name="${datetime}.${ext}"
            fi

            new_path="$dir/$new_name"

            printf "${BLUE}[%d] Обработка: %s${NC}\n" "$p" "$basename_str"

            if [ "$file" = "$new_path" ]; then
                printf "${YELLOW}  - Уже имеет правильный формат${NC}\n"
                s=$((s + 1))
            else
                safe_rename "$file" "$new_path" "$basename_str"
                rc=$?
                case "$rc" in
                    0)
                        printf "${GREEN}  ✓ Переименован в: %s${NC}\n" "$(basename "$new_path")"
                        r=$((r + 1))
                        ;;
                    1)
                        printf "${RED}  ✗ Ошибка переименования${NC}\n"
                        e=$((e + 1))
                        ;;
                    2)
                        printf "${YELLOW}  - Уже имеет правильный формат${NC}\n"
                        s=$((s + 1))
                        ;;
                esac
            fi
        else
            s=$((s + 1))
        fi

        echo "$p $r $s $e $img $vid $photo $video" > "$stats_file"
    done

    read processed renamed skipped errors img_count vid_count photo_count video_count < "$stats_file"
    rm -f "$stats_file"

    printf "\n${PURPLE}=== ИТОГ РЕЖИМА 2 ===${NC}\n"
    printf "${BLUE}Обработано: %d${NC}\n" "$processed"
    printf "${GREEN}Переименовано: %d${NC}\n" "$renamed"
    printf "${YELLOW}Пропущено: %d${NC}\n" "$skipped"
    printf "${RED}Ошибок: %d${NC}\n" "$errors"
    printf "\n${BLUE}Разбивка по исходным форматам:${NC}\n"
    printf "  IMG: %d\n" "$img_count"
    printf "  VID: %d\n" "$vid_count"
    printf "  photo: %d\n" "$photo_count"
    printf "  video: %d\n" "$video_count"
    log_msg "INFO" "Итог режима 2: processed=$processed renamed=$renamed skipped=$skipped errors=$errors img=$img_count vid=$vid_count photo=$photo_count video=$video_count"

    printf "\n${PURPLE}Нажмите Enter для возврата в меню...${NC}"
    read -r dummy
}

# --- Пункт 3: Переименование по метаданным файла (дата создания/изменения) ---
mode_metadata() {
    if ! confirm_mode \
        "РЕЖИМ 3: Переименование по метаданным файла" \
        "Как работает режим:
- Обрабатывает только фото и видео.
- Берет дату создания и дату изменения файла.
- Выбирает наиболее раннюю дату.
- Формирует имя: ns_YYYY-MM-DD_HH:MM:SS.ext
- При наличии наносекунд добавляет миллисекунды: ..._123.ext
- При конфликте имен использует безопасное авто-добавление суффикса."; then
        return
    fi

    clear_screen
    printf "${PURPLE}=== РЕЖИМ 3: Переименование по метаданным файла ===${NC}\n\n"
    printf "${BLUE}Используется наиболее ранняя дата из даты создания и даты изменения${NC}\n"
    printf "${BLUE}Обрабатываются только фото и видео файлы${NC}\n\n"
    log_msg "INFO" "Запуск режима 3 (метаданные файла)"

    processed=0
    renamed=0
    skipped=0
    errors=0

    stats_file=$(mktemp)
    echo "0 0 0 0" > "$stats_file"

    find . -type f -print0 | while IFS= read -r -d '' file; do
        read p r s e < "$stats_file"
        filename=$(basename "$file")

        # Обрабатываем только фото и видео
        if ! is_media_file "$file"; then
            echo "$p $r $s $e" > "$stats_file"
            continue
        fi

        p=$((p + 1))

        # Проверяем, нужно ли пропустить файл
        if should_skip_for_metadata "$file"; then
            # Для немедиафайлов не выводим сообщение
            if is_media_file "$file"; then
                printf "${BLUE}[%d] Пропуск: %s (уже имеет правильный формат)${NC}\n" "$p" "$filename"
            fi
            s=$((s + 1))
            echo "$p $r $s $e" > "$stats_file"
            continue
        fi

        dir=$(dirname "$file")
        ext="${filename##*.}"

        # Получаем даты из метаданных файла
        dates=$(get_file_dates "$file")
        create_date=$(echo "$dates" | cut -d'|' -f1)
        modify_date=$(echo "$dates" | cut -d'|' -f2)
        create_nano=$(echo "$dates" | cut -d'|' -f3)
        modify_nano=$(echo "$dates" | cut -d'|' -f4)

        # Выбираем наиболее раннюю дату
        earliest_date=$(get_earliest_date "$create_date" "$modify_date")

        if [ -n "$earliest_date" ]; then
            # Определяем, какую дату выбрали и берем соответствующие наносекунды
            if [ "$earliest_date" = "$create_date" ] && [ -n "$create_nano" ]; then
                nanoseconds=$(echo "$create_nano" | cut -c1-3 | sed 's/^0*//')
            elif [ "$earliest_date" = "$modify_date" ] && [ -n "$modify_nano" ]; then
                nanoseconds=$(echo "$modify_nano" | cut -c1-3 | sed 's/^0*//')
            else
                nanoseconds=""
            fi

            # Формируем новое имя с префиксом ns_
            if [ -n "$nanoseconds" ] && [ "$nanoseconds" -gt 0 ] 2>/dev/null; then
                new_name="ns_${earliest_date}_${nanoseconds}.${ext}"
            else
                new_name="ns_${earliest_date}.${ext}"
            fi

            new_path="$dir/$new_name"

            printf "${BLUE}[%d] Обработка: %s${NC}\n" "$p" "$filename"
            printf "  Дата создания: %s\n" "${create_date:-недоступна}"
            printf "  Дата изменения: %s\n" "$modify_date"
            printf "  Используется: %s\n" "$earliest_date"
            if [ -n "$nanoseconds" ]; then
                printf "  Миллисекунды: %s\n" "$nanoseconds"
            fi

            # Проверяем, не совпадает ли новое имя с именем файла, который уже имеет правильный формат
            # Извлекаем дату из имени файла, если она есть в формате YYYY-MM-DD_HH:MM:SS
            name_date=$(echo "$filename" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}:[0-9]{2}:[0-9]{2}')

            if [ -n "$name_date" ] && [ "$name_date" = "$earliest_date" ]; then
                printf "${YELLOW}  - Файл уже имеет правильную дату в имени, но без префикса ns_${NC}\n"
                # Переименовываем с добавлением префикса ns_ используя улучшенную safe_rename
                safe_rename "$file" "$new_path" "$filename"
                rc=$?
                case "$rc" in
                    0)
                        printf "${GREEN}  ✓ Добавлен префикс ns_: %s${NC}\n" "$(basename "$new_path")"
                        r=$((r + 1))
                        ;;
                    1)
                        printf "${RED}  ✗ Ошибка переименования${NC}\n"
                        e=$((e + 1))
                        ;;
                    2)
                        printf "${YELLOW}  - Уже имеет правильный формат${NC}\n"
                        s=$((s + 1))
                        ;;
                esac
            else
                # Используем улучшенную safe_rename для обычного переименования
                safe_rename "$file" "$new_path" "$filename"
                rc=$?
                case "$rc" in
                    0)
                        printf "${GREEN}  ✓ Переименован в: %s${NC}\n" "$(basename "$new_path")"
                        r=$((r + 1))
                        ;;
                    1)
                        printf "${RED}  ✗ Ошибка переименования${NC}\n"
                        e=$((e + 1))
                        ;;
                    2)
                        printf "${YELLOW}  - Уже имеет правильный формат${NC}\n"
                        s=$((s + 1))
                        ;;
                esac
            fi
        else
            printf "${YELLOW}[%d] Не удалось получить дату для: %s${NC}\n" "$p" "$filename"
            s=$((s + 1))
        fi

        echo "$p $r $s $e" > "$stats_file"
    done

    read processed renamed skipped errors < "$stats_file"
    rm -f "$stats_file"

    printf "\n${PURPLE}=== ИТОГ РЕЖИМА 3 ===${NC}\n"
    printf "${BLUE}Обработано: %d${NC}\n" "$processed"
    printf "${GREEN}Переименовано: %d${NC}\n" "$renamed"
    printf "${YELLOW}Пропущено: %d${NC}\n" "$skipped"
    printf "${RED}Ошибок: %d${NC}\n" "$errors"
    log_msg "INFO" "Итог режима 3: processed=$processed renamed=$renamed skipped=$skipped errors=$errors"

    printf "\n${PURPLE}Нажмите Enter для возврата в меню...${NC}"
    read -r dummy
}

# --- Главное меню ---
show_menu() {
    clear_screen
    printf "${PURPLE}========================================${NC}\n"
    printf "${PURPLE}        MEDIA RENAMER UTILITY${NC}\n"
    printf "${PURPLE}========================================${NC}\n"
    printf "${BLUE}1 - Переименование по EXIF${NC}\n"
    printf "${BLUE}2 - Переименование по шаблонам имен${NC}\n"
    printf "${BLUE}3 - Переименование по метаданным файла${NC}\n"
    printf "${RED}0 - Выход${NC}\n"
    printf "${YELLOW}Лог: %s${NC}\n" "$LOG_FILE"
    printf "${PURPLE}========================================${NC}\n"
    printf "Выберите пункт: "
}

# --- Основной цикл программы ---
main() {
    if ! init_logging; then
        exit 1
    fi

    while true; do
        show_menu
        read -r choice

        case $choice in
            1)
                mode_exif
                ;;
            2)
                mode_name_patterns
                ;;
            3)
                mode_metadata
                ;;
            0)
                clear_screen
                printf "${GREEN}До свидания!${NC}\n"
                log_msg "INFO" "Завершение работы пользователем."
                exit 0
                ;;
            *)
                printf "${RED}Неверный выбор. Пожалуйста, выберите 0-3.${NC}\n"
                log_msg "WARN" "Неверный выбор меню: '$choice'"
                sleep 2
                ;;
        esac
    done
}

# Запуск программы
main
