#!/bin/bash

# ==============================================================================
# UNIVERSAL SSH SETUP & HARDENING TOOL
# ==============================================================================

echo "=========================================="
echo "🔑 SSH TRUST & SETUP TOOL"
echo "=========================================="

[ -z "$TARGET_IP" ] && read -e -p "IP des Ziel-Servers? " TARGET_IP
if [ -z "$TARGET_IP" ]; then echo "❌ Fehler: Keine IP!"; exit 1; fi

[ -z "$TARGET_USER" ] && read -e -p "SSH-Benutzername auf dem Ziel? " TARGET_USER
if [ -z "$TARGET_USER" ]; then echo "❌ Fehler: Kein User!"; exit 1; fi

[ -z "$TARGET_ALIAS" ] && read -e -p "Gewünschter SSH-Alias? " TARGET_ALIAS
if [ -z "$TARGET_ALIAS" ]; then echo "❌ Fehler: Kein Alias!"; exit 1; fi

[ -z "$TARGET_PORT" ] && read -e -p "SSH Port? (Enter für Standard 22): " -i "22" TARGET_PORT
TARGET_PORT=${TARGET_PORT:-22}

# Finde das korrekte Home-Verzeichnis des normalen Users
LOCAL_USER=${LOCAL_USER:-$SUDO_USER}
LOCAL_USER=${LOCAL_USER:-$USER}
LOCAL_HOME=$(getent passwd "$LOCAL_USER" | cut -d: -f6)

SSH_DIR="$LOCAL_HOME/.ssh"
KEY_FILE="$SSH_DIR/id_ed25519"

# Ordner sauber als der echte User anlegen
sudo -u "$LOCAL_USER" mkdir -p "$SSH_DIR"
sudo -u "$LOCAL_USER" chmod 700 "$SSH_DIR"

if [ ! -f "$KEY_FILE" ]; then
    echo "🛠️  Generiere sicheren ED25519 Key für $LOCAL_USER..."
    sudo -u "$LOCAL_USER" ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -q
    echo "✅ Key generiert."
else
    echo "✅ Lokaler SSH-Key existiert bereits."
fi

echo "🔄 Prüfe passwortloses Login auf $TARGET_IP..."

# Check ebenfalls als echter User ausführen
if sudo -u "$LOCAL_USER" ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new -i "$KEY_FILE" -p "$TARGET_PORT" "$TARGET_USER@$TARGET_IP" "echo 'success'" >/dev/null 2>&1; then
    echo "✅ Passwortloses Login funktioniert bereits!"
else
    echo "⚠️  Key muss auf den Ziel-Server kopiert werden."
    echo "--------------------------------------------------------"
    echo "🛑 ACHTUNG: Bitte gib jetzt das SSH-Passwort für '$TARGET_USER' ein!"
    echo "Beim Tippen werden KEINE Sternchen angezeigt."
    echo "--------------------------------------------------------"
    
    # FIX: Wir nutzen ssh-copy-id als lokaler User. Kein -t mehr, das das Terminal unter sudo zerstört!
    sudo -u "$LOCAL_USER" ssh-copy-id -i "$KEY_FILE" -p "$TARGET_PORT" -o StrictHostKeyChecking=accept-new "$TARGET_USER@$TARGET_IP"
    
    if [ $? -ne 0 ]; then
        echo "❌ Fehler beim Kopieren des Keys. Abbruch."
        exit 1
    fi
    echo "✅ Key erfolgreich übertragen!"
fi

# ==========================================
# CONFIG FÜR DEN NORMALEN USER
# ==========================================
CONFIG_FILE="$SSH_DIR/config"
sudo -u "$LOCAL_USER" touch "$CONFIG_FILE"
sudo -u "$LOCAL_USER" sed -i "/^Host $TARGET_ALIAS$/,/StrictHostKeyChecking/d" "$CONFIG_FILE" 2>/dev/null

echo "📝 Lege Alias '$TARGET_ALIAS' für $LOCAL_USER an..."
sudo -u "$LOCAL_USER" bash -c "cat <<EOF >> \"$CONFIG_FILE\"
Host $TARGET_ALIAS
    HostName $TARGET_IP
    User $TARGET_USER
    Port $TARGET_PORT
    IdentityFile $KEY_FILE
    StrictHostKeyChecking accept-new
EOF"
sudo -u "$LOCAL_USER" chmod 600 "$CONFIG_FILE"


# ==========================================
# CONFIG FÜR ROOT (SYSTEMD)
# ==========================================
# Da systemd Skripte als Root ausführt, braucht Root diesen Alias ebenfalls!
ROOT_SSH_DIR="/root/.ssh"
ROOT_CONFIG_FILE="$ROOT_SSH_DIR/config"

mkdir -p "$ROOT_SSH_DIR"
chmod 700 "$ROOT_SSH_DIR"
touch "$ROOT_CONFIG_FILE"
sed -i "/^Host $TARGET_ALIAS$/,/StrictHostKeyChecking/d" "$ROOT_CONFIG_FILE" 2>/dev/null

echo "📝 Lege Alias '$TARGET_ALIAS' für ROOT (systemd) an..."
cat <<EOF >> "$ROOT_CONFIG_FILE"
Host $TARGET_ALIAS
    HostName $TARGET_IP
    User $TARGET_USER
    Port $TARGET_PORT
    IdentityFile $KEY_FILE
    StrictHostKeyChecking accept-new
EOF
chmod 600 "$ROOT_CONFIG_FILE"

echo "✅ Alias angelegt! ('ssh $TARGET_ALIAS')"