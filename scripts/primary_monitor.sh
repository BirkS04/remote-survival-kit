#!/bin/bash

# ==========================================
# 1. KONFIGURATION
# ==========================================
source /etc/remote-survival/survival.conf

STRIKE_FILE="/tmp/remote_survival_strikes"
MAX_STRIKES=3
RECOVERY_FLAG_FILE="/etc/remote-survival/recovery_active.flag"

# Nutze den sauberen SSH Alias (wurde in install.sh in ~/.ssh/config angelegt!)
RECOVERY_SSH_TARGET="$RECOVERY_ALIAS"

# ==========================================
# 2. SENSOREN (Nur prüfen, nichts verändern)
# ==========================================

check_ping() {
    local target_ip="$1"
    if ping -c 2 -W 2 "$target_ip" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

check_daemon_active() {
    local daemon_name="$1"
    if systemctl is-active --quiet "$daemon_name"; then
        return 0
    else
        return 1
    fi
}

get_public_ip() {
    local ipv4=$(curl -s -4 --max-time 3 ident.me)
    local ipv6=$(curl -s -6 --max-time 3 ident.me)
    local result=""
    
    if [ -n "$ipv4" ]; then result="IPv4: $ipv4"; else result="IPv4: N/A"; fi
    if [ -n "$ipv6" ]; then result="$result | IPv6: $ipv6"; else result="$result | IPv6: N/A"; fi

    echo "$result"
}

# ==========================================
# 3. AKTOREN (Dinge ausführen/verändern)
# ==========================================

restart_service() {
    local daemon_name="$1"
    systemctl restart "$daemon_name" 2>/dev/null
}

send_alert() {
    local message="$1"
    /usr/local/bin/remote-survival/notify.sh "$message"
}

manage_strikes() {
    local action="$1"
    local current=0
    
    if [ -f "$STRIKE_FILE" ]; then
        current=$(cat "$STRIKE_FILE")
    fi

    if [ "$action" == "reset" ]; then
        echo "0" > "$STRIKE_FILE"
    elif [ "$action" == "increase" ]; then
        current=$((current + 1))
        echo "$current" > "$STRIKE_FILE"
        echo "$current"
    fi
}

system_reboot() {
    /sbin/reboot
}

# --- FAILOVER FUNKTIONEN ---
trigger_failover() {
    echo "🚨 Triggere Failover zum Beelink..."
    
    if [ "$RECOVERY_NODE_MAC" != "NICHT_BENÖTIGT" ]; then
        wakeonlan "$RECOVERY_NODE_MAC" > /dev/null 2>&1
    fi

    local timeout=45
    local elapsed=0
    
    while [ "$elapsed" -lt "$timeout" ]; do
        # BatchMode=yes verhindert Hängenbleiben bei Passwortabfragen.
        if ssh -o BatchMode=yes -o ConnectTimeout=2 "$RECOVERY_SSH_TARGET" "touch ${RECOVERY_FLAG_FILE}" 2>/dev/null; then
            send_alert "✅ Failover erfolgreich: Beelink ist wach und Flag gesetzt!"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    send_alert "❌ Failover fehlgeschlagen: Beelink nicht per SSH erreichbar."
}

clear_failover_flag() {
    ssh -o BatchMode=yes -o ConnectTimeout=2 "$RECOVERY_SSH_TARGET" "rm -f ${RECOVERY_FLAG_FILE}" 2>/dev/null
}

# ==========================================
# 4. DAS GEHIRN (Main Loop)
# ==========================================

main() {
    # --- PHASE 1: Der "Happy Path" ---
    if check_ping "$TAILSCALE_TEST_IP"; then
        manage_strikes "reset"
        clear_failover_flag
        exit 0
    fi

    # --- PHASE 2: Der "Fast-Track" (Tailscale ist gecrasht) ---
    if ! check_daemon_active "tailscaled"; then
        restart_service "tailscaled"
        sleep 15
        
        if check_ping "$TAILSCALE_TEST_IP"; then
            manage_strikes "reset"
            clear_failover_flag
            exit 0
        fi
    fi

    # --- PHASE 3: Tiefen-Diagnose ---
    local error_cause=""
    
    if ! check_ping "$ROUTER_IP"; then
        error_cause="LOKALES_NETZWERK_TOT"
    elif ! check_ping "$INTERNET_TEST_IP"; then
        error_cause="PROVIDER_OFFLINE"
        exit 0
    else
        error_cause="TAILSCALE_DEADLOCK"
    fi

    # --- PHASE 4 & 5: Out-of-Band Alarm & Eskalation ---
    local current_strikes=$(manage_strikes "increase")

    if [ "$error_cause" == "TAILSCALE_DEADLOCK" ]; then
        local pub_ip=$(get_public_ip)
        send_alert "⚠️ Tailscale blockiert! (Strike: $current_strikes/$MAX_STRIKES). Notfall-IPs -> $pub_ip"
    
    elif [ "$error_cause" == "LOKALES_NETZWERK_TOT" ]; then
        send_alert "⚠️ Lokales Netzwerk abgerissen! (Strike: $current_strikes/$MAX_STRIKES)"
    fi

    # --- STRIKE-AUSWERTUNG ---
    if [ "$current_strikes" -ge "$MAX_STRIKES" ]; then
        send_alert "🚨 Maximale Strikes erreicht ($MAX_STRIKES). Führe sauberen Hardware-Reboot durch!"
        trigger_failover
        sleep 5
        system_reboot
    else
        restart_service "tailscaled"
        
        if [ "$error_cause" == "LOKALES_NETZWERK_TOT" ]; then
            restart_service "NetworkManager"
        fi
    fi
}

main