#!/bin/sh

#set -x
set -e


ask_yn_question()
{
	QUESTION=$1

	while true; do
		echo -n "${QUESTION} (y/n) "
		read REPLY
		if [ "${REPLY}" = "y" ]; then
			return 0;
		fi
		if [ "${REPLY}" = "n" ]; then
			return 1;
		fi
		echo "Don't tell ya life, reply using 'y' or 'n' "'!'
	done
}


echo "Running migration from XIVO Arcadia to Torchwood..."

FLAVOUR=$(uname -r | sed -r 's/^.*-([a-z0-9]+)$/\1/')
if [ -n "${FLAVOUR}" ]; then
	echo "Kernel flavour detected: ${FLAVOUR}"
else
	echo "Cannot detect kernel flavour "'!'
	exit 1
fi

BACKUP_CONF_BASE=/root/xivo-migration
BACKUP_CONF=${BACKUP_CONF_BASE}/arcadia-torchwood
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

UNCLEAN=
if $(dpkg -l pf-config | grep -q ii); then
	UNCLEAN=1

	echo "Old installation method detected, fixing"

	aptitude update
	aptitude -y install pf-fai

	wget -O /etc/apt/sources.list ftp://fai.proformatique.com/fai/xivo-migration/arcadia-torchwood/data/sources.list
	wget -O /etc/apt/apt.conf ftp://fai.proformatique.com/fai/xivo-migration/arcadia-torchwood/data/apt.conf
fi

echo "We let you 5 secondes to check if errors occurred, then migration will continue."
sleep 5

echo "Bootstrapping new XIVO version"
aptitude update
aptitude -y install pf-fai-xivo-0.2-torchwood
aptitude unmarkauto zaptel-modules-2.6.18-5-${FLAVOUR}

echo "Some features are now optional, discussing their fate"
FEATURES_NOW_OPTIONAL="fax capi misdn"
FEATURE_DEPS_fax="asterisk-app-fax"
FEATURE_DEPS_capi="asterisk-chan-capi"
FEATURE_DEPS_misdn="asterisk-chan-misdn misdn-modules-2.6.18-5-${FLAVOUR}"
for FEAT in ${FEATURES_NOW_OPTIONAL}; do
	CMD=markauto
	if ask_yn_question "Do you want to keep ${FEAT} support installed ?"; then
		CMD=unmarkauto
	fi
	# manage marks in all cases, to all changing in a subsequent run (if things went wrong)
	Z=FEATURE_DEPS_${FEAT}
	PKGLIST=${!Z}
	aptitude ${CMD} ${PKGLIST}
done

echo "Installing new XIVO version, pray or slay"
echo "---"
aptitude update
# leaving this touchy chapter to the user...
aptitude dist-upgrade
aptitude clean

