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
pip install --upgrade gunicorn
pip install --use-pep517 --no-build-isolation -e "$install_dir/searxng-src"
EOF
}

# Set permissions
myynh_set_permissions () {
	chown -R $app: "$install_dir"
	chmod u=rwX,g=rX,o= "$install_dir"
	chmod -R o-rwx "$install_dir"
}

#=================================================
# UWSGI HELPERS
#=================================================

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

#=================================================
# SYSTEMD SOCKET HELPERS
#=================================================

# Create a dedicated systemd socket config
# usage: ynh_add_systemd_socket_config [--socket=socket] [--template=template]
# | arg: --socket=      - Socket name (optional, `$app` by default)
# | arg: --template=    - Name of template file (optional, this is 'systemd' by default, meaning `../conf/systemd.socket` will be used as template)
#
# This will use the template `../conf/<templatename>.socket`.
#
# See the documentation of `ynh_config_add` for a description of the template
# format and how placeholders are replaced with actual variables.
ynh_config_add_systemd_socket() {
	# ============ Argument parsing =============
	local -A args_array=([s]=socket= [t]=template=)
	local socket
	local template
	ynh_handle_getopts_args "$@"
	socket="${socket:-$app}"
	template="${template:-systemd.socket}"
	# ===========================================

	ynh_config_add --template="$template" --destination="/etc/systemd/system/$socket.socket"

	systemctl enable "$socket.socket" --quiet
	systemctl daemon-reload
}

# Remove the dedicated systemd socket config
#
# usage: ynh_config_remove_systemd socket
# | arg: socket   - Socket name (optionnal, $app by default)
ynh_config_remove_systemd_socket() {
	local socket="${1:-$app}"
	if [ -e "/etc/systemd/system/$socket.socket" ]; then
		ynh_systemctl --service="$socket" --action=stop
		systemctl disable "$socket" --quiet
		ynh_safe_rm "/etc/systemd/system/$socket.socket"
		systemctl daemon-reload
	fi
}
