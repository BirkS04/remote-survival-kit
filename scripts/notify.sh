#!/bin/bash

# Lade die Konfiguration
source /etc/remote-survival/survival.conf

MESSAGE="$1"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# ==========================================
# 1. LOKALES LOGBUCH (Immer aktiv)
# ==========================================
echo "[$TIMESTAMP] $MESSAGE" >> /var/log/remote-survival.log

# ==========================================
# 2. TELEGRAM (Optional)
# ==========================================
if [ "$ENABLE_TELEGRAM" == "true" ]; then
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
         -d chat_id="${TELEGRAM_CHAT_ID}" \
         -d text="🚨 Remote Survival: $MESSAGE" > /dev/null
fi

# ==========================================
# 3. E-MAIL PER SMTP (Optional)
# ==========================================
if [ "$ENABLE_EMAIL" == "true" ]; then
    # Wir erstellen eine kleine temporäre Textdatei für den Mail-Inhalt, 
    # da E-Mails "Header" (Von, An, Betreff) benötigen.
    MAIL_FILE=$(mktemp)
    
    cat <<EOF > "$MAIL_FILE"
From: "Remote Survival Pi" <$EMAIL_FROM>
To: <$EMAIL_TO>
Subject: 🚨 Alarm: Remote Node Status

System-Meldung ($TIMESTAMP):
$MESSAGE
EOF

    # Sende die E-Mail via curl über den SMTP-Server
    curl -s --ssl-reqd \
         --url "$SMTP_URL" \
         --user "$SMTP_USER:$SMTP_PASS" \
         --mail-from "$EMAIL_FROM" \
         --mail-rcpt "$EMAIL_TO" \
         --upload-file "$MAIL_FILE" > /dev/null

    # Temporäre Datei wieder löschen
    rm -f "$MAIL_FILE"
fi