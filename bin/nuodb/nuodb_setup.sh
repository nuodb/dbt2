#!/bin/sh

NUODB_HOME=/opt/nuodb
NUODB_DB=dbt2
NUODB_USERNAME=dbt2
NUODB_PASSWORD=dbt2
NUODB_SCHEMA=dbt2

[ -n "$NUO_VERSION" ] || { echo "Missing version"; exit 1; }

# Ensure THP is not on
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/defrag >/dev/null

wget -q "http://download.nuohub.org/nuodb-ce_${NUO_VERSION}_amd64.deb" --output-document=/var/tmp/nuodb.deb
sudo dpkg -i /var/tmp/nuodb.deb

