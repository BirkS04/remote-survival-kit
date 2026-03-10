#!/bin/bash

# ==============================================================================
# REMOTE SURVIVAL KIT - UNINSTALLER
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "❌ Bitte starte das Deinstallations-Skript mit sudo!"
  exit 1
fi

echo "================================================="
echo "🗑️ DEINSTALLIERE REMOTE SURVIVAL KIT..."
echo "================================================="

# 1. Systemd Dienste und Timer stoppen
echo "⏹️  Stoppe Hintergrunddienste..."
systemctl stop survival-primary.timer 2>/dev/null
systemctl disable survival-primary.timer 2>/dev/null
systemctl stop survival-primary.service 2>/dev/null

systemctl stop survival-recovery.timer 2>/dev/null
systemctl disable survival-recovery.timer 2>/dev/null
systemctl stop survival-recovery.service 2>/dev/null

# 2. Systemd Dateien entfernen
echo "🗑️  Lösche Systemd Konfigurationen..."
rm -f /etc/systemd/system/survival-primary.*
rm -f /etc/systemd/system/survival-recovery.*
systemctl daemon-reload

# 3. Skripte und Konfigurationen entfernen
echo "🗑️  Lösche Programm-Dateien und Konfigurationen..."
rm -rf /usr/local/bin/remote-survival
rm -rf /etc/remote-survival

# 4. Watchdog aus OS Kernel entfernen (nur Debian/Ubuntu)
echo "🛡️  Deaktiviere Hardware Watchdog..."
sed -i 's/^RuntimeWatchdogSec=15s/#RuntimeWatchdogSec=15s/' /etc/systemd/system.conf 2>/dev/null
# Setze Watchdog-Einstellung auf Standard zurück
sed -i 's/^RuntimeWatchdogSec=60s/#RuntimeWatchdogSec=/' /etc/systemd/system.conf 2>/dev/null
systemctl daemon-reexec

# 5. Temporäre Dateien säubern
rm -f /tmp/remote_survival_strikes
rm -f /var/log/remote-survival.log

echo ""
echo "✅ Deinstallation erfolgreich! Alle Spuren wurden beseitigt."