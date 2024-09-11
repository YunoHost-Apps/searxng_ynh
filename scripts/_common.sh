#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

# Install/Upgrade SearXNG in virtual environement
myynh_source_searxng () {
	# Retrieve info from manifest
	repo_fullpath=$(ynh_read_manifest
	commit_sha=$(ynh_read_manifest | xargs basename --suffix=".tar.gz")

	# Download source
	sudo -H -u $app -i bash << EOF
mkdir "$install_dir/searxng-src"
git clone -n "$repo_fullpath" "$install_dir/searxng-src" 2>&1
EOF

	# Checkout commit
	pushd "$install_dir/searxng-src"
	sudo -H -u $app -i bash << EOF
	cd "$install_dir/searxng-src"
	git checkout "$commit_sha" 2>&1
EOF
	popd
}

myynh_install_searxng () {
	# Create the virtual environment
	sudo -H -u $app -i bash << EOF
python3 -m venv "$install_dir/searxng-pyenv"
echo ". $install_dir/searxng-pyenv/bin/activate" >  "$install_dir/.profile"
EOF

	# Check if virtualenv was sourced from the login
	sudo -H -u $app -i bash << EOF
command -v python && python --version
EOF

	sudo -H -u $app -i bash << EOF
pip install --upgrade pip
pip install --upgrade setuptools
pip install --upgrade wheel
pip install --upgrade pyyaml
cd "$install_dir/searxng-src"
pip install --use-pep517 --no-build-isolation -e .
EOF
}

# Set permissions
myynh_set_permissions () {
	chown -R $app: "$install_dir"
	chmod 750 "$install_dir"
	chmod -R o-rwx "$install_dir"
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
	chown $app:root "/var/log/uwsgi/$app"
	chmod -R u=rwX,g=rX,o= "/var/log/uwsgi/$app"

	# Setup specific Systemd rules if necessary
	mkdir -p "/etc/systemd/system/uwsgi-app@$app.service.d"
	if [ -e "../conf/uwsgi-app@override.service" ]
	then
		ynh_config_add --template="uwsgi-app@override.service" --destination="/etc/systemd/system/uwsgi-app@$app.service.d/override.conf"
	fi

	systemctl daemon-reload
	ynh_systemctl --service="uwsgi-app@$app.service" --action="enable"

	# Add as a service
	yunohost service add "uwsgi-app@$app" --description="uWSGI service for searxng" --log "/var/log/uwsgi/$app/$app.log"
}

# Remove the dedicated uwsgi ini file
#
# usage: ynh_remove_uwsgi_service
ynh_remove_uwsgi_service () {
	local finaluwsgiini="/etc/uwsgi/apps-available/$app.ini"
	if [ -e "$finaluwsgiini" ]
	then
		yunohost service remove "uwsgi-app@$app"
		ynh_systemctl --service="uwsgi-app@$app.service" --action="stop"
		ynh_systemctl --service="uwsgi-app@$app.service" --action="disable"

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
	chown $app:root "/var/log/uwsgi/$app"
	chmod -R u=rwX,g=rX,o= "/var/log/uwsgi/$app"

	ynh_systemctl --service="uwsgi-app@$app.service" --action="enable"
	yunohost service add "uwsgi-app@$app" --description="uWSGI service for searxng" --log "/var/log/uwsgi/$app/$app.log"
}
