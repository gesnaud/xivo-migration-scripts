#!/bin/sh

#set -x
set -e


echo "Running XIVO Tardis installation..."

FLAVOUR=$(uname -r | sed -r 's/^.*-([a-z0-9]+)$/\1/')
if [ -n "${FLAVOUR}" ]; then
	echo "Kernel flavour detected: ${FLAVOUR}"
else
	echo "Cannot detect kernel flavour "'!'
	exit 1
fi

if ! $(dpkg -l pf-fai | grep -q ii); then
	echo "PF bootstrapping missing, installing..."

	echo "deb http://dak.proformatique.com/debian/ etch main" >>/etc/apt/sources.list
	wget http://dak.proformatique.com/ziyi_proformatique_current.asc -O - | apt-key add -

	aptitude update >/dev/null
	aptitude -y install pf-fai >/dev/null

	wget -O /etc/apt/sources.list ftp://fai.proformatique.com/fai/xivo-migration/arcadia-torchwood/data/sources.list
	wget -O /etc/apt/apt.conf ftp://fai.proformatique.com/fai/xivo-migration/arcadia-torchwood/data/apt.conf
fi

echo "We let you 5 secondes to check if errors occurred, then installation will continue."
sleep 5

echo "Bootstrapping current XIVO version"
aptitude update >/dev/null
aptitude -y dist-upgrade
aptitude -y install pf-fai-xivo-0.3-tardis >/dev/null

echo "Installing current XIVO version, pray or slay"
echo "---"
aptitude update >/dev/null
aptitude -y install pf-xivo >/dev/null
aptitude -y install zaptel-modules-2.6.18-5-${FLAVOUR} >/dev/null

