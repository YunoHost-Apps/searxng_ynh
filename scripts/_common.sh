#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================
myynh_setup_source () {
	# Download source
	mkdir "$install_dir/searxng-src"
	ynh_setup_source --dest_dir="$install_dir/searxng-src"

	# Retrieve version information
	local version=$(ynh_read_manifest "version" | cut -d'~' -f1)
	local commit=$(ynh_read_manifest "resources.sources.main.url" | xargs basename | head -c 9)

	# Set needed information
	version_string="$version+$commit"
	git_url=$(ynh_read_manifest "upstream.code")

	# Replace hardcoded information
	ynh_replace_regex --match="^VERSION_STRING: str = .*" \
		--replace="VERSION_STRING: str = \"$version_string\"" \
		--file="$install_dir/searxng-src/searx/version.py"
	ynh_replace_regex --match="^GIT_URL: str = .*" \
		--replace="GIT_URL: str = \"$git_url\"" \
		--file="$install_dir/searxng-src/searx/version.py"
}

myynh_install_searxng () {
	# Create the virtual environment
	sudo -H -u $app -i bash << EOF
python3 -m venv "$install_dir/searxng-pyenv"
echo ". $install_dir/searxng-pyenv/bin/activate" > "$install_dir/.profile"
EOF

	# Check if virtualenv was sourced from the login
	sudo -H -u $app -i bash << EOF
command -v python && python --version
EOF

	# Install with pip
	sudo -H -u $app -i bash << EOF
pip install --upgrade pip
pip install --upgrade setuptools
pip install --upgrade wheel
pip install --requirement "$install_dir/searxng-src/requirements.txt"
pip install --requirement "$install_dir/searxng-src/requirements-server.txt"
pip install --use-pep517 --no-build-isolation -e "$install_dir/searxng-src"
EOF
}

# Set permissions
myynh_set_permissions () {
	chown -R $app: "$install_dir"
	chmod u=rwX,g=rX,o= "$install_dir"
	chmod -R o-rwx "$install_dir"

	chown $app:root "/etc/uwsgi/apps-available/$app.ini"
	chown -R $app:root "/etc/systemd/system/uwsgi-app@$app.service.d" || true

	chown $app:root "/var/log/uwsgi/$app"
	chmod -R u=rwX,g=rX,o= "/var/log/uwsgi/$app"
}

#=================================================
# UWSGI HELPERS
#=================================================

# Check if system wide templates are available and correcly configured
#
# usage: ynh_check_global_uwsgi_config
ynh_check_global_uwsgi_config () {
	uwsgi --version || ynh_die "You need to add uwsgi (and appropriate plugin) as a dependency"

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
# ynh_systemctl --service "uwsgi-app@$app.service" --wait_until "WSGI app 0 \(mountpoint='[/[:alnum:]_-]*'\) ready in [[:digit:]]* seconds on interpreter" --log_path "/var/log/uwsgi/$app/$app.log"
#
# usage: ynh_add_uwsgi_service
#
# to interact with your service: `systemctl <action> uwsgi-app@app`
ynh_add_uwsgi_service () {
	ynh_check_global_uwsgi_config

	local finaluwsgiini="/etc/uwsgi/apps-available/$app.ini"

	# www-data group is needed since it is this nginx who will start the service
	usermod --append --groups www-data "$app" || ynh_die "It wasn't possible to add user $app to group www-data"

	ynh_config_add --template="uwsgi.ini" --destination="$finaluwsgiini"
	ynh_store_file_checksum "$finaluwsgiini"
	chown $app:root "$finaluwsgiini"

	# make sure the folder for logs exists and set authorizations
	mkdir -p "/var/log/uwsgi/$app"

	# Setup specific Systemd rules if necessary
	mkdir -p "/etc/systemd/system/uwsgi-app@$app.service.d"
	if [ -e "../conf/uwsgi-app@override.service" ]
	then
		ynh_config_add --template="uwsgi-app@override.service" \
			--destination="/etc/systemd/system/uwsgi-app@$app.service.d/override.conf"
	fi

	systemctl daemon-reload
	ynh_systemctl --service="uwsgi-app@$app.service" \
		--action="enable"

	# Add as a service
	yunohost service add "uwsgi-app@$app" \
		--description="uWSGI service for searxng" \
		--log "/var/log/uwsgi/$app/$app.log"
}

# Remove the dedicated uwsgi ini file
#
# usage: ynh_remove_uwsgi_service
ynh_remove_uwsgi_service () {
	local finaluwsgiini="/etc/uwsgi/apps-available/$app.ini"
	if [ -e "$finaluwsgiini" ]
	then
		yunohost service remove "uwsgi-app@$app"
		ynh_systemctl --service="uwsgi-app@$app.service" \
			--action="stop"
		ynh_systemctl --service="uwsgi-app@$app.service" \
			--action="disable"

		ynh_safe_rm "$finaluwsgiini"
		ynh_safe_rm "/var/log/uwsgi/$app"
		ynh_safe_rm "/etc/systemd/system/uwsgi-app@$app.service.d"
	fi
}

# Backup the dedicated uwsgi config
# Should be used in backup script
#
# usage: ynh_backup_uwsgi_service
ynh_backup_uwsgi_service () {
	ynh_backup "/etc/uwsgi/apps-available/$app.ini"
	ynh_backup "/etc/systemd/system/uwsgi-app@$app.service.d" || true
}

# Restore the dedicated uwsgi config
# Should be used in restore script
#
# usage: ynh_restore_uwsgi_service
ynh_restore_uwsgi_service () {
	ynh_check_global_uwsgi_config
	ynh_restore "/etc/uwsgi/apps-available/$app.ini"
	ynh_restore "/etc/systemd/system/uwsgi-app@$app.service.d" || true

	mkdir -p "/var/log/uwsgi/$app"

	ynh_systemctl --service="uwsgi-app@$app.service" \
		--action="enable"
	yunohost service add "uwsgi-app@$app" \
		--description="uWSGI service for searxng" \
		--log "/var/log/uwsgi/$app/$app.log"
}
