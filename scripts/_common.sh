#!/bin/bash

#=================================================
# COMMON VARIABLES
#=================================================
pkg_dependencies="python3-dev python3-babel python3-venv uwsgi uwsgi-plugin-python3 git build-essential libxslt-dev zlib1g-dev libffi-dev libssl-dev"

#=================================================
# UWSGI HELPERS
#=================================================

# Check if system wide templates are available and correcly configured
#
# usage: ynh_check_global_uwsgi_config
ynh_check_global_uwsgi_config () {
    uwsgi --version || ynh_die --message "You need to add uwsgi (and appropriate plugin) as a dependency"

    cat > /etc/systemd/system/uwsgi-app@.service <<EOF
[Unit]
Description=%i uWSGI app
After=syslog.target
[Service]
RuntimeDirectory=%i
ExecStart=/usr/bin/uwsgi \
        -H /opt/yunohost/searxng/ \
        --ini /etc/uwsgi/apps-available/%i.ini \
        --socket /var/run/%i/app.socket \
        --logto /var/log/uwsgi/%i/%i.log
User=%i
Group=www-data
Restart=on-failure
KillSignal=SIGQUIT
Type=notify
StandardError=syslog
NotifyAccess=all
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}

# Create a dedicated uwsgi ini file to use with generic uwsgi service
#
# This will use a template in ../conf/uwsgi.ini
# and will replace the following keywords with
# global variables that should be defined before calling
# this helper :
#
#   __APP__       by  $app
#   __PATH__      by  $path_url
#   __FINALPATH__ by  $final_path
#
#  And dynamic variables (from the last example) :
#   __PATH_2__    by $path_2
#   __PORT_2__    by $port_2
#
# To be able to customise the settings of the systemd unit you can override the rules with the file "conf/uwsgi-app@override.service".
# This file will be automatically placed on the good place
#
# usage: ynh_add_uwsgi_service
#
# to interact with your service: `systemctl <action> uwsgi-app@app`
ynh_add_uwsgi_service () {
    ynh_check_global_uwsgi_config

    local others_var=${1:-}
    local finaluwsgiini="/etc/uwsgi/apps-available/$app.ini"

    # www-data group is needed since it is this nginx who will start the service
    usermod --append --groups www-data "$app" || ynh_die --message "It wasn't possible to add user $app to group www-data"

    ynh_backup_if_checksum_is_different "$finaluwsgiini"
    cp ../conf/uwsgi.ini "$finaluwsgiini"

    # To avoid a break by set -u, use a void substitution ${var:-}. If the variable is not set, it's simply set with an empty variable.
    # Substitute in a nginx config file only if the variable is not empty
    if test -n "${final_path:-}"; then
        ynh_replace_string --match_string "__FINALPATH__" --replace_string "$final_path" --target_file "$finaluwsgiini"
    fi
    if test -n "${path_url:-}"; then
        ynh_replace_string --match_string "__PATH__" --replace_string "$path_url" --target_file "$finaluwsgiini"
    fi
    if test -n "${app:-}"; then
        ynh_replace_string --match_string "__APP__" --replace_string "$app" --target_file "$finaluwsgiini"
    fi

    # Replace all other variable given as arguments
    for var_to_replace in $others_var
    do
        # ${var_to_replace^^} make the content of the variable on upper-cases
        # ${!var_to_replace} get the content of the variable named $var_to_replace 
        ynh_replace_string --match_string "__${var_to_replace^^}__" --replace_string "${!var_to_replace}" --target_file "$finaluwsgiini"
    done

    ynh_store_file_checksum --file "$finaluwsgiini"

    chown $app:root "$finaluwsgiini"

    # make sure the folder for logs exists and set authorizations
    mkdir -p /var/log/uwsgi/$app
    chown $app:root /var/log/uwsgi/$app
    chmod -R u=rwX,g=rX,o= /var/log/uwsgi/$app

    # Setup specific Systemd rules if necessary
    test -e ../conf/uwsgi-app@override.service && \
        mkdir /etc/systemd/system/uwsgi-app@$app.service.d && \
        cp ../conf/uwsgi-app@override.service /etc/systemd/system/uwsgi-app@$app.service.d/override.conf

    systemctl daemon-reload
    systemctl enable "uwsgi-app@$app.service" --quiet

    # Add as a service
    yunohost service add "uwsgi-app@$app" --log "/var/log/uwsgi/$app/$app.log"
}

# Remove the dedicated uwsgi ini file
#
# usage: ynh_remove_uwsgi_service
ynh_remove_uwsgi_service () {
    local finaluwsgiini="/etc/uwsgi/apps-available/$app.ini"
    if [ -e "$finaluwsgiini" ]; then
        yunohost service remove "uwsgi-app@$app"
        systemctl disable "uwsgi-app@$app.service" --quiet

        ynh_secure_remove --file="$finaluwsgiini"
        ynh_secure_remove --file="/var/log/uwsgi/$app"
        ynh_secure_remove --file="/etc/systemd/system/uwsgi-app@$app.service.d"
    fi
    if [ -e /etc/init.d/uwsgi ]
    then
        # Redémarre le service uwsgi si il n'est pas désinstallé.
        ynh_systemd_action --service_name=uwsgi --action=start
    else
        if yunohost service status | grep -q uwsgi
        then
            ynh_print_info --message="Remove uwsgi service"
            yunohost service remove uwsgi
        fi
    fi
}


#=================================================

# Remove a file or a directory securely
#
# usage: ynh_regex_secure_remove --file=path_to_remove [--regex=regex to append to $file] [--non_recursive] [--dry_run]
# | arg: -f, --file - File or directory to remove
# | arg: -r, --regex - Regex to append to $file to filter the files to remove
# | arg: -n, --non_recursive - Perform a non recursive rm and a non recursive search with the regex
# | arg: -d, --dry_run - Do not remove, only list the files to remove
#
# Requires YunoHost version 2.6.4 or higher.
ynh_regex_secure_remove () {
    # Declare an array to define the options of this helper.
    local legacy_args=frnd
    declare -Ar args_array=( [f]=file= [r]=regex= [n]=non_recursive [d]=dry_run )
    local file
    local regex
    local dry_run
    local non_recursive
    # Manage arguments with getopts
    ynh_handle_getopts_args "$@"
    regex=${regex:-}
    dry_run=${dry_run:-0}
    non_recursive=${non_recursive:-0}

    local forbidden_path="
/var/www \
/home/yunohost.app"

    # Fail if no argument is provided to the helper.
    if [ -z "$file" ]
    then
        ynh_print_warn --message="ynh_regex_secure_remove called with no argument --file, ignoring."
        return 0
    fi

    if [ -n "$regex" ]
    then
        if [ -e "$file" ]
        then
            if [ $non_recursive -eq 1 ]; then
                local recursive="-maxdepth 1"
            else
                local recursive=""
            fi
            # Use find to list the files in $file and grep to filter with the regex
            files_to_remove="$(find -P "$file" $recursive -name ".." -prune -o -print | grep --extended-regexp "$regex")"
        else
            ynh_print_info --message="'$file' wasn't deleted because it doesn't exist."
            return 0
        fi
    else
        files_to_remove="$file"
    fi

    # Check each file before removing it
    while read file_to_remove
    do
        if [ -n "$file_to_remove" ]
        then
            # Check all forbidden path before removing anything
            # First match all paths or subpaths in $forbidden_path
            if [[ "$forbidden_path" =~ "$file_to_remove" ]] || \
                # Match all first level paths from / (Like /var, /root, etc...)
                [[ "$file_to_remove" =~ ^/[[:alnum:]]+$ ]] || \
                # Match if the path finishes by /. Because it seems there is an empty variable
                [ "${file_to_remove:${#file_to_remove}-1}" = "/" ]
            then
                ynh_print_err --message="Not deleting '$file_to_remove' because this path is forbidden !!!"

            # If the file to remove exists
            elif [ -e "$file_to_remove" ]
            then
                if [ $dry_run -eq 1 ]
                then
                    ynh_print_warn --message="File to remove: $file_to_remove"
                else
                    if [ $non_recursive -eq 1 ]; then
                        local recursive=""
                    else
                        local recursive="--recursive"
                    fi

                    # Remove a file or a directory
                    rm --force $recursive "$file_to_remove"
                fi
            else
                # Ignore non existent files with regex, as we likely remove the parent directory before its content is listed.
                if [ -z "$regex" ]
                then
                    ynh_print_info --message="'$file_to_remove' wasn't deleted because it doesn't exist."
                fi  
            fi
        fi
    done <<< "$(echo "$files_to_remove")"
}
