#!/bin/bash
source /etc/remote-survival/survival.conf
DIR="/usr/local/bin/remote-survival"
STRIKE_FILE="/tmp/remote_survival_strikes"

# Lese aktuelle Strikes aus (Standard ist 0)
STRIKES=$(cat "$STRIKE_FILE" 2>/dev/null || echo "0")
NEW_STRIKES=$STRIKES
NEEDS_RESTART=false

# ==========================================
# TEST 1: ROUTER / LOKALES NETZWERK
# ==========================================
if ! ping -c 2 -W 2 "$ROUTER_IP" > /dev/null 2>&1; then
    echo "$(date) - Primary: Router ($ROUTER_IP) nicht erreichbar!" >> /var/log/remote-survival.log
    NEEDS_RESTART=true
fi

# ==========================================
# TEST 2: INTERNET (ISP DOWN?)
# ==========================================
INTERNET_OK=true
if ! ping -c 2 -W 2 "$INTERNET_TEST_IP" > /dev/null 2>&1; then
    INTERNET_OK=false
    echo "$(date) - Primary: Kein Internet (ISP down?). Überspringe Tailscale-Test." >> /var/log/remote-survival.log
fi

# ==========================================
# TEST 3: TAILSCALE (Nur wenn Internet da ist)
# ==========================================
if [ "$INTERNET_OK" == "true" ] && [ "$ENABLE_TAILSCALE_RESTART" == "true" ]; then
    # Wir prüfen nicht nur den Status, sondern pingen DURCH den Tunnel
    if ! ping -c 2 -W 2 "$TAILSCALE_TEST_IP" > /dev/null 2>&1; then
        echo "$(date) - Primary: Tailscale ($TAILSCALE_TEST_IP) antwortet nicht!" >> /var/log/remote-survival.log
        NEEDS_RESTART=true
    fi
fi

# ==========================================
# ESKALATIONS-LOGIK (Das Strike-System)
# ==========================================
if [ "$NEEDS_RESTART" == "true" ]; then
    NEW_STRIKES=$((STRIKES + 1))
    echo "$NEW_STRIKES" > "$STRIKE_FILE"

    if [ "$NEW_STRIKES" -ge 3 ]; then
        # 3 Strikes erreicht -> HARTER REBOOT
        $DIR/notify.sh "Primary: 🚨 3 Strikes erreicht! Lokales Netz oder VPN dauerhaft tot. Führe SYSTEM-REBOOT durch!"
        sleep 5
        /sbin/reboot
        exit 0
    else
        # 1 oder 2 Strikes -> DIENSTE NEUSTARTEN
        $DIR/notify.sh "Primary: Netzwerk/VPN Fehler (Strike $NEW_STRIKES/3). Starte Dienste neu..."
        systemctl restart NetworkManager 2>/dev/null
        systemctl restart tailscaled 2>/dev/null
    fi
else
    # ALLES OK -> Reset Strikes auf 0
    if [ "$STRIKES" -gt 0 ]; then
        $DIR/notify.sh "Primary: ✅ System hat sich erholt. Strike-Counter zurückgesetzt."
    fi
    echo "0" > "$STRIKE_FILE"
fi