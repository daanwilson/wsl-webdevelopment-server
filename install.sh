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

echo "🚀 Start installatie: Apache, PHP (+exts), MariaDB, phpMyAdmin"
echo ""

# -------------------------
# Vraag om database credentials
# -------------------------
echo "📝 Database configuratie:"
read -p "Voer de gewenste MySQL admin username in: " MYSQL_ADMIN_USER

# Tijdelijk pipefail uitzetten voor read commando's
set +e

MYSQL_ADMIN_PASS=""
MYSQL_ADMIN_PASS_CONFIRM="different"

while [ "$MYSQL_ADMIN_PASS" != "$MYSQL_ADMIN_PASS_CONFIRM" ]; do
    read -sp "Voer het gewenste wachtwoord in: " MYSQL_ADMIN_PASS
    echo ""
    read -sp "Bevestig het wachtwoord: " MYSQL_ADMIN_PASS_CONFIRM
    echo ""
    
    if [ "$MYSQL_ADMIN_PASS" != "$MYSQL_ADMIN_PASS_CONFIRM" ]; then
        echo "❌ Wachtwoorden komen niet overeen. Probeer opnieuw."
    fi
done

echo "✅ Wachtwoorden komen overeen!"
set -e

echo ""
echo "✅ Credentials ingesteld voor gebruiker: $MYSQL_ADMIN_USER"
echo ""

# -------------------------
# Updates & basispakketten
# -------------------------
echo "🔄 Systeem updaten..."
sudo apt update && sudo apt upgrade -y

echo "📦 Basispakketten installeren..."
sudo apt install -y software-properties-common curl unzip git nano wget lsb-release ca-certificates apt-transport-https

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
sudo chown -R $USER:www-data "$WEBROOT"
sudo chmod -R 775 "$WEBROOT"

# Vervang / voeg Directory-blok toe in apache2.conf
sudo sed -i "/<Directory \/var\/www\/>/,/<\/Directory>/d" /etc/apache2/apache2.conf || true
sudo tee -a /etc/apache2/apache2.conf > /dev/null <<EOL

<Directory $WEBROOT/>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOL

# --------------------------------
# php.ini aanpassen (apache2 variant)
# --------------------------------
PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
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

echo "ℹ️  MySQL admin user '${MYSQL_ADMIN_USER}'@'localhost' aangemaakt met wachtwoord."

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
  sudo systemctl reload apache2
  echo "✅ phpMyAdmin geactiveerd in Apache (/etc/phpmyadmin)."
else
  echo "⚠️  /etc/phpmyadmin/apache.conf niet gevonden — phpMyAdmin installatie mogelijk mislukt."
fi

# -------------------------
# Testpagina en final restart
# -------------------------
echo "<?php phpinfo(); ?>" | sudo tee "$WEBROOT/index.php" > /dev/null

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
echo "    Password: [het door jou ingestelde wachtwoord]"
echo ""
echo "🔁 Voer 'wsl --shutdown' uit in PowerShell als je wijzigingen in /etc/wsl.conf hebt gedaan en start WSL opnieuw."
