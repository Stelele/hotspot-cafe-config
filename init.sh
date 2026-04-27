#!/bin/bash

DALORADIUS_PATH=/var/www/daloradius
DALORADIUS_CONF_PATH=/var/www/daloradius/app/common/includes/daloradius.conf.php

function init_daloradius {
    if [ ! -f "$DALORADIUS_CONF_PATH" ] || [ ! -s "$DALORADIUS_CONF_PATH" ]; then
        if [ -f "$DALORADIUS_CONF_PATH.sample" ]; then
            cp "$DALORADIUS_CONF_PATH.sample" "$DALORADIUS_CONF_PATH"
        else
            # Create minimal config if sample doesn't exist
            cat > "$DALORADIUS_CONF_PATH" << 'CONFEOF'
<?php
$configValues = array();
$configValues['CONFIG_DB_HOST'] = 'localhost';
$configValues['CONFIG_DB_PORT'] = '3306';
$configValues['CONFIG_DB_USER'] = 'radius';
$configValues['CONFIG_DB_PASS'] = 'radpass';
$configValues['CONFIG_DB_NAME'] = 'radius';
$configValues['CONFIG_DB_PASSWORD_ENCRYPTION'] = 'yes';
$configValues['CONFIG_DB_PASSWORD_MIN_LENGTH'] = '8';
$configValues['CONFIG_DB_PASSWORD_MAX_LENGTH'] = '14';
$configValues['CONFIG_DB_TBL_DALOOPERATORS'] = 'operators';
$configValues['CONFIG_DB_TBL_DALOOPERATORS_ACL'] = 'operators_acl';
$configValues['CONFIG_DB_TBL_DALOOPERATORS_ACL_FILES'] = 'operators_acl_files';
$configValues['CONFIG_MAINT_TEST_USER_RADIUSSERVER'] = 'radius';
$configValues['CONFIG_MAINT_TEST_USER_RADIUSPORT'] = '1812';
$configValues['CONFIG_MAINT_TEST_USER_RADIUSSECRET'] = 'testing123';
$configValues['FREERADIUS_VERSION'] = '3';
$configValues['CONFIG_LOG_FILE'] = '/tmp/daloradius.log';
$configValues['CONFIG_LANG'] = 'en';
?>
CONFEOF
        fi
        chown www-data:www-data "$DALORADIUS_CONF_PATH"
    fi

    [ -n "$MYSQL_HOST" ] && sed -i "s/\$configValues\['CONFIG_DB_HOST'\] = .*;/\$configValues\['CONFIG_DB_HOST'\] = '$MYSQL_HOST';/" $DALORADIUS_CONF_PATH
    [ -n "$MYSQL_PORT" ] && sed -i "s/\$configValues\['CONFIG_DB_PORT'\] = .*;/\$configValues\['CONFIG_DB_PORT'\] = '$MYSQL_PORT';/" $DALORADIUS_CONF_PATH
    [ -n "$MYSQL_PASSWORD" ] && sed -i "s/\$configValues\['CONFIG_DB_PASS'\] = .*;/\$configValues\['CONFIG_DB_PASS'\] = '$MYSQL_PASSWORD';/" $DALORADIUS_CONF_PATH
    [ -n "$MYSQL_USER" ] && sed -i "s/\$configValues\['CONFIG_DB_USER'\] = .*;/\$configValues\['CONFIG_DB_USER'\] = '$MYSQL_USER';/" $DALORADIUS_CONF_PATH
    [ -n "$MYSQL_DATABASE" ] && sed -i "s/\$configValues\['CONFIG_DB_NAME'\] = .*;/\$configValues\['CONFIG_DB_NAME'\] = '$MYSQL_DATABASE';/" $DALORADIUS_CONF_PATH

    sed -i "s/\$configValues\['FREERADIUS_VERSION'\] = .*;/\$configValues\['FREERADIUS_VERSION'\] = '3';/" $DALORADIUS_CONF_PATH

    [ -n "$DEFAULT_FREERADIUS_SERVER" ] \
        && sed -i "s/\$configValues\['CONFIG_MAINT_TEST_USER_RADIUSSERVER'\] = .*;/\$configValues\['CONFIG_MAINT_TEST_USER_RADIUSSERVER'\] = '$DEFAULT_FREERADIUS_SERVER';/" $DALORADIUS_CONF_PATH
    [ -n "$DEFAULT_FREERADIUS_PORT" ] \
        && sed -i "s/\$configValues\['CONFIG_MAINT_TEST_USER_RADIUSPORT'\] = .*;/\$configValues\['CONFIG_MAINT_TEST_USER_RADIUSPORT'\] = '$DEFAULT_FREERADIUS_PORT';/" $DALORADIUS_CONF_PATH
    [ -n "$DEFAULT_CLIENT_SECRET" ] \
        && sed -i "s/\$configValues\['CONFIG_MAINT_TEST_USER_RADIUSSECRET'\] = .*;/\$configValues\['CONFIG_MAINT_TEST_USER_RADIUSSECRET'\] = '$DEFAULT_CLIENT_SECRET';/" $DALORADIUS_CONF_PATH

    sed -i "s/\$configValues\['CONFIG_LOG_FILE'\] = .*;/\$configValues\['CONFIG_LOG_FILE'\] = '\/tmp\/daloradius.log';/" $DALORADIUS_CONF_PATH

    echo "daloRADIUS initialization completed."
}

function init_freeradius {
    echo "Initializing FreeRADIUS..."

    # Copy config templates to active config location
    cp /etc/freeradius/3.0/templates/sql.conf.template /etc/freeradius/3.0/mods-available/sql
    cp /etc/freeradius/3.0/templates/clients.conf.template /etc/freeradius/3.0/clients.conf

    # Replace placeholders with actual values
    sed -i "s/DB_HOST_PLACEHOLDER/$MYSQL_HOST/" /etc/freeradius/3.0/mods-available/sql
    sed -i "s/DB_PORT_PLACEHOLDER/$MYSQL_PORT/" /etc/freeradius/3.0/mods-available/sql
    sed -i "s/DB_USER_PLACEHOLDER/$MYSQL_USER/" /etc/freeradius/3.0/mods-available/sql
    sed -i "s/DB_PASS_PLACEHOLDER/$MYSQL_PASSWORD/" /etc/freeradius/3.0/mods-available/sql
    sed -i "s/DB_NAME_PLACEHOLDER/$MYSQL_DATABASE/" /etc/freeradius/3.0/mods-available/sql

    # Set ownership for FreeRADIUS config files
    chown freerad:freerad /etc/freeradius/3.0/mods-available/sql
    chown freerad:freerad /etc/freeradius/3.0/clients.conf

    # Enable SQL module by creating symlink
    ln -sf /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/sql

    # Enable SQL module in default site config (uncomment -sql -> sql)
    sed -i 's/^\t-sql$/\tsql/' /etc/freeradius/3.0/sites-enabled/default

    # Load FreeRADIUS SQL schema into database if tables don't exist
    echo -n "Checking FreeRADIUS database schema..."
    TABLE_EXISTS=$(mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$MYSQL_DATABASE' AND table_name='radcheck';" 2>/dev/null)

    if [ "$TABLE_EXISTS" != "1" ]; then
        echo "loading schema..."
        mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < /var/www/daloradius/contrib/db/fr3-mariadb-freeradius.sql 2>/dev/null
        mysql -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < /var/www/daloradius/contrib/db/mariadb-daloradius.sql 2>/dev/null
        echo "schema loaded successfully"
    else
        echo "schema already exists"
    fi

    # Disable TLS in SQL module (matching official guide approach)
    sed -Ei '/^\[\t\s#\]*tls\s+\{/, /\[\t\s#\]*\}/ s/^/#/' /etc/freeradius/3.0/mods-available/sql

    echo "FreeRADIUS initialization completed."
}

echo "Starting daloRADIUS..."

# Configure daloRADIUS
init_daloradius

# Wait for MySQL to be ready (with timeout)
echo -n "Waiting for mysql ($MYSQL_HOST)..."
for i in $(seq 30); do
    if mysqladmin ping -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" --silent 2>/dev/null; then
        echo "ok"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "timeout, proceeding anyway..."
    fi
    sleep 2
done

# Configure and start FreeRADIUS
init_freeradius

# Kill any existing FreeRADIUS processes
killall freeradius 2>/dev/null
sleep 1

# Start FreeRADIUS daemon
echo "Starting FreeRADIUS..."
freeradius -l /var/log/freeradius/radius.log
sleep 2

# Verify FreeRADIUS started
if pgrep -x freeradius > /dev/null; then
    echo "FreeRADIUS started successfully"
else
    echo "WARNING: FreeRADIUS failed to start"
fi

# Start Apache2 in the foreground
exec /usr/sbin/apachectl -DFOREGROUND -k start
