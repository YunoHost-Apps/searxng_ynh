#!/bin/bash

#=================================================
# COMMON VARIABLES
#=================================================

#=================================================
# PERSONAL HELPERS
#=================================================

# Install/Upgrade SearXNG in virtual environement
myynh_source_searxng () {
	# Retrieve info from manifest
	repo_fullpath=$(ynh_read_manifest --manifest_key="upstream.code")
	commit_sha=$(ynh_read_manifest --manifest_key="resources.sources.main.url" | xargs basename --suffix=".tar.gz")

	# Download source
	sudo -i -u $app bash << EOF
git clone -n "$repo_fullpath" "$install_dir/searxng-src"
pushd "$install_dir/searxng-src"
	ynh_exec_fully_quiet git checkout "$commit_sha"
popd
EOF
}

myynh_install_searxng () {
	# Create the virtual environment
	sudo -H -u $app -i bash << EOF
python3 -m venv "$install_dir/searxng-pyenv"
echo ". $install_dir/searxng-pyenv/bin/activate" >>  "$install_dir/.profile"
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
pip install -e .
EOF
}

# Upgrade the virtual environment directory
myynh_upgrade_venv_directory () {

	# Remove old python links before recreating them
	find "$install_dir/bin/" -type l -name 'python*' \
		-exec bash -c 'rm --force "$1"' _ {} \;

	# Remove old python directories before recreating them
	find "$install_dir/lib/" -mindepth 1 -maxdepth 1 -type d -name "python*" \
		-not -path "*/python${py_required_version%.*}" \
		-exec bash -c 'rm --force --recursive "$1"' _ {} \;
	find "$install_dir/include/site/" -mindepth 1 -maxdepth 1 -type d -name "python*" \
		-not -path "*/python${py_required_version%.*}" \
		-exec bash -c 'rm --force --recursive "$1"' _ {} \;

	# Upgrade the virtual environment directory
	sudo -H -u $app -i bash << EOF
python3 -m venv --upgrade "$install_dir"
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
