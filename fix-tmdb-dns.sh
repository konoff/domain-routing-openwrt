#!/bin/sh

# tmdb-dns-fix.sh
# Универсальный скрипт для управления DNS-исключениями TMDB на OpenWrt
# Версия 1.0

# Цвета для вывода
RED='\033[31;1m'
GREEN='\033[32;1m'
YELLOW='\033[33;1m'
BLUE='\033[34;1m'
NC='\033[0m' # No Color

# Функция для вывода заголовка
print_header() {
    printf "${BLUE}========================================${NC}\n"
    printf "${BLUE}   TMDB DNS Fix for OpenWrt${NC}\n"
    printf "${BLUE}========================================${NC}\n"
    echo ""
}

# Функция для создания бэкапа
create_backup() {
    BACKUP_FILE="/tmp/dns-config-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    printf "${YELLOW}Creating backup of current DNS configs...${NC}\n"
    tar -czf "$BACKUP_FILE" /etc/config/dhcp /etc/config/stubby 2>/dev/null
    
    if [ $? -eq 0 ]; then
        printf "${GREEN}✓ Backup created: %s${NC}\n" "$BACKUP_FILE"
        echo "$BACKUP_FILE" > /tmp/last-backup-path.txt
        return 0
    else
        printf "${RED}✗ Failed to create backup${NC}\n"
        return 1
    fi
}

# Функция для применения фикса
apply_fix() {
    echo ""
    printf "${GREEN}▶ Applying TMDB DNS fix...${NC}\n"
    echo ""
    
    # Создаём бэкап перед изменениями
    create_backup
    if [ $? -ne 0 ]; then
        printf "${RED}Aborting fix due to backup failure${NC}\n"
        return 1
    fi
    
    # Шаг 1: Добавляем прямые DNS для доменов TMDB
    printf "${YELLOW}Step 1: Adding direct DNS for TMDB domains${NC}\n"
    
    # Основные домены
    printf "   Adding api.themoviedb.org → 9.9.9.9\n"
    uci add_list dhcp.@dnsmasq[0].server='/api.themoviedb.org/9.9.9.9'
    
    printf "   Adding api.themoviedb.org → 149.112.112.112 (backup)\n"
    uci add_list dhcp.@dnsmasq[0].server='/api.themoviedb.org/149.112.112.112'
    
    printf "   Adding image.tmdb.org → 9.9.9.9\n"
    uci add_list dhcp.@dnsmasq[0].server='/image.tmdb.org/9.9.9.9'
    
    printf "   Adding themoviedb.org → 9.9.9.9\n"
    uci add_list dhcp.@dnsmasq[0].server='/themoviedb.org/9.9.9.9'
    
    printf "   Adding www.themoviedb.org → 9.9.9.9\n"
    uci add_list dhcp.@dnsmasq[0].server='/www.themoviedb.org/9.9.9.9'
    
    printf "${GREEN}✓ TMDB domains configured${NC}\n\n"
    
    # Шаг 2: Оптимизируем Stubby
    printf "${YELLOW}Step 2: Optimizing Stubby for Russian networks${NC}\n"
    
    # Отключаем DNSSEC
    printf "   Disabling DNSSEC validation\n"
    uci set stubby.global.dnssec_return_status="0"
    
    # Увеличиваем таймауты
    printf "   Increasing timeouts for reliability\n"
    uci set stubby.global.timeout="3000"
    
    printf "${GREEN}✓ Stubby optimized${NC}\n\n"
    
    # Шаг 3: Сохраняем изменения
    printf "${YELLOW}Step 3: Saving configuration${NC}\n"
    uci commit dhcp
    uci commit stubby
    printf "${GREEN}✓ Configuration saved${NC}\n\n"
    
    # Шаг 4: Перезапускаем сервисы
    printf "${YELLOW}Step 4: Restarting services${NC}\n"
    
    printf "   Restarting stubby...\n"
    /etc/init.d/stubby restart
    
    printf "   Restarting dnsmasq...\n"
    /etc/init.d/dnsmasq restart
    
    printf "${GREEN}✓ Services restarted${NC}\n\n"
    
    # Шаг 5: Проверка результата
    printf "${YELLOW}Step 5: Testing resolution${NC}\n"
    printf "   Testing api.themoviedb.org...\n"
    
    # Даём время сервисам подняться
    sleep 2
    
    TEST_RESULT=$(nslookup api.themoviedb.org localhost 2>/dev/null | grep -A 5 "Name:" | grep "Address" | head -1)
    
    if echo "$TEST_RESULT" | grep -q "127.0.0.1"; then
        printf "${RED}✗ Still getting 127.0.0.1${NC}\n"
        printf "   Check configuration manually or try reboot\n"
    else
        IP_ADDR=$(echo "$TEST_RESULT" | awk '{print $2}')
        printf "${GREEN}✓ SUCCESS! Got real IP: %s${NC}\n" "$IP_ADDR"
    fi
    
    echo ""
    printf "${GREEN}========================================${NC}\n"
    printf "${GREEN}   Fix completed successfully${NC}\n"
    printf "${GREEN}========================================${NC}\n"
}

# Функция для отката изменений
rollback_changes() {
    echo ""
    printf "${YELLOW}▶ Rolling back TMDB DNS changes...${NC}\n"
    echo ""
    
    # Проверяем наличие бэкапов
    BACKUP_FILES=$(ls -t /tmp/dns-config-backup-*.tar.gz 2>/dev/null | head -3)
    
    if [ -z "$BACKUP_FILES" ]; then
        printf "${RED}No backup files found in /tmp/${NC}\n"
        printf "${YELLOW}Looking for last backup path...${NC}\n"
        
        if [ -f /tmp/last-backup-path.txt ]; then
            LAST_BACKUP=$(cat /tmp/last-backup-path.txt)
            if [ -f "$LAST_BACKUP" ]; then
                BACKUP_FILES="$LAST_BACKUP"
            fi
        fi
    fi
    
    if [ -n "$BACKUP_FILES" ]; then
        printf "${YELLOW}Available backups:${NC}\n"
        echo "$BACKUP_FILES" | nl -w2 -s') '
        
        printf "\n${YELLOW}Enter backup number to restore (or 'q' to quit): ${NC}"
        read CHOICE
        
        if [ "$CHOICE" != "q" ] && [ "$CHOICE" -ge 1 ] 2>/dev/null; then
            SELECTED_BACKUP=$(echo "$BACKUP_FILES" | sed -n "${CHOICE}p")
            
            if [ -n "$SELECTED_BACKUP" ]; then
                printf "${YELLOW}Restoring from: %s${NC}\n" "$SELECTED_BACKUP"
                tar -xzf "$SELECTED_BACKUP" -C /
                
                if [ $? -eq 0 ]; then
                    printf "${GREEN}✓ Backup restored${NC}\n"
                    
                    # Перезапускаем сервисы
                    printf "${YELLOW}Restarting services...${NC}\n"
                    /etc/init.d/stubby restart
                    /etc/init.d/dnsmasq restart
                    
                    printf "${GREEN}✓ Services restarted${NC}\n"
                    
                    # Проверка после отката
                    sleep 2
                    TEST_RESULT=$(nslookup api.themoviedb.org localhost 2>/dev/null | grep -A 5 "Name:" | grep "Address" | head -1)
                    
                    if echo "$TEST_RESULT" | grep -q "127.0.0.1"; then
                        printf "${RED}✗ After rollback: still getting 127.0.0.1${NC}\n"
                    else
                        IP_ADDR=$(echo "$TEST_RESULT" | awk '{print $2}')
                        printf "${GREEN}✓ After rollback: got real IP: %s${NC}\n" "$IP_ADDR"
                    fi
                else
                    printf "${RED}✗ Failed to restore backup${NC}\n"
                fi
            fi
        fi
    else
        printf "${YELLOW}No automatic backups found.${NC}\n"
        printf "${YELLOW}Do you want to manually remove TMDB exceptions? (y/n): ${NC}"
        read MANUAL_CHOICE
        
        if [ "$MANUAL_CHOICE" = "y" ] || [ "$MANUAL_CHOICE" = "Y" ]; then
            printf "${YELLOW}Removing TMDB exceptions from dnsmasq...${NC}\n"
            
            # Получаем текущий список server записей
            SERVER_LIST=$(uci show dhcp.@dnsmasq[0] | grep ".server=")
            
            # Создаём временный файл с новым списком
            TEMP_FILE=$(mktemp)
            
            # Фильтруем записи, оставляем только не-TMDB
            uci show dhcp.@dnsmasq[0] | grep ".server=" | while read line; do
                if ! echo "$line" | grep -q "themoviedb.org"; then
                    echo "$line" >> "$TEMP_FILE"
                fi
            done
            
            # Очищаем и восстанавливаем
            uci -q delete dhcp.@dnsmasq[0].server
            if [ -s "$TEMP_FILE" ]; then
                cat "$TEMP_FILE" | while read line; do
                    VALUE=$(echo "$line" | cut -d'=' -f2- | tr -d "'")
                    uci add_list dhcp.@dnsmasq[0].server="$VALUE"
                done
            fi
            
            rm -f "$TEMP_FILE"
            
            # Восстанавливаем DNSSEC в Stubby
            uci set stubby.global.dnssec_return_status="1"
            uci set stubby.global.timeout="1500"
            
            uci commit dhcp
            uci commit stubby
            
            printf "${GREEN}✓ Manual cleanup completed${NC}\n"
            
            /etc/init.d/stubby restart
            /etc/init.d/dnsmasq restart
        fi
    fi
    
    echo ""
    printf "${GREEN}========================================${NC}\n"
    printf "${GREEN}   Rollback completed${NC}\n"
    printf "${GREEN}========================================${NC}\n"
}

# Функция для проверки текущего статуса
check_status() {
    echo ""
    printf "${BLUE}▶ Checking current DNS status...${NC}\n"
    echo ""
    
    # Проверяем DNS-серверы в dnsmasq
    printf "${YELLOW}Current DNS servers in dnsmasq:${NC}\n"
    uci show dhcp.@dnsmasq[0] | grep ".server=" | while read line; do
        VALUE=$(echo "$line" | cut -d'=' -f2-)
        if echo "$VALUE" | grep -q "themoviedb.org"; then
            printf "  ${GREEN}%s${NC}\n" "$VALUE"
        else
            printf "  %s\n" "$VALUE"
        fi
    done
    echo ""
    
    # Проверяем настройки Stubby
    printf "${YELLOW}Stubby DNSSEC status:${NC}\n"
    DNSSEC_STATUS=$(uci get stubby.global.dnssec_return_status 2>/dev/null)
    if [ "$DNSSEC_STATUS" = "0" ]; then
        printf "  ${GREEN}DNSSEC: Disabled (fix applied)${NC}\n"
    else
        printf "  ${RED}DNSSEC: Enabled (default)${NC}\n"
    fi
    echo ""
    
    # Проверяем резолвинг TMDB
    printf "${YELLOW}Testing TMDB resolution:${NC}\n"
    TEST_RESULT=$(nslookup api.themoviedb.org localhost 2>/dev/null | grep -A 5 "Name:" | grep "Address" | head -1)
    
    if echo "$TEST_RESULT" | grep -q "127.0.0.1"; then
        printf "  ${RED}✗ api.themoviedb.org → 127.0.0.1 (BROKEN)${NC}\n"
    else
        IP_ADDR=$(echo "$TEST_RESULT" | awk '{print $2}')
        printf "  ${GREEN}✓ api.themoviedb.org → %s (OK)${NC}\n" "$IP_ADDR"
    fi
    echo ""
}

# Главное меню
main_menu() {
    print_header
    
    printf "${YELLOW}What would you like to do?${NC}\n"
    printf "  ${GREEN}1)${NC} Apply TMDB DNS fix (add exceptions, disable DNSSEC)\n"
    printf "  ${GREEN}2)${NC} Rollback changes (restore from backup or manual cleanup)\n"
    printf "  ${GREEN}3)${NC} Check current status\n"
    printf "  ${GREEN}4)${NC} Quit\n"
    echo ""
    printf "${YELLOW}Enter choice [1-4]: ${NC}"
    read MAIN_CHOICE
    
    case "$MAIN_CHOICE" in
        1)
            apply_fix
            ;;
        2)
            rollback_changes
            ;;
        3)
            check_status
            ;;
        4)
            printf "${GREEN}Exiting.${NC}\n"
            exit 0
            ;;
        *)
            printf "${RED}Invalid choice. Please enter 1-4.${NC}\n"
            sleep 2
            main_menu
            ;;
    esac
    
    echo ""
    printf "${YELLOW}Press Enter to return to main menu...${NC}"
    read DUMMY
    main_menu
}

# Запуск главного меню
main_menu