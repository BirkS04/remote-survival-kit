#!/bin/bash

# ==============================================================================
# UNIVERSAL SSH SETUP & HARDENING TOOL
# Richtet passwortloses SSH, Aliase und Server-Sicherheit ein.
# ==============================================================================

echo "=========================================="
echo "🔑 SSH TRUST & SETUP TOOL"
echo "=========================================="

# --- 1. EINGABEPRÜFUNG (BULLETPROOFING) ---
read -p "IP des Ziel-Servers? (z.B. 192.168.178.50): " TARGET_IP
if [ -z "$TARGET_IP" ]; then echo "❌ Fehler: Keine IP angegeben!"; exit 1; fi

read -p "SSH-Benutzername auf dem Ziel? (z.B. ubuntu): " TARGET_USER
if [ -z "$TARGET_USER" ]; then echo "❌ Fehler: Kein Benutzername angegeben!"; exit 1; fi

read -p "Gewünschter SSH-Alias? (z.B. beelink): " TARGET_ALIAS
if [ -z "$TARGET_ALIAS" ]; then echo "❌ Fehler: Kein Alias angegeben!"; exit 1; fi

read -p "SSH Port? (Enter für Standard 22): " TARGET_PORT
TARGET_PORT=${TARGET_PORT:-22} # Wenn leer, nimm 22

# --- 2. LOKALEN SSH-KEY PRÜFEN/GENERIEREN ---
SSH_DIR="$HOME/.ssh"
KEY_FILE="$SSH_DIR/id_ed25519"

# Strikte Rechte für den SSH-Ordner (sonst weigert sich SSH oft)
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ ! -f "$KEY_FILE" ]; then
    echo "🛠️  Generiere sicheren ED25519 Key..."
    # -N "" bedeutet: Kein Passwort für den Key selbst (wichtig für automatisierte Skripte!)
    ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -q
    echo "✅ Key generiert."
else
    echo "✅ Lokaler SSH-Key existiert bereits."
fi

# --- 3. VERBINDUNG TESTEN ODER KEY KOPIEREN ---
echo "🔄 Prüfe passwortloses Login auf $TARGET_IP..."
# Timeout 3s, BatchMode=yes verhindert hängenbleiben, wenn Passwort nötig ist
if ssh -o BatchMode=yes -o ConnectTimeout=3 -p "$TARGET_PORT" "$TARGET_USER@$TARGET_IP" "echo 'success'" >/dev/null 2>&1; then
    echo "✅ Passwortloses Login funktioniert bereits!"
else
    echo "⚠️  Kopiere Key auf den Ziel-Server. Bitte jetzt das Passwort für $TARGET_USER eingeben:"
    ssh-copy-id -p "$TARGET_PORT" -i "$KEY_FILE.pub" "$TARGET_USER@$TARGET_IP"
    
    if [ $? -ne 0 ]; then
        echo "❌ Fehler beim Kopieren des Keys. Abbruch."
        exit 1
    fi
fi

# --- 4. SSH ALIAS EINRICHTEN ---
CONFIG_FILE="$SSH_DIR/config"
touch "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE" # Strikte Rechte für die Config

# Prüft, ob der Alias exakt so schon existiert (verhindert doppelte Einträge)
if ! grep -q "^Host $TARGET_ALIAS$" "$CONFIG_FILE"; then
    echo "📝 Lege Alias '$TARGET_ALIAS' an..."
    cat <<EOF >> "$CONFIG_FILE"

Host $TARGET_ALIAS
    HostName $TARGET_IP
    User $TARGET_USER
    Port $TARGET_PORT
    IdentityFile $KEY_FILE
EOF
    echo "✅ Alias angelegt! Du kannst dich jetzt mit 'ssh $TARGET_ALIAS' verbinden."
else
    echo "✅ Alias '$TARGET_ALIAS' existiert bereits in der Config."
fi

# --- 5. ZIEL-SERVER ABSICHERN (OPTIONAL) ---
echo ""
echo "🛡️  Möchtest du den SSH-Server auf dem Ziel ($TARGET_ALIAS) absichern?"
echo "    Das deaktiviert den Passwort-Login (nur noch Keys erlaubt)"
echo "    und verbietet den direkten root-Login."
read -p "Absichern? (y/n): " SECURE_CHOICE

if [[ "$SECURE_CHOICE" == "y" || "$SECURE_CHOICE" == "Y" ]]; then
    echo "🔒 Sichere Ziel-Server ab (benötigt sudo-Rechte auf dem Ziel)..."
    REMOTE_CMD="sudo sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config && \
                sudo sed -i 's/^#*PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && \
                sudo systemctl restart sshd || sudo systemctl restart ssh"
    
    ssh -t "$TARGET_ALIAS" "$REMOTE_CMD"
    echo "✅ Ziel-Server ist jetzt abgesichert!"
fi

echo "🎉 SSH-Setup komplett abgeschlossen."