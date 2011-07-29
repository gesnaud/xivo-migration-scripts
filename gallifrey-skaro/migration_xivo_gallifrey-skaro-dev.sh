#!/bin/bash

#set -x
set -e

println()
{       
	echo -en "\033[0;36;40m$1\033[0;38;39m\n\r"
}

pkg_installed()
{
  PKG=$1

  dpkg -l ${PKG} 2>/dev/null | grep -qE "^ii"
}

OLD_XIVO_BRANCH="XIVO Gallifrey"
XIVO_BRANCH="XIVO Skaro"

CLEANUP_FILES=

MIGRATION=
if pkg_installed pf-xivo; then
  println "Running migration from ${OLD_XIVO_BRANCH} to ${XIVO_BRANCH}..."
  MIGRATION=1
else
  println "Running ${XIVO_BRANCH} installation..."
fi

# discovery
KERN_REL=$(uname -r)
KERN_FLAVOUR=$(echo ${KERN_REL} | cut -d\- -f3)
if [ -n "${KERN_FLAVOUR}" ]; then
  println "Kernel flavour detected: ${KERN_FLAVOUR}"
else
  println "Cannot detect kernel flavour "'!'
  exit 1
fi

println "Update Proformatique Repository Key"
wget http://mirror.xivo.fr/ziyi_proformatique_current.asc -O - | apt-key add -

println "Preseeding packages"
# preseed debconf to avoid being asked for configuration of new packages
wget -q -O - http://fai.proformatique.com/d-i/squeeze/pkg.cfg | debconf-set-selections
wget -q -O - http://fai.proformatique.com/d-i/squeeze/classes/xivo-skaro/custom.cfg | debconf-set-selections

if [ -n "${MIGRATION}" ]; then
  # necessary because of tools unloading modules would fail
  invoke-rc.d asterisk stop

  BACKUP_CONF_BASE=/root/xivo-migration
  BACKUP_CONF=${BACKUP_CONF_BASE}/gallifrey-skaro
  if [ -e "${BACKUP_CONF}" ]; then
    println "A backup of the configuration already exist"
    println " Something must have gone wrong in the previous run :-("
    println " Better luck this time"'!'
  else
    println "Backuping configuration before proceeding"
    mkdir -p ${BACKUP_CONF}
    cp -a /etc /tftpboot ${BACKUP_CONF}/
    cp -a /var/lib/asterisk ${BACKUP_CONF}/var_lib_asterisk
    # the following is fixed in Dalek
    cp -a /usr/share/asterisk ${BACKUP_CONF}/usr_share_asterisk
  fi

  MIGR_DONE=/var/lib/pf-fai/migration_lenny-squeeze_done
  if [ ! -e ${MIGR_DONE} ]; then
    println "Ensure we are starting from an up-to-date Lenny system"
    apt-get update >/dev/null
    apt-get -y dist-upgrade

    println "Removing old apt lists"
    RM_LIST=$(dpkg -l | grep pf-fai | awk '{print $2}')
    apt-get -y remove --purge ${RM_LIST}

    touch ${MIGR_DONE}
  fi
else
  UPGRD_DONE=/var/lib/pf-fai/upgrade_squeeze_done
  if [ ! -e ${UPGRD_DONE} ]; then
    println "Ensure we are starting from an up-to-date Squeeze system"
    apt-get update >/dev/null
    apt-get -y dist-upgrade
  fi
fi

if ! pkg_installed pf-fai; then
  println "PF bootstrapping missing, installing..."

  SL_TEMP=/etc/apt/sources.list.inst-bak
  cp -a /etc/apt/sources.list /etc/apt/sources.list.inst-bak

  # add base deb line if missing
  if ! rgrep -qE "^deb .*proformatique.* squeeze " /etc/apt/sources.list; then
    echo "deb http://mirror.xivo.fr/debian/ squeeze main" >>/etc/apt/sources.list
  fi

  apt-get update >/dev/null
  apt-get -y install pf-fai pf-fai-dev >/dev/null

  mv /etc/apt/sources.list.inst-bak /etc/apt/sources.list
fi

if [ -n "${MIGRATION}" ]; then
  echo "deb http://ftp.fr.debian.org/debian/ squeeze main contrib non-free" >>/etc/apt/sources.list
  echo "deb http://security.debian.org/ squeeze/updates main" >>/etc/apt/sources.list
  echo "deb http://volatile.debian.org/debian-volatile squeeze/volatile main" >>/etc/apt/sources.list

  APT_CONFIG=/etc/apt/apt.conf.d/pf-squeeze-migration
  if ! apt-config dump | grep APT::Cache-Limit >/dev/null; then
    echo 'APT::Cache-Limit "33554432";' >${APT_CONFIG}
  fi
  CLEANUP_FILES="${CLEANUP_FILES} ${APT_CONFIG}"
fi

println "We let you 5 secondes to check if errors occurred, then migration will continue."
println "If you have custom apt source lists, please cancel and update your deb-lines before rerunning this script."
sleep 5

println "Upgrading APT"
apt-get update >/dev/null
if [ -n "${MIGRATION}" ]; then
  # it is _quite_ difficult to have only needed stuff installed, and not gnome-apt and other Suggests / Recommends
  # (and needed options to avoid this situation only exist in the next version...)
  # perl migration is also quite broken :-(
  apt-get -y --no-remove install apt-utils aptitude apt aptitude-doc-ja- aptitude-doc-en- aptitude-doc-fr- aptitude-doc-fi- aptitude-doc-cs- perl librrds-perl libcrypt-ssleay-perl
else
  apt-get -y install apt
fi

println "Pushing changes still in FAI (not packaged yet)"
# allow late preseeding via packaging
sed -i -r 's/^DPkg::Pre-Install-Pkgs/\/\/DPkg::Pre-Install-Pkgs/' /etc/apt/apt.conf.d/70debconf
chmod 700 /root
echo "BOOTLOGD_ENABLE=Yes" >/etc/default/bootlogd
apt-get -y purge dhcp-client dhcp3-client
apt-get -y --purge install ssh dhcp3-client iproute postfix exim4-base- exim4-config- \
                sudo vim bzip2 less iputils-ping host traceroute popularity-contest \
                linuxlogo tasksel- nvi- vim-tiny-
update-alternatives --set editor $(which vim.basic)
## no disclosure when logouting
echo "clear" >/root/.bash_logout
## nice console login prompt
sed -i 's/getty 38400 tty/getty -f \/etc\/issue.linuxlogo 38400 tty/' /etc/inittab
sed -i 's/-L [0-9]/-L 3/' /etc/linux_logo.conf
invoke-rc.d linuxlogo restart
telinit q

println "Bootstrapping ${XIVO_BRANCH}"
apt-get update >/dev/null
apt-get -y install pf-fai-xivo-1.2-skaro-dev >/dev/null
apt-get update >/dev/null

if pkg_installed mysql-server; then
  println "MySQL is installed, it needs to be upgraded first"
  apt-get -y --no-remove install mysql-server mysql-server-5.0
fi

println "Installing ${XIVO_BRANCH}, pray or slay"
if [ -n "${MIGRATION}" ]; then
  println "Migration from Lenny to Squeeze in the same run"
  println "XiVO Base-Config needs to be upgraded first"
  apt-get -y install pf-xivo-base-config
fi
println "---"
if [ -z "${MIGRATION}" ]; then
  # install DAHDI _before_ install to avoid tools complaining while loading modules
  apt-get -y install dahdi-linux-modules-${KERN_REL}
fi
# the real migration; leaving this touchy chapter to the user...
apt-get dist-upgrade
if [ -z "${MIGRATION}" ]; then
  apt-get -y install pf-xivo
fi
apt-get clean >/dev/null

if [ -n "${MIGRATION}" ]; then
  println "Migrating modules to new kernel version"
  NEW_KERN_REL=$(aptitude --quiet search -F '%p' ~i~nlinux-image-2\\.6\\. | sort | tail -n 1 | sed 's/linux-image-//')
  KMODS_UPD_LIST="dahdi-linux-modules divas4linux-melware-modules misdn-modules sangoma-wanpipe-modules"
  PKG_UPD_LIST=
  for KMOD in ${KMODS_UPD_LIST}; do
    if pkg_installed ${KMOD}-${KERN_REL}; then
      PKG_UPD_LIST="${PKG_UPD_LIST} ${KMOD}-${NEW_KERN_REL}"
    fi
  done
  if [ -n "${PKG_UPD_LIST}" ]; then
    apt-get -y install ${PKG_UPD_LIST}
  fi
fi

println "Cleanup"
rm -rf ${CLEANUP_FILES}

if [ -n "${MIGRATION}" ]; then
  println "Installation finished"
else
  println "Migration finished"
  if [ "${KERN_REL}" != "${NEW_KERN_REL}" ]; then
    println "!!! You should reboot soon to the new kernel !!!"
  fi
fi
println
println "Note: If this is a Proformatique installation with maintenance, please install pf-sys-ssh too."

