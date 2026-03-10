#!/bin/bash

# ==============================================================================
# REMOTE SURVIVAL KIT - INSTALLER (Debian/Ubuntu)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "❌ Bitte starte das Installations-Skript mit sudo!"
  exit 1
fi

if [ ! -x "$(command -v apt)" ]; then
  echo "❌ Dieses Skript unterstützt aktuell nur Debian/Ubuntu basierte Systeme."
  exit 1
fi

echo "================================================="
echo "🚀 WILLKOMMEN BEIM REMOTE SURVIVAL KIT INSTALLER"
echo "================================================="
echo ""

# --- ROLLE ABFRAGEN ---
echo "Welche Rolle soll dieses Gerät übernehmen?"
echo "[1] PRIMARY NODE  (z.B. Raspberry Pi - läuft 24/7, überwacht Netzwerk)"
echo "[2] RECOVERY NODE (z.B. Beelink - wacht über BIOS auf, prüft Primary)"
read -p "Bitte wähle [1] oder [2]: " ROLE_CHOICE

if [ "$ROLE_CHOICE" == "1" ]; then
    NODE_ROLE="PRIMARY"
elif [ "$ROLE_CHOICE" == "2" ]; then
    NODE_ROLE="RECOVERY"
else
    echo "❌ Ungültige Eingabe. Abbruch."
    exit 1
fi

# --- NETZWERK ABFRAGEN ---
echo ""
echo "--- Netzwerkkonfiguration ---"
read -p "IP-Adresse des Routers (z.B. 192.168.178.1): " ROUTER_IP
read -p "IP-Adresse des Primary Nodes (z.B. Pi): " PRIMARY_NODE_IP
read -p "IP-Adresse des Recovery Nodes (z.B. Beelink): " RECOVERY_NODE_IP

if [ "$NODE_ROLE" == "PRIMARY" ]; then
    read -p "MAC-Adresse des Recovery Nodes (für Wake-on-LAN): " RECOVERY_NODE_MAC
else
    RECOVERY_NODE_MAC="NICHT_BENÖTIGT"
fi

# --- E-MAIL BENACHRICHTIGUNGEN ---
echo ""
echo "--- E-Mail Benachrichtigungen ---"
read -p "E-Mail Alarme aktivieren? (y/n): " EMAIL_CHOICE
if [[ "$EMAIL_CHOICE" == "y" || "$EMAIL_CHOICE" == "Y" ]]; then
    ENABLE_EMAIL="true"
    echo "HINWEIS: Nutze smtps:// für Port 465 oder smtp:// für Port 587 (STARTTLS)."
    read -p "SMTP Server URL (z.B. smtps://smtp.gmail.com:465): " SMTP_URL
    read -p "SMTP Benutzername (z.B. max@gmail.com): " SMTP_USER
    read -p "SMTP App-Passwort (kein normales Passwort!): " SMTP_PASS
    read -p "Absender E-Mail (From): " EMAIL_FROM
    read -p "Empfänger E-Mail (To): " EMAIL_TO
else
    ENABLE_EMAIL="false"
    SMTP_URL=""
    SMTP_USER=""
    SMTP_PASS=""
    EMAIL_FROM=""
    EMAIL_TO=""
fi

# --- TELEGRAM BENACHRICHTIGUNGEN ---
echo ""
echo "--- Telegram Benachrichtigungen ---"
read -p "Telegram Alarme aktivieren? (y/n): " TELEGRAM_CHOICE
if [[ "$TELEGRAM_CHOICE" == "y" || "$TELEGRAM_CHOICE" == "Y" ]]; then
    ENABLE_TELEGRAM="true"
    read -p "Telegram Bot Token: " TELEGRAM_BOT_TOKEN
    read -p "Telegram Chat ID: " TELEGRAM_CHAT_ID
else
    ENABLE_TELEGRAM="false"
    TELEGRAM_BOT_TOKEN=""
    TELEGRAM_CHAT_ID=""
fi

# --- SYSTEM-ORDNER & CONFIG ---
echo ""
echo "📦 Lege System-Verzeichnisse an..."
mkdir -p /etc/remote-survival
mkdir -p /usr/local/bin/remote-survival

echo "📝 Speichere Konfiguration..."
cat <<EOF > /etc/remote-survival/survival.conf
NODE_ROLE="$NODE_ROLE"
ROUTER_IP="$ROUTER_IP"
INTERNET_TEST_IP="8.8.8.8"
TAILSCALE_TEST_IP="100.100.100.100"
PRIMARY_NODE_IP="$PRIMARY_NODE_IP"
RECOVERY_NODE_IP="$RECOVERY_NODE_IP"
RECOVERY_NODE_MAC="$RECOVERY_NODE_MAC"

ENABLE_TAILSCALE_RESTART="true"
ENABLE_WATCHDOG="true"

ENABLE_EMAIL="$ENABLE_EMAIL"
SMTP_URL="$SMTP_URL"
SMTP_USER="$SMTP_USER"
SMTP_PASS="$SMTP_PASS"
EMAIL_FROM="$EMAIL_FROM"
EMAIL_TO="$EMAIL_TO"

ENABLE_TELEGRAM="$ENABLE_TELEGRAM"
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
EOF

chmod 600 /etc/remote-survival/survival.conf

# --- SKRIPTE & ABHÄNGIGKEITEN ---
echo "⚙️  Kopiere Überwachungs-Skripte..."
cp scripts/*.sh /usr/local/bin/remote-survival/
chmod +x /usr/local/bin/remote-survival/*.sh

if [ "$NODE_ROLE" == "PRIMARY" ]; then
    echo "⬇️  Installiere Wake-on-LAN Paket (falls nicht vorhanden)..."
    apt-get update -qq && apt-get install -y wakeonlan > /dev/null
    
    echo "🛡️  Aktiviere systemd Hardware-Watchdog (60 Sekunden)..."
    sed -i 's/^#RuntimeWatchdogSec=.*/RuntimeWatchdogSec=60s/' /etc/systemd/system.conf
    systemctl daemon-reexec
fi

# --- SYSTEMD DIENSTE ---
echo "⚙️  Richte Hintergrunddienste ein..."
cp systemd/*.service /etc/systemd/system/ 2>/dev/null
cp systemd/*.timer /etc/systemd/system/ 2>/dev/null
systemctl daemon-reload

if [ "$NODE_ROLE" == "PRIMARY" ]; then
    systemctl enable --now survival-primary.timer
    systemctl disable survival-recovery.timer 2>/dev/null
    echo "🟢 Primary Monitor & Hardware Watchdog aktiviert!"
elif [ "$NODE_ROLE" == "RECOVERY" ]; then
    systemctl enable --now survival-recovery.timer
    systemctl disable survival-primary.timer 2>/dev/null
    echo "🟢 Recovery Monitor aktiviert!"
fi

echo ""
echo "✅ INSTALLATION ABGESCHLOSSEN!"