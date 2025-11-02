#!/usr/bin/env bash
set -euo pipefail

# =====================================================
# WSL Webstack installer (Apache + PHP + MariaDB + phpMyAdmin)
# - schakelt extensies in: zip, gd, soap, xml, mysqli, pdo_mysql, curl
# - past php.ini aan (enkele dev-settings)
# - installeert phpMyAdmin en activeert de config voor Apache
# - maakt MySQL gebruiker 'Daan'@'localhost' met leeg wachtwoord en ALL PRIVILEGES
# - schakelt AllowNoPassword in voor phpMyAdmin
# =====================================================

WEBROOT="/var/www/html"
DB_NAME="projectdb"
DB_USER="devuser"
DB_PASS="devpass"
MYSQL_ADMIN_USER="daan"
MYSQL_ADMIN_PASS=""   # leeg wachtwoord (intentioneel voor lokaal dev)

echo "🚀 Start installatie: Apache, PHP (+exts), MariaDB, phpMyAdmin"

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
# Binnen WSL is default root auth via unix_socket, we voeren minimale veilige defaults maar
# omdat we willen Daan zonder wachtwoord maken, slaan we dat apart over.
# We run minimal "remove test DB" style commands.
sudo mysql -u root <<'SQL'
-- minimal cleanup (ok to run even if already set)
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
SQL

# -------------------------
# Maak admin user met leeg wachtwoord (LOCAL ONLY)
# -------------------------
echo "🔐 Aanmaken MySQL admin user '$MYSQL_ADMIN_USER' met leeg wachtwoord (localhost only)"
# Create user with empty password and give ALL PRIVILEGES on *.* and grant option
sudo mysql -u root <<SQL
CREATE USER IF NOT EXISTS '${MYSQL_ADMIN_USER}'@'localhost' IDENTIFIED BY '';
GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_ADMIN_USER}'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

echo "ℹ️  MySQL admin user '${MYSQL_ADMIN_USER}'@'localhost' aangemaakt met leeg wachtwoord."

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
# phpMyAdmin config aanpassen: AllowNoPassword op true
# -------------------------
PHPMYADMIN_CONFIG="/etc/phpmyadmin/config.inc.php"

if [ -f "$PHPMYADMIN_CONFIG" ]; then
  echo "🔓 AllowNoPassword instelling activeren in phpMyAdmin..."
  
  # Maak backup van originele config
  sudo cp "$PHPMYADMIN_CONFIG" "${PHPMYADMIN_CONFIG}.bak"
  
  # Zoek of AllowNoPassword al bestaat en pas aan, of voeg toe
  if sudo grep -q "\$cfg\['Servers'\]\[\$i\]\['AllowNoPassword'\]" "$PHPMYADMIN_CONFIG"; then
    # Bestaat al, pas aan naar true
    sudo sed -i "s/\$cfg\['Servers'\]\[\$i\]\['AllowNoPassword'\]\s*=\s*false;/\$cfg['Servers'][\$i]['AllowNoPassword'] = true;/" "$PHPMYADMIN_CONFIG"
    echo "✅ AllowNoPassword aangepast naar true."
  else
    # Bestaat niet, voeg toe na de auth_type regel
    sudo sed -i "/\$cfg\['Servers'\]\[\$i\]\['auth_type'\]/a \$cfg['Servers'][\$i]['AllowNoPassword'] = true;" "$PHPMYADMIN_CONFIG"
    echo "✅ AllowNoPassword toegevoegd en ingesteld op true."
  fi
else
  echo "⚠️  phpMyAdmin config niet gevonden op $PHPMYADMIN_CONFIG"
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
echo " - phpMyAdmin AllowNoPassword: INGESCHAKELD"
echo " - MySQL admin user: ${MYSQL_ADMIN_USER}@localhost (leeg wachtwoord)"
echo ""
echo "⚠️ Veiligheidsherinnering: ${MYSQL_ADMIN_USER}@localhost bevat geen wachtwoord. Dit is enkel geschikt voor lokale dev. Zorg dat je dit NIET toepast op productieservers."
echo ""
echo "🔁 Voer 'wsl --shutdown' uit in PowerShell als je wijzigingen in /etc/wsl.conf hebt gedaan en start WSL opnieuw."
