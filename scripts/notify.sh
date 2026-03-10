#!/bin/bash
# Lade die Konfiguration
source /etc/remote-survival/survival.conf

MESSAGE="$1"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# 1. Immer lokal ins Log schreiben
echo "[$TIMESTAMP] $MESSAGE" >> /var/log/remote-survival.log

# 2. Telegram senden (nur wenn in Config aktiviert)
if [ "$ENABLE_TELEGRAM" == "true" ]; then
    # -s für silent, leitet Ausgabe ins Nichts um
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
         -d chat_id="${TELEGRAM_CHAT_ID}" \
         -d text="🚨 Remote Survival Kit: $MESSAGE" > /dev/null
fi