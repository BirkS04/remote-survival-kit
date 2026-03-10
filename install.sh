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

ACTUAL_USER=${SUDO_USER:-$USER}

echo "================================================="
echo "🚀 WILLKOMMEN BEIM REMOTE SURVIVAL KIT INSTALLER"
echo "================================================="
echo ""

# --- ALTE KONFIGURATION LADEN (FALLS VORHANDEN) ---
CONF_FILE="/etc/remote-survival/survival.conf"
if [ -f "$CONF_FILE" ]; then
    echo "📝 Bestehende Konfiguration gefunden! Werte werden voreingetragen (Drücke einfach ENTER zum Übernehmen)."
    source "$CONF_FILE"
fi

if [ -z "$AUTO_ROLE" ]; then

    echo "Welche Rolle soll dieses Gerät übernehmen?"
    echo "[1] PRIMARY NODE  (z.B. Raspberry Pi - läuft 24/7, überwacht Netzwerk)"
    echo "[2] RECOVERY NODE (z.B. Beelink - wacht über BIOS auf, prüft Primary)"
    
    DEF_ROLE="1"
    if [ "$NODE_ROLE" == "RECOVERY" ]; then DEF_ROLE="2"; fi
    
    read -e -p "Bitte wähle [1] oder [2]: " -i "$DEF_ROLE" ROLE_CHOICE

    if [ "$ROLE_CHOICE" == "1" ]; then NODE_ROLE="PRIMARY"; else NODE_ROLE="RECOVERY"; fi

    echo ""
    echo "--- Netzwerkkonfiguration (WICHTIG: Nutze lokale IPs, keine Tailscale-IPs!) ---"
    read -e -p "IP-Adresse des Routers (z.B. 192.168.178.1): " -i "${ROUTER_IP:-192.168.178.1}" ROUTER_IP
    read -e -p "LOKALE IP des Primary Nodes (z.B. Pi): " -i "${PRIMARY_NODE_IP:-192.168.178.100}" PRIMARY_NODE_IP
    read -e -p "LOKALE IP des Recovery Nodes (z.B. Beelink): " -i "${RECOVERY_NODE_IP:-192.168.178.101}" RECOVERY_NODE_IP

    if [ "$NODE_ROLE" == "PRIMARY" ]; then
        read -e -p "MAC-Adresse des Recovery Nodes (für Wake-on-LAN): " -i "${RECOVERY_NODE_MAC:-00:11:22:33:44:55}" RECOVERY_NODE_MAC
    else
        RECOVERY_NODE_MAC="NICHT_BENÖTIGT"
    fi

    echo ""
    echo "--- SSH Benutzer (User-to-User Brücke) ---"
    read -e -p "Dein SSH-Benutzername auf dem Primary Node: " -i "${PRIMARY_SSH_USER:-$ACTUAL_USER}" PRIMARY_SSH_USER
    read -e -p "Dein SSH-Benutzername auf dem Recovery Node: " -i "${RECOVERY_SSH_USER:-ubuntu}" RECOVERY_SSH_USER

    echo ""
    echo "--- Benachrichtigungen ---"
    DEF_EMAIL_CHOICE="n"; [ "$ENABLE_EMAIL" == "true" ] && DEF_EMAIL_CHOICE="y"
    read -e -p "E-Mail Alarme aktivieren? (y/n): " -i "$DEF_EMAIL_CHOICE" EMAIL_CHOICE
    if [[ "$EMAIL_CHOICE" == "y" || "$EMAIL_CHOICE" == "Y" ]]; then
        ENABLE_EMAIL="true"
        read -e -p "SMTP Server URL: " -i "${SMTP_URL:-smtps://smtp.gmail.com:465}" SMTP_URL
        read -e -p "SMTP Benutzername: " -i "$SMTP_USER" SMTP_USER
        read -e -p "SMTP App-Passwort: " -i "$SMTP_PASS" SMTP_PASS
        read -e -p "Absender E-Mail: " -i "${EMAIL_FROM:-$SMTP_USER}" EMAIL_FROM
        read -e -p "Empfänger E-Mail: " -i "${EMAIL_TO:-$SMTP_USER}" EMAIL_TO
    else
        ENABLE_EMAIL="false"
    fi

    DEF_TELEGRAM_CHOICE="n"; [ "$ENABLE_TELEGRAM" == "true" ] && DEF_TELEGRAM_CHOICE="y"
    read -e -p "Telegram Alarme aktivieren? (y/n): " -i "$DEF_TELEGRAM_CHOICE" TELEGRAM_CHOICE
    if [[ "$TELEGRAM_CHOICE" == "y" || "$TELEGRAM_CHOICE" == "Y" ]]; then
        ENABLE_TELEGRAM="true"
        read -e -p "Telegram Bot Token: " -i "$TELEGRAM_BOT_TOKEN" TELEGRAM_BOT_TOKEN
        read -e -p "Telegram Chat ID: " -i "$TELEGRAM_CHAT_ID" TELEGRAM_CHAT_ID
    else
        ENABLE_TELEGRAM="false"
    fi

    echo ""
    echo "📦 Speichere Konfiguration..."
    mkdir -p /etc/remote-survival
    mkdir -p /usr/local/bin/remote-survival

    cat <<EOF > /etc/remote-survival/survival.conf
NODE_ROLE="$NODE_ROLE"
ROUTER_IP="$ROUTER_IP"
INTERNET_TEST_IP="8.8.8.8"
TAILSCALE_TEST_IP="100.100.100.100"
PRIMARY_NODE_IP="$PRIMARY_NODE_IP"
RECOVERY_NODE_IP="$RECOVERY_NODE_IP"
RECOVERY_NODE_MAC="$RECOVERY_NODE_MAC"

PRIMARY_SSH_USER="$PRIMARY_SSH_USER"
RECOVERY_SSH_USER="$RECOVERY_SSH_USER"

# ALIAS NAMEN
PRIMARY_ALIAS="primary"
RECOVERY_ALIAS="recovery"

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

else
    NODE_ROLE="$AUTO_ROLE"
    echo "🤖 Automatischer Modus: Installiere als '$NODE_ROLE'"
    mkdir -p /etc/remote-survival
    mv /tmp/survival.conf /etc/remote-survival/survival.conf
    sed -i 's/^NODE_ROLE=.*/NODE_ROLE="RECOVERY"/' /etc/remote-survival/survival.conf
    chmod 600 /etc/remote-survival/survival.conf
    source /etc/remote-survival/survival.conf
fi

echo "⚙️  Kopiere Überwachungs-Skripte..."
mkdir -p /usr/local/bin/remote-survival
cp scripts/*.sh /usr/local/bin/remote-survival/ 2>/dev/null
chmod +x /usr/local/bin/remote-survival/*.sh

if [ "$NODE_ROLE" == "RECOVERY" ]; then
    echo "🛡️  Setze strikte Ordnerrechte für das Flag-System..."
    chown -R "$RECOVERY_SSH_USER":"$RECOVERY_SSH_USER" /etc/remote-survival
    echo "$RECOVERY_SSH_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart tailscaled" > /etc/sudoers.d/remote-survival-tailscale
    chmod 0440 /etc/sudoers.d/remote-survival-tailscale
fi

if [ "$NODE_ROLE" == "PRIMARY" ]; then
    apt-get update -qq && apt-get install -y wakeonlan > /dev/null
    sed -i 's/^#RuntimeWatchdogSec=.*/RuntimeWatchdogSec=60s/' /etc/systemd/system.conf
    systemctl daemon-reexec
fi

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
echo "✅ LOKALE INSTALLATION ABGESCHLOSSEN!"


if [ "$NODE_ROLE" == "PRIMARY" ] && [ -z "$AUTO_ROLE" ]; then
    echo ""
    echo "================================================="
    echo "🌐 REMOTE DEPLOYMENT (RECOVERY NODE EINRICHTEN)"
    echo "================================================="
    read -e -p "Möchtest du den Recovery Node (Beelink) jetzt automatisch mit-einrichten? (y/n): " -i "y" AUTO_DEPLOY
    
    if [[ "$AUTO_DEPLOY" == "y" || "$AUTO_DEPLOY" == "Y" ]]; then
        
        echo "🔑 Schritt 1: Richte System-SSH-Zugriff ($PRIMARY_SSH_USER -> $RECOVERY_SSH_USER) ein..."
        chmod +x check_and_install_ssh.sh
        
        sudo -u "$PRIMARY_SSH_USER" env \
            TARGET_IP="$RECOVERY_NODE_IP" \
            TARGET_USER="$RECOVERY_SSH_USER" \
            TARGET_ALIAS="$RECOVERY_ALIAS" \
            TARGET_PORT="22" \
            SECURE_CHOICE="n" \
            bash ./check_and_install_ssh.sh
            
        echo "✅ SSH-Brücke (HINWEG) steht!"
        
        echo "🔑 Schritt 2: Baue sicheren Rückweg (Beelink -> Pi) auf..."
        
        sudo -u "$PRIMARY_SSH_USER" ssh -t "$RECOVERY_ALIAS" "
            mkdir -p ~/.ssh
            chmod 700 ~/.ssh
            [ ! -f ~/.ssh/id_ed25519 ] && ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -q
            
            cat <<EOF > ~/.ssh/config
Host $PRIMARY_ALIAS
    HostName $PRIMARY_NODE_IP
    User $PRIMARY_SSH_USER
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
EOF
            chmod 600 ~/.ssh/config
        "
        
        BEELINK_PUBKEY=$(sudo -u "$PRIMARY_SSH_USER" ssh "$RECOVERY_ALIAS" "cat ~/.ssh/id_ed25519.pub" | tr -d '\r')
        
        sudo -u "$PRIMARY_SSH_USER" mkdir -p "/home/$PRIMARY_SSH_USER/.ssh"
        sudo -u "$PRIMARY_SSH_USER" touch "/home/$PRIMARY_SSH_USER/.ssh/authorized_keys"
        if [ -n "$BEELINK_PUBKEY" ] && ! grep -q "$BEELINK_PUBKEY" "/home/$PRIMARY_SSH_USER/.ssh/authorized_keys"; then
            echo "$BEELINK_PUBKEY" | sudo -u "$PRIMARY_SSH_USER" tee -a "/home/$PRIMARY_SSH_USER/.ssh/authorized_keys" >/dev/null
        fi
        
        echo "📦 Pushe Repo auf $RECOVERY_ALIAS..."
        sudo -u "$PRIMARY_SSH_USER" ssh "$RECOVERY_ALIAS" "mkdir -p /tmp/remote-survival-setup"
        sudo -u "$PRIMARY_SSH_USER" scp -r ./* "$RECOVERY_ALIAS":/tmp/remote-survival-setup/
        sudo -u "$PRIMARY_SSH_USER" scp /etc/remote-survival/survival.conf "$RECOVERY_ALIAS":/tmp/survival.conf
        
        echo "⚙️  Führe lautlose Installation auf dem Beelink aus..."
        echo "⚠️  Bitte gib jetzt das Sudo-Passwort für '$RECOVERY_SSH_USER' (Beelink) ein, um die Installation dort abzuschließen!"
        sudo -u "$PRIMARY_SSH_USER" ssh -t "$RECOVERY_ALIAS" "cd /tmp/remote-survival-setup && sudo env AUTO_ROLE=RECOVERY ./install.sh"
        
        sudo -u "$PRIMARY_SSH_USER" ssh "$RECOVERY_ALIAS" "rm -rf /tmp/remote-survival-setup /tmp/survival.conf"
        echo "🎉 ZERO-TOUCH DEPLOYMENT ERFOLGREICH ABGESCHLOSSEN!"
    fi
fi