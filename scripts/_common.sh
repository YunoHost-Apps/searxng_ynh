#!/bin/bash

#=================================================
# COMMON VARIABLES
#=================================================

repo_fullpath="https://github.com/searxng/searxng"
commit_sha="38fdd2288a8c5ffbd94c6068bc4ef6ec9a3df415"

#=================================================
# UWSGI HELPERS
#=================================================

# Check if system wide templates are available and correcly configured
#
# usage: ynh_check_global_uwsgi_config
ynh_check_global_uwsgi_config () {
	uwsgi --version || ynh_die --message="You need to add uwsgi (and appropriate plugin) as a dependency"

	cat > "/etc/systemd/system/uwsgi-app@.service" <<EOF
[Unit]
Description=%i uWSGI app
After=syslog.target

[Service]
RuntimeDirectory=%i
ExecStart=/usr/bin/uwsgi \
        --ini /etc/uwsgi/apps-available/%i.ini \
        --socket /run/%i/app.socket \
        --logto /var/log/uwsgi/%i/%i.log
User=%i
Group=www-data
Restart=always
RestartSec=10
KillSignal=SIGQUIT
Type=notify
NotifyAccess=all

[Install]
WantedBy=multi-user.target
EOF

	systemctl daemon-reload
}

# Create a dedicated uwsgi ini file to use with generic uwsgi service
#
# To be able to customise the settings of the systemd unit you can override the rules with the file "conf/uwsgi-app@override.service".
# This file will be automatically placed on the good place
# 
# Note that the service need to be started manually at the end of the installation.
# Generally you can start the service with this command:
# ynh_systemd_action --service_name "uwsgi-app@$app.service" --line_match "WSGI app 0 \(mountpoint='[/[:alnum:]_-]*'\) ready in [[:digit:]]* seconds on interpreter" --log_path "/var/log/uwsgi/$app/$app.log"
#
# usage: ynh_add_uwsgi_service
#
# to interact with your service: `systemctl <action> uwsgi-app@app`
ynh_add_uwsgi_service () {
	ynh_check_global_uwsgi_config

	local finaluwsgiini="/etc/uwsgi/apps-available/$app.ini"

	# www-data group is needed since it is this nginx who will start the service
	usermod --append --groups www-data "$app" || ynh_die --message="It wasn't possible to add user $app to group www-data"

	ynh_add_config --template="uwsgi.ini" --destination="$finaluwsgiini"
	ynh_store_file_checksum --file="$finaluwsgiini"
	chown $app:root "$finaluwsgiini"

	# make sure the folder for logs exists and set authorizations
	mkdir -p "/var/log/uwsgi/$app"
	chown $app:root "/var/log/uwsgi/$app"
	chmod -R u=rwX,g=rX,o= "/var/log/uwsgi/$app"

	# Setup specific Systemd rules if necessary
	mkdir -p "/etc/systemd/system/uwsgi-app@$app.service.d"
	if [ -e "../conf/uwsgi-app@override.service" ]; then
		ynh_add_config --template="uwsgi-app@override.service" --destination="/etc/systemd/system/uwsgi-app@$app.service.d/override.conf"
	fi

	systemctl daemon-reload
	ynh_systemd_action --service_name="uwsgi-app@$app.service" --action="enable"

	# Add as a service
	yunohost service add "uwsgi-app@$app" --description="uWSGI service for searxng" --log "/var/log/uwsgi/$app/$app.log"
}

# Remove the dedicated uwsgi ini file
#
# usage: ynh_remove_uwsgi_service
ynh_remove_uwsgi_service () {
	local finaluwsgiini="/etc/uwsgi/apps-available/$app.ini"
	if [ -e "$finaluwsgiini" ]; then
		yunohost service remove "uwsgi-app@$app"
		ynh_systemd_action --service_name="uwsgi-app@$app.service" --action="stop"
		ynh_exec_fully_quiet ynh_systemd_action --service_name="uwsgi-app@$app.service" --action="disable"

		ynh_secure_remove --file="$finaluwsgiini"
		ynh_secure_remove --file="/var/log/uwsgi/$app"
		ynh_secure_remove --file="/etc/systemd/system/uwsgi-app@$app.service.d"
	fi
}

# Backup the dedicated uwsgi config
# Should be used in backup script
#
# usage: ynh_backup_uwsgi_service
ynh_backup_uwsgi_service () {
	ynh_backup --src_path="/etc/uwsgi/apps-available/$app.ini"
	ynh_backup --src_path="/etc/systemd/system/uwsgi-app@$app.service.d" --not_mandatory
}

# Restore the dedicated uwsgi config
# Should be used in restore script
#
# usage: ynh_restore_uwsgi_service
ynh_restore_uwsgi_service () {
	ynh_check_global_uwsgi_config
	ynh_restore_file --origin_path="/etc/uwsgi/apps-available/$app.ini"
	ynh_restore_file --origin_path="/etc/systemd/system/uwsgi-app@$app.service.d" --not_mandatory

	mkdir -p "/var/log/uwsgi/$app"
	chown $app:root "/var/log/uwsgi/$app"
	chmod -R u=rwX,g=rX,o= "/var/log/uwsgi/$app"
    
	ynh_systemd_action --service_name="uwsgi-app@$app.service" --action="enable"
	yunohost service add "uwsgi-app@$app" --description="uWSGI service for searxng" --log "/var/log/uwsgi/$app/$app.log"
}
