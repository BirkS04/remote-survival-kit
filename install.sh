#!/bin/bash

# ==============================================================================
# REMOTE SURVIVAL KIT - INSTALLER (Debian/Ubuntu Edition)
# ==============================================================================

# 1. PRE-FLIGHT CHECKS
if [ "$EUID" -ne 0 ]; then
  echo "❌ Bitte starte das Installations-Skript mit sudo!"
  exit 1
fi

if [ ! -x "$(command -v apt)" ]; then
  echo "❌ Dieses Skript unterstützt aktuell nur Debian/Ubuntu basierte Systeme (z.B. Raspberry Pi OS, Ubuntu)."
  exit 1
fi

echo "================================================="
echo "🚀 WILLKOMMEN BEIM REMOTE SURVIVAL KIT INSTALLER"
echo "================================================="
echo ""

# 2. ROLLE ABFRAGEN
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

# 3. VARIABLEN ABFRAGEN
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

echo ""
echo "--- Benachrichtigungen ---"
read -p "Telegram-Benachrichtigungen aktivieren? (y/n): " TELEGRAM_CHOICE
if [[ "$TELEGRAM_CHOICE" == "y" || "$TELEGRAM_CHOICE" == "Y" ]]; then
    ENABLE_TELEGRAM="true"
    read -p "Telegram Bot Token: " TELEGRAM_BOT_TOKEN
    read -p "Telegram Chat ID: " TELEGRAM_CHAT_ID
else
    ENABLE_TELEGRAM="false"
    TELEGRAM_BOT_TOKEN=""
    TELEGRAM_CHAT_ID=""
fi

# 4. SYSTEM-ORDNER ERSTELLEN
echo ""
echo "📦 Lege System-Verzeichnisse an..."
mkdir -p /etc/remote-survival
mkdir -p /usr/local/bin/remote-survival

# 5. KONFIGURATIONS-DATEI SCHREIBEN
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
ENABLE_TELEGRAM="$ENABLE_TELEGRAM"
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
EOF
chmod 600 /etc/remote-survival/survival.conf

# 6. SKRIPTE KOPIEREN & ABHÄNGIGKEITEN INSTALLIEREN
echo "⚙️  Kopiere Überwachungs-Skripte..."
cp scripts/*.sh /usr/local/bin/remote-survival/
chmod +x /usr/local/bin/remote-survival/*.sh

if [ "$NODE_ROLE" == "PRIMARY" ]; then
    echo "⬇️  Installiere Wake-on-LAN Paket..."
    apt-get update -qq && apt-get install -y wakeonlan > /dev/null
    
    # HARDWARE WATCHDOG AKTIVIEREN (Die magische Kern-Absicherung)
    echo "🛡️  Aktiviere systemd Hardware-Watchdog..."
    # Wenn der Kernel 15 Sekunden lang nicht antwortet, wird der Strom hart gekappt.
    sed -i 's/^#RuntimeWatchdogSec=.*/RuntimeWatchdogSec=15s/' /etc/systemd/system.conf
    # Lädt die systemd Konfiguration neu, um den Watchdog sofort scharf zu schalten
    systemctl daemon-reexec
fi

# 7. SYSTEMD DIENSTE INSTALLIEREN
echo "⚙️  Richte Hintergrunddienste ein..."
cp systemd/*.service /etc/systemd/system/
cp systemd/*.timer /etc/systemd/system/
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