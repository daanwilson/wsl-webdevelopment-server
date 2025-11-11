#!/usr/bin/env bash
set -euo pipefail

# =====================================================
# WSL Webstack installer (Apache + PHP + MariaDB + phpMyAdmin)
# - schakelt extensies in: zip, gd, soap, xml, mysqli, pdo_mysql, curl
# - past php.ini aan (enkele dev-settings)
# - installeert phpMyAdmin en activeert de config voor Apache
# - maakt MySQL root gebruiker aan met custom username en wachtwoord
# =====================================================

WEBROOT="/var/www/html"

# -------------------------
# Database credentials
# -------------------------

MYSQL_ADMIN_USER=$USER
MYSQL_ADMIN_PASS=$USER


echo "🚀 Start installatie: Apache, PHP (+exts), MariaDB, phpMyAdmin"
echo ""

# -------------------------
# Vraag om schone installatie
# -------------------------
echo "❓ Wil je een schone installatie uitvoeren?"
echo "   Dit verwijdert Apache, MariaDB/MySQL en phpMyAdmin volledig."
echo ""
if [ -e /dev/tty ]; then
    # Lees altijd van de TTY, ook wanneer het script via een pipe wordt gestart (curl ... | bash)
    if ! read -p "Voer schone installatie uit? (j/n) [n]: " -r CLEAN_INSTALL </dev/tty; then
        CLEAN_INSTALL="n"
    fi
else
    echo "Niet-interactieve omgeving gedetecteerd; standaardantwoord: n"
    CLEAN_INSTALL="n"
fi
CLEAN_INSTALL=${CLEAN_INSTALL:-n}

if [[ "$CLEAN_INSTALL" =~ ^[Jj]$ ]]; then
    CLEAN_INSTALL=true
    echo "✅ Schone installatie geselecteerd - bestaande software wordt verwijderd"
else
    CLEAN_INSTALL=false
    echo "ℹ️  Bestaande installaties blijven behouden"
fi

echo ""

# -------------------------
# Updates & basispakketten
# -------------------------
echo "🔄 Systeem updaten..."
sudo apt update && sudo apt upgrade -y

echo "📦 Basispakketten installeren..."
sudo apt install -y software-properties-common curl unzip git nano wget lsb-release ca-certificates apt-transport-https

# -------------------------
# Apache volledig verwijderen (indien gewenst)
# -------------------------
if [ "$CLEAN_INSTALL" = true ]; then
    echo "🗑️  Apache volledig verwijderen..."
    sudo systemctl stop apache2 2>/dev/null || true
    sudo apt remove --purge -y apache2 apache2-utils apache2-bin apache2-data 2>/dev/null || true
    sudo apt autoremove -y
    sudo rm -rf /etc/apache2
    sudo rm -rf /var/www
    echo "✅ Apache verwijderd"
else
    echo "⏭️  Apache verwijderen overgeslagen"
fi

# -------------------------
# MariaDB/MySQL volledig verwijderen (indien gewenst)
# -------------------------
if [ "$CLEAN_INSTALL" = true ]; then
    echo "🗑️  MariaDB/MySQL volledig verwijderen..."
    sudo systemctl stop mariadb 2>/dev/null || true
    sudo systemctl stop mysql 2>/dev/null || true
    sudo apt remove --purge -y mariadb-server mariadb-client mariadb-common mysql-server mysql-client mysql-common 2>/dev/null || true
    sudo apt autoremove -y
    sudo rm -rf /etc/mysql
    sudo rm -rf /var/lib/mysql
    sudo rm -rf /var/log/mysql
    echo "✅ MariaDB/MySQL verwijderd"
else
    echo "⏭️  MariaDB/MySQL verwijderen overgeslagen"
fi

# -------------------------
# phpMyAdmin volledig verwijderen (indien gewenst)
# -------------------------
if [ "$CLEAN_INSTALL" = true ]; then
    echo "🗑️  phpMyAdmin volledig verwijderen..."
    sudo apt remove --purge -y phpmyadmin 2>/dev/null || true
    sudo apt autoremove -y
    sudo rm -rf /etc/phpmyadmin
    sudo rm -rf /usr/share/phpmyadmin
    sudo rm -f /etc/apache2/conf-available/phpmyadmin.conf
    sudo rm -f /etc/apache2/conf-enabled/phpmyadmin.conf
    echo "✅ phpMyAdmin verwijderd"
else
    echo "⏭️  phpMyAdmin verwijderen overgeslagen"
fi

# -------------------------
# Netwerk schijf toevoegen aan fstab
# -------------------------
echo "💾 Netwerk schijf H: toevoegen aan /etc/fstab..."

# Maak mount point aan als deze niet bestaat
sudo mkdir -p /mnt/h

# Voeg H: schijf toe aan fstab als deze nog niet bestaat
if ! grep -q "^H: /mnt/h" /etc/fstab; then
    echo "H: /mnt/h drvfs defaults 0 0" | sudo tee -a /etc/fstab > /dev/null
    echo "✅ H: schijf toegevoegd aan /etc/fstab"
else
    echo "ℹ️  H: schijf staat al in /etc/fstab"
fi

# Mount de schijf direct (als deze al gemount is, geeft dit geen error)
sudo mount -a 2>/dev/null || true
echo "✅ Netwerk schijf gemount op /mnt/h"

# -------------------------
# SSH sleutels kopiëren van Windows naar WSL
# -------------------------
echo "🔑 SSH sleutels kopiëren van Windows naar WSL..."

# Bepaal Windows gebruikersnaam (uit WSLENV of PATH)
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "")

if [ -n "$WIN_USER" ] && [ "$WIN_USER" != "" ]; then
    WIN_SSH_DIR="/mnt/c/Users/${WIN_USER}/.ssh"
    WSL_SSH_DIR="$HOME/.ssh"

    if [ -d "$WIN_SSH_DIR" ]; then
        # Maak .ssh directory aan als deze niet bestaat
        mkdir -p "$WSL_SSH_DIR"

        # Kopieer alle SSH bestanden (alleen als ze bestaan)
        if [ -f "$WIN_SSH_DIR/id_rsa" ] || [ -f "$WIN_SSH_DIR/id_ed25519" ]; then
            # Kopieer bestanden één voor één om fouten te voorkomen
            for file in "$WIN_SSH_DIR"/*; do
                if [ -f "$file" ]; then
                    cp -n "$file" "$WSL_SSH_DIR/" 2>/dev/null || true
                fi
            done

            # Zet correcte permissies (belangrijk voor SSH!)
            chmod 700 "$WSL_SSH_DIR" || true
            chmod 600 "$WSL_SSH_DIR"/id_* 2>/dev/null || true
            chmod 644 "$WSL_SSH_DIR"/*.pub 2>/dev/null || true
            chmod 644 "$WSL_SSH_DIR"/config 2>/dev/null || true
            chmod 644 "$WSL_SSH_DIR"/known_hosts 2>/dev/null || true

            echo "✅ SSH sleutels gekopieerd naar $WSL_SSH_DIR"
            echo "ℹ️  Gevonden sleutels:"
            ls -la "$WSL_SSH_DIR" 2>/dev/null | grep -E "id_|config" || echo "   Geen sleutels gevonden"
        else
            echo "⚠️  Geen SSH sleutels gevonden in $WIN_SSH_DIR"
        fi
    else
        echo "⚠️  Windows .ssh directory niet gevonden: $WIN_SSH_DIR"
    fi
else
    echo "⚠️  Kon Windows gebruikersnaam niet bepalen - SSH kopiëren overgeslagen"
fi

echo "ℹ️  SSH sectie voltooid, verder met PHP installatie..."

# -------------------------
# PHP (via Ondřej PPA) + extensies
# -------------------------
echo "🐘 PHP repository toevoegen en PHP installeren..."
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update

# Installeer PHP + veelgebruikte extensies
sudo apt install -y apache2 mariadb-server \
 php php-cli libapache2-mod-php \
 php-mbstring php-xml php-curl php-zip php-gd php-soap php-mysql php-xmlrpc

# Zorg dat specifieke modules ingeschakeld zijn (phpenmod)
echo "🔌 Extensies inschakelen..."
sudo phpenmod zip gd soap xml mysqli pdo_mysql curl

# -------------------------
# Apache configuratie: DocumentRoot -> $WEBROOT
# -------------------------
echo "🌐 Webroot instellen: $WEBROOT"

# Maak webroot directory aan als deze niet bestaat
sudo mkdir -p "$WEBROOT"

# Zet correcte eigenaar en permissies
sudo chown -R $USER:www-data "$WEBROOT"
sudo chmod -R 755 "$WEBROOT"

# Update Apache's default site configuratie volledig
APACHE_SITE="/etc/apache2/sites-available/000-default.conf"
sudo tee "$APACHE_SITE" > /dev/null <<VHOST
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot $WEBROOT

    <Directory $WEBROOT/>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
VHOST

# Voeg Directory-blok toe in apache2.conf
sudo tee -a /etc/apache2/apache2.conf > /dev/null <<EOL

<Directory $WEBROOT/>
    Options Indexes FollowSymLinks MultiViews
    AllowOverride All
    Require all granted
</Directory>
EOL

# Voeg gebruiker toe aan www-data groep
sudo usermod -a -G www-data $USER

echo "✅ Apache DocumentRoot ingesteld op $WEBROOT"

# --------------------------------
# php.ini aanpassen (apache2 variant)
# --------------------------------
# Zorg dat Xdebug logpad bestaat om warnings/aborts te voorkomen als Xdebug geactiveerd is
sudo mkdir -p /var/log/xdebug 2>/dev/null || true
sudo touch /var/log/xdebug/xdebug.log 2>/dev/null || true
sudo chown www-data:adm /var/log/xdebug /var/log/xdebug/xdebug.log 2>/dev/null || true
sudo chmod 775 /var/log/xdebug 2>/dev/null || true
sudo chmod 664 /var/log/xdebug/xdebug.log 2>/dev/null || true

# Bepaal PHP hoofdversie; onderdruk eventuele Xdebug-stderr en voorkom aborts
set +e
PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".;' 2>/dev/null)"
set -e
PHP_VER="${PHP_VER:-8.}"
PHP_INI="/etc/php/$PHP_VER/apache2/php.ini"

if [ -f "$PHP_INI" ]; then
  echo "🛠  php.ini gevonden: $PHP_INI — instellingen aanpassen..."
  # a) handige dev instellingen (pas aan indien gewenst)
  sudo sed -i "s/^upload_max_filesize = .*/upload_max_filesize = 128M/" "$PHP_INI"
  sudo sed -i "s/^post_max_size = .*/post_max_size = 128M/" "$PHP_INI"
  sudo sed -i "s/^memory_limit = .*/memory_limit = 256M/" "$PHP_INI"
  # Zorg dat errors zichtbaar zijn in dev (optioneel); je kan dit later uitschakelen
  sudo sed -i "s/^display_errors = .*/display_errors = On/" "$PHP_INI"
  sudo sed -i "s/^error_reporting = .*/error_reporting = E_ALL/" "$PHP_INI"
else
  echo "⚠️  php.ini niet gevonden op $PHP_INI — overslaan php.ini aanpassingen."
fi

# -------------------------
# Apache modules & restart
# -------------------------
sudo a2enmod rewrite
sudo systemctl enable apache2
sudo systemctl restart apache2

# -------------------------
# MariaDB opstarten en config
# -------------------------
echo "🗄️  MariaDB starten en (basis)beveiliging toepassen..."
sudo systemctl enable mariadb
sudo systemctl start mariadb

# Voer mysql_secure_installation-achtige stappen non-interactief:
sudo mysql -u root <<'SQL'
-- minimal cleanup (ok to run even if already set)
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
SQL

# -------------------------
# Maak admin user met wachtwoord
# -------------------------
echo "🔐 Aanmaken MySQL admin user '$MYSQL_ADMIN_USER' met wachtwoord..."
# Create user with password and give ALL PRIVILEGES on *.* and grant option
sudo mysql -u root <<SQL
CREATE USER IF NOT EXISTS '${MYSQL_ADMIN_USER}'@'localhost' IDENTIFIED BY '${MYSQL_ADMIN_PASS}';
GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_ADMIN_USER}'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

echo "ℹ️  MySQL admin user '${MYSQL_ADMIN_USER}'@'localhost' aangemaakt met wachtwoord: ${MYSQL_ADMIN_PASS}"

# -------------------------
# phpMyAdmin installeren (non-interactive minimal)
# -------------------------
echo "📋 phpMyAdmin installeren (non-interactive)..."

# voorkom prompts: we zetten dbconfig-install op false zodat apt niet om app passwords vraagt
sudo debconf-set-selections <<DEB
phpmyadmin phpmyadmin/dbconfig-install boolean false
phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2
DEB

# Installeer phpmyadmin pakket zonder interactieve prompts
sudo DEBIAN_FRONTEND=noninteractive apt install -y phpmyadmin

# Zorg dat Apache de phpMyAdmin config laadt
if [ -f /etc/phpmyadmin/apache.conf ]; then
  sudo ln -sf /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf
  sudo a2enconf phpmyadmin
  echo "✅ phpMyAdmin geactiveerd in Apache (/etc/phpmyadmin)."
else
  echo "⚠️  /etc/phpmyadmin/apache.conf niet gevonden — phpMyAdmin installatie mogelijk mislukt."
fi

# Alternatieve configuratie: maak symlink in webroot
if [ -d /usr/share/phpmyadmin ]; then
  sudo ln -sf /usr/share/phpmyadmin "$WEBROOT/phpmyadmin"
  echo "✅ phpMyAdmin symlink aangemaakt in $WEBROOT/phpmyadmin"
fi

# Reload Apache om configuratie te activeren
sudo systemctl reload apache2

# -------------------------
# Testpagina en final restart
# -------------------------

# Verwijder oude index.html en index.php
sudo rm -f "$WEBROOT/index.html"
sudo rm -f "$WEBROOT/index.php"

# Kopieer de index.php uit de repository naar WEBROOT
curl -s https://raw.githubusercontent.com/daanwilson/wsl-webdevelopment-server/refs/heads/main/index.php -o "$WEBROOT/index.php"

# Maak info.php aan met phpinfo()
echo "<?php phpinfo(); ?>" | sudo tee "$WEBROOT/info.php" > /dev/null
echo "✅ info.php aangemaakt voor diagnose"

# Verwijder eventuele .htaccess files die problemen kunnen veroorzaken
sudo rm -f "$WEBROOT/.htaccess"

# Zet nogmaals correcte permissies op alle bestanden
echo "⌛ Zet correcte permissies op alle bestanden, dit kan even duren...."
sudo chown -R $USER:www-data "$WEBROOT"
sudo find "$WEBROOT" -type d -exec chmod 755 {} \;
sudo find "$WEBROOT" -type f -exec chmod 644 {} \;
echo "✅ Rechten ingesteld"

sudo systemctl restart apache2
sudo systemctl restart mariadb

echo ""
echo "✅ Klaar! Samenvatting:"
echo " - Apache document root: $WEBROOT"
echo " - PHP versie: $(php -v | head -n1)"
echo " - Ingeschakelde PHP-extensies: zip, gd, soap, xml, mysqli, pdo_mysql, curl"
echo " - php.ini aangepast (upload_max_filesize=128M, post_max_size=128M, memory_limit=256M, display_errors=On)"
echo " - phpMyAdmin: beschikbaar via http://localhost/phpmyadmin"
echo " - MySQL admin user: ${MYSQL_ADMIN_USER}@localhost (met wachtwoord)"
echo ""
echo "🔐 Login credentials voor phpMyAdmin:"
echo "    Username: ${MYSQL_ADMIN_USER}"
echo "    Password: ${MYSQL_ADMIN_PASS}"
echo ""
echo "📂 Permissies check:"
echo "    Home directory: $(ls -ld $HOME | awk '{print $1, $3, $4}')"
echo "    Projects directory: $(ls -ld $WEBROOT | awk '{print $1, $3, $4}')"
echo ""
echo "🔁 Voer 'wsl --shutdown' uit in PowerShell als je wijzigingen in /etc/wsl.conf hebt gedaan en start WSL opnieuw."