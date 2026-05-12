#!/bin/bash
set -euo pipefail

APACHE_CONF="/etc/apache2/sites-available/ws1c.conf"

if ! grep -q "_1cws_module" "${APACHE_CONF}" 2>/dev/null; then
  echo "LoadModule _1cws_module ${SRV_HOME}/wsap24.so" >> "${APACHE_CONF}"
fi

chmod -R 755 /var/www

a2ensite ws1c.conf >/dev/null || true
service apache2 start
service apache2 reload

gosu usr1cv8 "${SRV_HOME}/ras" cluster localhost:1540 --daemon

exec gosu usr1cv8 "${SRV_HOME}/ragent"
