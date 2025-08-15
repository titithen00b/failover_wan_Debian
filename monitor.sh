#!/bin/bash
set -euo pipefail

# Charger les variables d'environnement
CONFIG_FILE="/opt/failover/config.env"
STATUS_FILE="/opt/failover/status.txt"
LOG_FILE="/opt/failover/logs/failover.log"

# Test si le fichier de config existe
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERREUR] Fichier config.env introuvable : $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

if [ ! -f "$CONFIG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
fi

# Fonction de log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Fonction de récupération du statut actuel
get_current_status() {
    if [ -f "$STATUS_FILE" ]; then
        cat "$STATUS_FILE"
    else
        echo "NORMAL"
    fi
}

# Vérification de l'existance des paquets vnstat et jq
if [ -z "$VNSTAT" ]; then 
    dpkg -s vnstat >/dev/null 2>&1 || sudo apt-get install -y vnstat
    echo "VNSTAT=1" >> config.env
fi
if [ -z "$JQ" ]; then 
    dpkg -s jq >/dev/null 2>&1 || sudo apt-get install -y jq
    echo "JQ=1" >> config.env
fi

# Fonction de MAJ du JSON
update_state_json() {
    local mode="$1"
    local data="$2"
    jq --arg mode "$mode" --arg data "$data" \
       '.mode = $mode | .data_used = $data' \
       state.json > tmp.json && mv -f tmp.json state.json
}

# Fonction de vidage iptable
clean_iptables(){
    iptables -F
    iptables -t nat -F
    iptables -X
    iptables -t nat -X
}

CURRENT_STATUS=$(get_current_status)

# Test de connectivité
ping -I $WAN1 -c 3 -W 2 8.8.8.8 > /dev/null 2>&1
CONNECTIVITY_OK=$?

if [ "$CONNECTIVITY_OK" -ne 0 ]; then
    # ❌ Plus de connection sur WAN1 → basculement en FAILOVER
    if [ "$CURRENT_STATUS" != "FAILOVER" ]; then
        clean_iptables
        iptables -t nat -A POSTROUTING -o $WAN2 -j MASQUERADE
        iptables -A FORWARD -i $LAN -o $WAN2 -j ACCEPT
        iptables -A FORWARD -i $WAN2 -o $LAN -m state --state RELATED,ESTABLISHED -j ACCEPT
        echo "FAILOVER" > "$STATUS_FILE"
        log "❌ Perte de connexion → basculement vers WAN2"

        # Envoi de SMS
        if [ -n "$FREE_SMS_USER" ] && [ -n "$FREE_SMS_PASS" ]; then
            curl -s -G --data-urlencode "user=$FREE_SMS_USER" \
                       --data-urlencode "pass=$FREE_SMS_PASS" \
                       --data-urlencode "msg=[FAILOVER] Basculement WAN actif sur WAN2" \
                       https://smsapi.free-mobile.fr/sendmsg
        fi
    fi
    STATS_BACKUP=$(vnstat -i "$BACKUP_IF" --oneline | awk -F\; '{print $11}')
    update_state_json "$CURRENT_STATUS" "$STATS_BACKUP"

else
    # ✅ Connexion OK → retour à la normale
    if [ "$CURRENT_STATUS" == "FAILOVER" ]; then
        clean_iptables
        iptables -t nat -A POSTROUTING -o $WAN1 -j MASQUERADE
        iptables -A FORWARD -i $LAN -o $WAN1 -j ACCEPT
        iptables -A FORWARD -i $WAN1 -o $LAN -m state --state RELATED,ESTABLISHED -j ACCEPT
        echo "NORMAL" > "$STATUS_FILE"
        # RX=$(cat /sys/class/net/"$WAN2"/statistics/rx_bytes 2>/dev/null || echo 0)
        # TX=$(cat /sys/class/net/"$WAN2"/statistics/tx_bytes 2>/dev/null || echo 0)
        # RX_MB=$((RX / 1024 / 1024))
        # TX_MB=$((TX / 1024 / 1024))
        # DATA_MB=$((RX_MB + TX_MB))
        STATS_NOM=$(vnstat -i "$BACKUP_IF" --oneline | awk -F\; '{print $11}')


        log "✅ Connexion principale restaurée → retour à WAN1"
        # log "📊 Données utilisées pendant le failover : ${DATA_MB} MB"
        log "📊 Données utilisées pendant le failover : $STATS_BACKUP"


        # echo "$DATA_MB MB" > /opt/failover/data_usage.txt
        echo "$STATS" > /opt/failover/data_usage.txt

        # Envoi de SMS
        if [ -n "$FREE_SMS_USER" ] && [ -n "$FREE_SMS_PASS" ]; then
            curl -s -G --data-urlencode "user=$FREE_SMS_USER" \
                       --data-urlencode "pass=$FREE_SMS_PASS" \
                       --data-urlencode "msg=[FAILOVER] Retour sur connexion nominal. Données consommées : $STATS_BACKUP" \
                       https://smsapi.free-mobile.fr/sendmsg
        fi
    fi
fi
