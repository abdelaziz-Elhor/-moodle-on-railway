#!/bin/bash
set -e

# === Wait for MySQL to be available ===
echo "🛠 Waiting for database connection at ${MOODLE_DATABASE_HOST}:${MOODLE_DATABASE_PORT_NUMBER}..."
until php -r '
$mysqli = new mysqli(
  getenv("MOODLE_DATABASE_HOST"),
  getenv("MOODLE_DATABASE_USER"),
  getenv("MOODLE_DATABASE_PASSWORD"),
  getenv("MOODLE_DATABASE_NAME"),
  (int)getenv("MOODLE_DATABASE_PORT_NUMBER")
);
if ($mysqli->connect_errno) {
  exit(1);
}
'
do
  echo "⏳ Database not ready, retrying in 3s..."
  sleep 3
done

# === Apache Port and Proxy Headers ===
echo "🛠 Patching Apache to listen on 8080..."
sed -i 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf
sed -i 's/^<VirtualHost \*:80>/<VirtualHost *:8080>/' /etc/apache2/sites-enabled/000-default.conf

echo "🔧 Enabling proxy headers support..."
a2enmod remoteip setenvif

# Inject Apache reverse proxy support
sed -i '/<VirtualHost \*:8080>/a \
    # Honor real IP from Railway proxy\n\
    RemoteIPHeader X-Forwarded-For\n\
    RemoteIPInternalProxy 127.0.0.1\n\
    RemoteIPInternalProxy 100.64.0.0/10\n\
    # Honor forwarded protocol (for HTTPS redirect fix)\n\
    SetEnvIf X-Forwarded-Proto https HTTPS=on' /etc/apache2/sites-enabled/000-default.conf

# === Ensure moodledata folder is ready ===
echo "📁 Ensuring moodledata exists and is writable..."
mkdir -p /var/www/moodledata
chown -R www-data:www-data /var/www/moodledata
chmod -R 777 /var/www/moodledata

# === Run CLI Installer if needed ===
if [ ! -f /var/www/html/config.php ]; then
  echo "🚀 Running Moodle CLI installer…"
  php admin/cli/install.php \
    --lang=en \
    --wwwroot="https://magiclms.store" \
    --dataroot="/var/www/moodledata" \
    --dbtype="$MOODLE_DATABASE_TYPE" \
    --dbname="$MOODLE_DATABASE_NAME" \
    --dbuser="$MOODLE_DATABASE_USER" \
    --dbpass="$MOODLE_DATABASE_PASSWORD" \
    --dbhost="$MOODLE_DATABASE_HOST" \
    --dbport="$MOODLE_DATABASE_PORT_NUMBER" \
    --fullname="$MOODLE_SITE_NAME" \
    --shortname="$MOODLE_SITE_NAME" \
    --adminuser="$MOODLE_USERNAME" \
    --adminpass="$MOODLE_PASSWORD" \
    --adminemail="$MOODLE_EMAIL" \
    --agree-license --non-interactive
  echo "✅ Installer done. Generated config.php"
else
  echo "✅ config.php found, skipping install."
fi

# === Patch config.php for proxy support ===
CONFIG=/var/www/html/config.php

echo "🔨 Enforcing correct wwwroot in config.php..."
sed -i "s|^\(\$CFG->wwwroot *= *\).*|\1'https://magiclms.store';|" "$CONFIG"

if ! grep -q "trustedproxy" "$CONFIG"; then
  echo "🔨 Adding reverseproxy, sslproxy and trustedproxy settings to config.php..."
  cat << 'EOF' >> "$CONFIG"

// — Moodle behind a reverse proxy —
$CFG->wwwroot = 'https://magiclms.store';
$CFG->sslproxy = true;
EOF
fi

# === Fix ownership & permissions ===
echo "🔧 Fixing permissions and ownership of Moodle directory..."
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

# === Start Apache ===
echo "🌀 Starting Apache…"
exec apache2-foreground
