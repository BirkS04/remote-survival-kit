#!/bin/bash

# ==========================================
# 1. KONFIGURATION
# ==========================================
source /etc/remote-survival/survival.conf

STRIKE_FILE="/tmp/remote_survival_strikes"
MAX_STRIKES=3

echo "DEBUG: [CONFIG] Konfiguration geladen."

# ==========================================
# 2. SENSOREN (Nur prüfen, nichts verändern)
# ==========================================

check_ping() {
    local target_ip="$1"
    echo "DEBUG: [SENSOR] Pinge $target_ip ..." >&2
    if ping -c 2 -W 2 "$target_ip" > /dev/null 2>&1; then
        echo "DEBUG: [SENSOR] -> Ping erfolgreich!" >&2
        return 0
    else
        echo "DEBUG: [SENSOR] -> Ping FEHLGESCHLAGEN!" >&2
        return 1
    fi
}

check_daemon_active() {
    local daemon_name="$1"
    echo "DEBUG: [SENSOR] Prüfe Status von Daemon '$daemon_name'..." >&2
    if systemctl is-active --quiet "$daemon_name"; then
        echo "DEBUG: [SENSOR] -> Daemon ist 'active' (läuft)." >&2
        return 0
    else
        echo "DEBUG: [SENSOR] -> Daemon ist NICHT active (abgestürzt)!" >&2
        return 1
    fi
}

get_public_ip() {
    # Holt IPv4 und IPv6 mit 3 Sekunden Timeout (verhindert Hänger)
    local ipv4=$(curl -s -4 --max-time 3 ident.me)
    local ipv6=$(curl -s -6 --max-time 3 ident.me)

    local result=""
    
    if [ -n "$ipv4" ]; then
        result="IPv4: $ipv4"
    else
        result="IPv4: N/A"
    fi

    if [ -n "$ipv6" ]; then
        result="$result | IPv6: $ipv6"
    else
        result="$result | IPv6: N/A"
    fi

    echo "$result"
}

# ==========================================
# 3. AKTOREN (Dinge ausführen/verändern)
# ==========================================

restart_service() {
    local daemon_name="$1"
    # systemctl restart "$daemon_name" 2>/dev/null
    echo "DEBUG: [AKTOR] (SIMULIERT) Starte Dienst '$daemon_name' neu."
}

send_alert() {
    local message="$1"
    echo "DEBUG: [AKTOR] Sende Alarm: $message"
    # /usr/local/bin/remote-survival/notify.sh "$message"
}

manage_strikes() {
    local action="$1"
    local current=0
    
    if [ -f "$STRIKE_FILE" ]; then
        current=$(cat "$STRIKE_FILE")
    fi

    if [ "$action" == "reset" ]; then
        echo "0" > "$STRIKE_FILE"
        echo "DEBUG: [AKTOR] Strikes wurden auf 0 zurückgesetzt." >&2
    elif [ "$action" == "increase" ]; then
        current=$((current + 1))
        echo "$current" > "$STRIKE_FILE"
        echo "DEBUG: [AKTOR] Strikes erhöht auf: $current" >&2
        echo "$current" # WICHTIG: Rückgabewert für das Skript
    fi
}

system_reboot() {
    echo "DEBUG: [AKTOR] (SIMULIERT) BUMM! Führe echten System-Reboot durch!"
    # /sbin/reboot
}

# ==========================================
# 4. DAS GEHIRN (Main Loop)
# ==========================================

main() {
    echo "========================================"
    echo "DEBUG: === STARTE NEUEN DURCHLAUF ==="
    echo "========================================"
    
    # --- PHASE 1: Der "Happy Path" ---
    echo "DEBUG: [PHASE 1] Prüfe den 'Happy Path' (Tailscale Ping)..."
    if check_ping "$TAILSCALE_TEST_IP"; then
        echo "DEBUG: [PHASE 1] Alles läuft perfekt! Beende Skript."
        manage_strikes "reset"
        exit 0
    fi
    echo "DEBUG: [PHASE 1] Fehler! Tailscale antwortet nicht. Gehe zu Phase 2."

    # --- PHASE 2: Der "Fast-Track" (Tailscale ist gecrasht) ---
    echo "DEBUG: [PHASE 2] Prüfe Fast-Track (Ist nur die App abgestürzt?)"
    if ! check_daemon_active "tailscaled"; then
        echo "DEBUG: [PHASE 2] App ist abgestürzt. Versuche Schnell-Reparatur..."
        restart_service "tailscaled"
        echo "DEBUG: [PHASE 2] Warte 15 Sekunden auf Reconnect..."
        # sleep 15  <-- Für den Test auskommentieren, sonst wartest du ewig auf die Ausgabe
        
        echo "DEBUG: [PHASE 2] Prüfe Ping nach Neustart..."
        if check_ping "$TAILSCALE_TEST_IP"; then
            echo "DEBUG: [PHASE 2] Fast-Track war erfolgreich! Beende Skript."
            manage_strikes "reset"
            exit 0
        fi
        echo "DEBUG: [PHASE 2] Fast-Track hat nicht geholfen."
    else
        echo "DEBUG: [PHASE 2] App läuft noch. Problem liegt tiefer. Überspringe Fast-Track."
    fi

    # --- PHASE 3: Tiefen-Diagnose ---
    echo "DEBUG: [PHASE 3] Starte Tiefen-Diagnose..."
    local error_cause=""
    
    if ! check_ping "$ROUTER_IP"; then
        echo "DEBUG: [PHASE 3] Fehlerursache: Router weg!"
        error_cause="LOKALES_NETZWERK_TOT"
    elif ! check_ping "$INTERNET_TEST_IP"; then
        echo "DEBUG: [PHASE 3] Fehlerursache: Internet weg (ISP Ausfall)!"
        error_cause="PROVIDER_OFFLINE"
        echo "DEBUG: Wir können das Internet nicht fixen. Abwarten. Skript beendet."
        exit 0
    else
        echo "DEBUG: [PHASE 3] Fehlerursache: Router und Internet gehen. Reines VPN Problem!"
        error_cause="TAILSCALE_DEADLOCK"
    fi

    # --- PHASE 4 & 5: Out-of-Band Alarm & Eskalation ---
    echo "DEBUG: [PHASE 4] Ermittle Strikes und sende Alarm..."
    local current_strikes=$(manage_strikes "increase")

    if [ "$error_cause" == "TAILSCALE_DEADLOCK" ]; then
        local pub_ip=$(get_public_ip)
        send_alert "⚠️ Tailscale blockiert! (Strike: $current_strikes/$MAX_STRIKES). Notfall-IP: $pub_ip"
    
    elif [ "$error_cause" == "LOKALES_NETZWERK_TOT" ]; then
        send_alert "⚠️ Lokales Netzwerk abgerissen! (Strike: $current_strikes/$MAX_STRIKES)"
    fi

    # --- STRIKE-AUSWERTUNG ---
    echo "DEBUG: [PHASE 5] Werte Strikes aus..."
    if [ "$current_strikes" -ge "$MAX_STRIKES" ]; then
        echo "DEBUG: [PHASE 5] ESKALATION! Maximale Strikes erreicht."
        send_alert "🚨 Maximale Strikes erreicht ($MAX_STRIKES). Reboot!"
        system_reboot
    else
        echo "DEBUG: [PHASE 5] Soft-Reparatur läuft (noch nicht eskaliert)."
        restart_service "tailscaled"
        
        if [ "$error_cause" == "LOKALES_NETZWERK_TOT" ]; then
            restart_service "NetworkManager"
        fi
    fi
    echo "DEBUG: === DURCHLAUF BEENDET ==="
    echo "========================================"
}

# Starte das Gehirn
main