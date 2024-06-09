#!/bin/bash

#=================================================
# PACKAGE UPDATING HELPER
#=================================================

# This script is meant to be run by GitHub Actions
# The YunoHost-Apps organisation offers a template Action to run this script periodically
# Since each app is different, maintainers can adapt its contents so as to perform
# automatic actions when a new upstream release is detected.

#=================================================
# FETCHING LATEST RELEASE AND ITS ASSETS
#=================================================

# Fetching information
current_version=$(cat manifest.toml | tomlq -j '.version|split("~")[0]')
repo=$(cat manifest.toml | tomlq -j '.upstream.code|split("https://github.com/")[1]')
# Some jq magic is needed, because the latest upstream release is not always the latest version (e.g. security patches for older versions)
version_raw=$(curl --silent "https://api.github.com/repos/$repo/commits/master" | jq -r ".commit.committer.date")
version=$(date -d "$version_raw" +%Y.%m.%d.%H.%M.%S)
commit_hash=$(curl --silent "https://api.github.com/repos/$repo/commits/master" | jq -r ".sha")

# Setting up the environment variables
echo "Current version: $current_version"
echo "Latest release from upstream: $version"
echo "VERSION=$version" >> $GITHUB_ENV
echo "REPO=$repo" >> $GITHUB_ENV
# For the time being, let's assume the script will fail
echo "PROCEED=false" >> $GITHUB_ENV

# Proceed only if the retrieved version is greater than the current one
if ! dpkg --compare-versions "$current_version" "lt" "$version" ; then
    echo "::warning ::No new version available"
    exit 0
# Proceed only if a PR for this new version does not already exist
elif git ls-remote -q --exit-code --heads https://github.com/$GITHUB_REPOSITORY.git ci-auto-update-v$version ; then
    echo "::warning ::A branch already exists for this update"
    exit 0
fi

#=================================================
# UPDATE SOURCE FILES
#=================================================

#=================================================
# SPECIFIC UPDATE STEPS
#=================================================

# Replace new version in _common.sh
sed -i "s/^commit_sha=.*/commit_sha=\"$commit_hash\"/" scripts/_common.sh

#=================================================
# GENERIC FINALIZATION
#=================================================

# Replace new version in manifest
sed -i "s/^version = .*/version = \"$version~ynh1\"/" manifest.toml

# No need to update the README, yunohost-bot takes care of it

# The Action will proceed only if the PROCEED environment variable is set to true
echo "PROCEED=true" >> $GITHUB_ENV
exit 0
