#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================
myynh_prepare_source () {
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
	pushd "$install_dir"
		# Create the virtual environment
		ynh_exec_as_app python3 -m venv "searxng-pyenv"
		
		# Print some version information
		ynh_print_info "venv Python version: $(searxng-pyenv/bin/python3 -VV)"

		# Install with pip
		ynh_exec_as_app "searxng-pyenv/bin/pip" install --upgrade pip setuptools wheel
		ynh_exec_as_app "searxng-pyenv/bin/pip" install --requirement "searxng-src/requirements.txt"
		ynh_exec_as_app "searxng-pyenv/bin/pip" install --upgrade granian
		ynh_exec_as_app "searxng-pyenv/bin/pip" install --use-pep517 --no-build-isolation --editable "searxng-src"
	popd
}

# Set permissions
myynh_set_permissions () {
	chown -R $app: "$install_dir"
	chmod u=rwX,g=rX,o= "$install_dir"
	chmod -R o-rwx "$install_dir"
}

