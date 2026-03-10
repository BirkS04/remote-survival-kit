#!/bin/bash

# ==============================================================================
# UNIVERSAL SSH SETUP & HARDENING TOOL
# ==============================================================================

echo "=========================================="
echo "🔑 SSH TRUST & SETUP TOOL"
echo "=========================================="

# Wenn die Variable schon von install.sh gesetzt wurde, wird nicht mehr gefragt!
[ -z "$TARGET_IP" ] && read -e -p "IP des Ziel-Servers? " TARGET_IP
if [ -z "$TARGET_IP" ]; then echo "❌ Fehler: Keine IP!"; exit 1; fi

[ -z "$TARGET_USER" ] && read -e -p "SSH-Benutzername auf dem Ziel? " TARGET_USER
if [ -z "$TARGET_USER" ]; then echo "❌ Fehler: Kein User!"; exit 1; fi

[ -z "$TARGET_ALIAS" ] && read -e -p "Gewünschter SSH-Alias? " TARGET_ALIAS
if [ -z "$TARGET_ALIAS" ]; then echo "❌ Fehler: Kein Alias!"; exit 1; fi

[ -z "$TARGET_PORT" ] && read -e -p "SSH Port? (Enter für Standard 22): " -i "22" TARGET_PORT
TARGET_PORT=${TARGET_PORT:-22}

# Lokalen Key als ausführender User generieren
SSH_DIR="$HOME/.ssh"
KEY_FILE="$SSH_DIR/id_ed25519"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ ! -f "$KEY_FILE" ]; then
    echo "🛠️  Generiere sicheren ED25519 Key..."
    ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -q
    echo "✅ Key generiert."
else
    echo "✅ Lokaler SSH-Key existiert bereits."
fi

echo "🔄 Prüfe passwortloses Login auf $TARGET_IP..."

if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=3 -p "$TARGET_PORT" "$TARGET_USER@$TARGET_IP" "echo 'success'" >/dev/null 2>&1; then
    echo "✅ Passwortloses Login funktioniert bereits!"
else
    echo "⚠️  Key muss auf den Ziel-Server kopiert werden."
    echo "--------------------------------------------------------"
    echo "🛑 ACHTUNG: Bitte warte, bis unten 'password:' steht!"
    echo "Beim Tippen werden KEINE Sternchen angezeigt."
    echo "--------------------------------------------------------"
    
    # FIX: Wir nutzen den rohen SSH-Befehl mit -t (Terminal erzwingen) statt ssh-copy-id!
    PUB_KEY=$(cat "$KEY_FILE.pub")
    ssh -t -o StrictHostKeyChecking=accept-new -p "$TARGET_PORT" "$TARGET_USER@$TARGET_IP" \
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo \"$PUB_KEY\" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    
    if [ $? -ne 0 ]; then
        echo "❌ Fehler beim Kopieren des Keys. Abbruch."
        exit 1
    fi
fi

# SSH Alias einrichten
CONFIG_FILE="$SSH_DIR/config"
touch "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

# Alten Eintrag löschen falls vorhanden
sed -i "/^Host $TARGET_ALIAS$/,/StrictHostKeyChecking/d" "$CONFIG_FILE" 2>/dev/null

echo "📝 Lege Alias '$TARGET_ALIAS' an..."
cat <<EOF >> "$CONFIG_FILE"
Host $TARGET_ALIAS
    HostName $TARGET_IP
    User $TARGET_USER
    Port $TARGET_PORT
    IdentityFile $KEY_FILE
    StrictHostKeyChecking accept-new
EOF
echo "✅ Alias angelegt! ('ssh $TARGET_ALIAS')"

# Server absichern (Optional)
if [ -z "$SECURE_CHOICE" ]; then
    echo ""
    echo "🛡️  Möchtest du den SSH-Server auf dem Ziel ($TARGET_ALIAS) absichern?"
    read -e -p "Absichern? (y/n): " -i "n" SECURE_CHOICE
fi

if [[ "$SECURE_CHOICE" == "y" || "$SECURE_CHOICE" == "Y" ]]; then
    echo "🔒 Sichere Ziel-Server ab..."
    REMOTE_CMD="sudo sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config && \
                sudo sed -i 's/^#*PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && \
                sudo systemctl restart sshd || sudo systemctl restart ssh"
    
    ssh -t "$TARGET_ALIAS" "$REMOTE_CMD"
    echo "✅ Ziel-Server ist jetzt abgesichert!"
fi

echo "🎉 SSH-Setup für $TARGET_ALIAS abgeschlossen."