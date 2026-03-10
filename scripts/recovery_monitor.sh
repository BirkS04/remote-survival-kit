#!/bin/bash
source /etc/remote-survival/survival.conf
DIR="/usr/local/bin/remote-survival"

# Kurz warten, falls Netzwerk gerade erst initialisiert wurde
sleep 10

# Prüfen, ob der Pi (Primary) antwortet
if ! ping -c 3 -W 3 "$PRIMARY_NODE_IP" > /dev/null 2>&1; then
    # SZNENARIO A: PI IST TOT
    $DIR/notify.sh "Recovery: ⚠️ Primary Node ($PRIMARY_NODE_IP) ist OFFLINE! Ich bleibe wach als Fallback."
    # Er macht hier nichts weiter, außer AN zu bleiben, damit du per Tailscale drauf kommst.
else
    # SZENARIO B: PI LEBT. Braucht man mich gerade?
    # Prüfe, ob aktuell ein User per SSH (Tailscale) angemeldet ist
    if who | grep -v "localhost" | grep -q "pts"; then
        echo "$(date) - Pi lebt, ABER jemand ist per SSH eingeloggt. Ich bleibe an." >> /var/log/remote-survival.log
    else
        echo "$(date) - Pi lebt und niemand arbeitet hier. Gehe wieder schlafen." >> /var/log/remote-survival.log
        # Fahre in 1 Minute herunter, um Strom zu sparen
        shutdown -h +1 "Auto-Shutdown: Primary is alive, no user logged in."
    fi
fi