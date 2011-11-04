#!/bin/sh

#set -x
set -e


echo "Running migration from XIVO Torchwood to Tardis..."

FLAVOUR=$(uname -r | sed -r 's/^.*-([a-z0-9]+)$/\1/')
if [ -n "${FLAVOUR}" ]; then
	echo "Kernel flavour detected: ${FLAVOUR}"
else
	echo "Cannot detect kernel flavour "'!'
	exit 1
fi

BACKUP_CONF_BASE=/root/xivo-migration
BACKUP_CONF=${BACKUP_CONF_BASE}/torchwood-tardis
if [ -e "${BACKUP_CONF}" ]; then
	echo "A backup of the configuration already exist"
	echo " Something must have gone wrong in the previous run :-("
	echo " Better luck this time"'!'
else
	echo "Backuping configuration before proceeding"
	mkdir -p ${BACKUP_CONF}
	cp -a /etc /tftpboot ${BACKUP_CONF}
fi

echo "Ensure we are starting from the latest revision"
aptitude update
aptitude -y dist-upgrade

echo "We let you 5 secondes to check if errors occurred, then migration will continue."
sleep 5

echo "Bootstrapping new XIVO version"
aptitude update
aptitude -y install pf-fai-xivo-0.3-tardis

echo "Installing new XIVO version, pray or slay"
echo "---"
aptitude update
# leaving this touchy chapter to the user...
aptitude dist-upgrade
aptitude clean

