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

# Der echte User, der sudo ausgeführt hat (wichtig, falls der Pi Keys anlegt)
ACTUAL_USER=${SUDO_USER:-$USER}

echo "================================================="
echo "🚀 WILLKOMMEN BEIM REMOTE SURVIVAL KIT INSTALLER"
echo "================================================="
echo ""

# ==============================================================================
# PHASE 1: KONFIGURATION ABFRAGEN (Läuft nur interaktiv auf dem Pi)
# ==============================================================================

if [ -z "$AUTO_ROLE" ]; then

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

    # --- NEU: SSH BENUTZER ABFRAGEN (Für die bi-direktionale Brücke) ---
    echo ""
    echo "--- SSH Benutzer (Wichtig für das automatische Failover) ---"
    read -p "Dein SSH-Benutzername auf dem Primary Node (hier, z.B. $ACTUAL_USER): " PRIMARY_SSH_USER
    PRIMARY_SSH_USER=${PRIMARY_SSH_USER:-$ACTUAL_USER}
    read -p "Dein SSH-Benutzername auf dem Recovery Node (z.B. beelink-user): " RECOVERY_SSH_USER

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

# Neu: SSH User für die Brücke
PRIMARY_SSH_USER="$PRIMARY_SSH_USER"
RECOVERY_SSH_USER="$RECOVERY_SSH_USER"

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
    # ==============================================================================
    # AUTOMATISCHER MODUS (Läuft ferngesteuert auf dem Beelink ab)
    # ==============================================================================
    NODE_ROLE="$AUTO_ROLE"
    echo "🤖 Automatischer Modus: Installiere als '$NODE_ROLE'"
    
    mkdir -p /etc/remote-survival
    # Config vom Pi an den richtigen Ort schieben
    mv /tmp/survival.conf /etc/remote-survival/survival.conf
    
    # WICHTIG: Die vom Pi kopierte Config auf RECOVERY umschreiben!
    sed -i 's/^NODE_ROLE=.*/NODE_ROLE="RECOVERY"/' /etc/remote-survival/survival.conf
    chmod 600 /etc/remote-survival/survival.conf
    
    # Config laden, damit Variablen wie RECOVERY_SSH_USER bekannt sind
    source /etc/remote-survival/survival.conf
fi


# ==============================================================================
# PHASE 2: SKRIPTE KOPIEREN & BERECHTIGUNGEN (Läuft auf beiden Nodes)
# ==============================================================================
echo "⚙️  Kopiere Überwachungs-Skripte..."
mkdir -p /usr/local/bin/remote-survival
cp scripts/*.sh /usr/local/bin/remote-survival/ 2>/dev/null
chmod +x /usr/local/bin/remote-survival/*.sh

# --- NEU: MINIMAL-SUDO FÜR RECOVERY NODE ---
if [ "$NODE_ROLE" == "RECOVERY" ]; then
    echo "🛡️  Setze strikte Ordnerrechte für das Flag-System..."
    # Der Beelink-User darf die Flag-Dateien in diesem Ordner normal erstellen/löschen
    chown -R "$RECOVERY_SSH_USER":"$RECOVERY_SSH_USER" /etc/remote-survival
    
    # Der Beelink-User darf OHNE Passwort nur Tailscale neu starten!
    echo "$RECOVERY_SSH_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart tailscaled" > /etc/sudoers.d/remote-survival-tailscale
    chmod 0440 /etc/sudoers.d/remote-survival-tailscale
fi


# ==============================================================================
# PHASE 3: SYSTEMD DIENSTE (Dein Original Code)
# ==============================================================================
if [ "$NODE_ROLE" == "PRIMARY" ]; then
    echo "⬇️  Installiere Wake-on-LAN Paket (falls nicht vorhanden)..."
    apt-get update -qq && apt-get install -y wakeonlan > /dev/null
    
    echo "🛡️  Aktiviere systemd Hardware-Watchdog (60 Sekunden)..."
    sed -i 's/^#RuntimeWatchdogSec=.*/RuntimeWatchdogSec=60s/' /etc/systemd/system.conf
    systemctl daemon-reexec
fi

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
echo "✅ LOKALE INSTALLATION ABGESCHLOSSEN!"


# ==============================================================================
# PHASE 4: REMOTE DEPLOYMENT (Der magische Zero-Touch Teil)
# ==============================================================================
if [ "$NODE_ROLE" == "PRIMARY" ] && [ -z "$AUTO_ROLE" ]; then
    echo ""
    echo "================================================="
    echo "🌐 REMOTE DEPLOYMENT (RECOVERY NODE EINRICHTEN)"
    echo "================================================="
    read -p "Möchtest du den Recovery Node (Beelink) jetzt automatisch mit-einrichten? (y/n): " AUTO_DEPLOY
    
    if [[ "$AUTO_DEPLOY" == "y" || "$AUTO_DEPLOY" == "Y" ]]; then
        
        # 1. SSH BRÜCKE: PI -> BEELINK
        echo "🔑 Schritt 1: Richte System-SSH-Zugriff von Pi auf Beelink ein..."
        chmod +x check_and_install_ssh.sh
        ./check_and_install_ssh.sh
        read -p "Welchen Alias hast du im SSH-Skript gerade vergeben? (z.B. beelink): " RECOVERY_ALIAS
        
        # 2. SSH BRÜCKE: BEELINK -> PI (Der Rückweg)
        echo "🔑 Schritt 2: Baue sicheren Rückweg (Beelink -> Pi) auf..."
        
        # Befehle Beelink, sich einen Key zu generieren, falls er keinen hat
        ssh "$RECOVERY_ALIAS" "[ ! -f ~/.ssh/id_ed25519 ] && ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -q"
        
        # Hole den Public Key vom Beelink
        BEELINK_PUBKEY=$(ssh "$RECOVERY_ALIAS" "cat ~/.ssh/id_ed25519.pub")
        
        # Trage ihn in die Authorized_Keys deines Pi-Users ein
        PI_AUTH_KEYS="/home/$PRIMARY_SSH_USER/.ssh/authorized_keys"
        sudo -u "$PRIMARY_SSH_USER" mkdir -p "/home/$PRIMARY_SSH_USER/.ssh"
        sudo -u "$PRIMARY_SSH_USER" touch "$PI_AUTH_KEYS"
        
        if ! grep -q "$BEELINK_PUBKEY" "$PI_AUTH_KEYS"; then
            echo "$BEELINK_PUBKEY" | sudo -u "$PRIMARY_SSH_USER" tee -a "$PI_AUTH_KEYS" >/dev/null
        fi
        
        echo "✅ Bi-direktionale SSH-Brücke steht!"
        
        # 3. REMOTE INSTALLATION
        echo "📦 Pushe Repo auf $RECOVERY_ALIAS..."
        ssh "$RECOVERY_ALIAS" "mkdir -p /tmp/remote-survival-setup"
        scp -r ./* "$RECOVERY_ALIAS":/tmp/remote-survival-setup/
        
        # Schiebe die Config rüber
        scp /etc/remote-survival/survival.conf "$RECOVERY_ALIAS":/tmp/survival.conf
        
        echo "⚙️  Führe lautlose Installation auf dem Beelink aus..."
        # Führe Skript als sudo aus und setze AUTO_ROLE
        ssh -t "$RECOVERY_ALIAS" "cd /tmp/remote-survival-setup && sudo env AUTO_ROLE=RECOVERY ./install.sh"
        
        # 4. AUFRÄUMEN
        ssh "$RECOVERY_ALIAS" "rm -rf /tmp/remote-survival-setup"
        echo "🎉 ZERO-TOUCH DEPLOYMENT ERFOLGREICH ABGESCHLOSSEN!"
    fi
fi