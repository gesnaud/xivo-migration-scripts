#!/bin/sh

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

OLD_XIVO_BRANCH="XIVO Tardis"
XIVO_BRANCH="XIVO K-9"

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

if [ -n "${MIGRATION}" ]; then
  # necessary because of tools unloading modules would fail
  invoke-rc.d asterisk stop

  BACKUP_CONF_BASE=/root/xivo-migration
  BACKUP_CONF=${BACKUP_CONF_BASE}/tardis-k-9
  if [ -e "${BACKUP_CONF}" ]; then
    println "A backup of the configuration already exist"
    println " Something must have gone wrong in the previous run :-("
    println " Better luck this time"'!'
  else
    println "Backuping configuration before proceeding"
    mkdir -p ${BACKUP_CONF}
    cp -a /etc /tftpboot ${BACKUP_CONF}/
    cp -a /var/lib/asterisk ${BACKUP_CONF}/var_lib_asterisk
    # the following is fixed in K-9
    cp -a /usr/share/asterisk ${BACKUP_CONF}/usr_share_asterisk
  fi
else
  if ! pkg_installed pf-fai; then
    println "PF bootstrapping missing, installing..."

    cp -a /etc/apt/sources.list /etc/apt/sources.list.inst-bak
    echo "deb http://mirror.xivo.io/debian/ etch main" >>/etc/apt/sources.list
    wget http://mirror.xivo.io/xivo_current.key -O - | apt-key add -

    aptitude update >/dev/null
    aptitude -y install pf-fai >/dev/null

    mv /etc/apt/sources.list.inst-bak /etc/apt/sources.list
  fi
fi

println "Ensure we are starting from an up-to-date system"
aptitude update >/dev/null
aptitude -y dist-upgrade

println "We let you 5 secondes to check if errors occurred, then migration will continue."
sleep 5

# preseed debconf to avoid being asked for configuration of new packages
wget -q -O - http://fai.proformatique.com/d-i/etch/pkg.cfg | debconf-set-selections
wget -q -O - http://fai.proformatique.com/d-i/etch/classes/xivo-k-9/custom.cfg | debconf-set-selections

println "Pushing changes still in FAI (not packaged yet)"
# allow late preseeding via packaging
sed -i -r 's/^DPkg::Pre-Install-Pkgs/\/\/DPkg::Pre-Install-Pkgs/' /etc/apt/apt.conf.d/70debconf
chmod 700 /root
echo "BOOTLOGD_ENABLE=Yes" >/etc/default/bootlogd
aptitude -y purge dhcp-client
aptitude -y install ssh dhcp3-client iproute postfix exim4-base_ exim4-config_ \
                sudo vim bzip2 less iputils-ping host traceroute popularity-contest \
                linuxlogo tasksel_ nvi_ vim-tiny_
update-alternatives --set editor $(which vim.basic)
## no disclosure when logouting
echo "clear" >/root/.bash_logout
## nice console login prompt
sed -i 's/getty 38400 tty/getty -f \/etc\/issue.linuxlogo 38400 tty/' /etc/inittab
sed -i 's/-L [0-9]/-L 3/' /etc/linux_logo.conf
invoke-rc.d linuxlogo restart
telinit q

println "Bootstrapping ${XIVO_BRANCH}"
aptitude update >/dev/null
aptitude -y install pf-fai-xivo-0.4-k-9 >/dev/null

println "Installing ${XIVO_BRANCH}, pray or slay"
println "---"
aptitude update >/dev/null
if [ -n "${MIGRATION}" ]; then
  if pkg_installed zaptel; then
    # unload Zaptel, it is replaced by DAHDI
    invoke-rc.d zaptel unload
  fi
fi
# install DAHDI _before_ install to avoid tools complaining while loading modules
aptitude -y install dahdi-linux-modules-${KERN_REL}
# the real migration; leaving this touchy chapter to the user...
aptitude dist-upgrade
if [ -z "${MIGRATION}" ]; then
  aptitude install pf-xivo
else
  # -- fixes --
  # atftpd config problem until 0.4.2
  dpkg-reconfigure -pcritical atftpd
fi
aptitude clean >/dev/null

# detect if already using Etch'n'Half or ask the user
if echo "${KERN_REL}" | grep -q "etchnhalf"; then
  REPLY="y"
else
  println "Do you wich to switch to Etch'n'Half? (y/n)"
  read REPLY
fi
if [ "${REPLY}" == "y" ]; then
  ETCHNHALF_KVER="2.6.24-etchnhalf.1-${KERN_FLAVOUR}"

  aptitude -y install linux-image-${ETCHNHALF_KVER} dahdi-linux-modules-${ETCHNHALF_KVER}
  OPTIONAL_PKGS="misdn-modules sangoma-wanpipe-modules divas4linux-melware-modules"
  for KMOD in ${OPTIONAL_PKGS}; do
    # install or force-upgrade (if already using Etch'n'Half)
    if pkg_installed ${KMOD}-${KERN_REL} || pkg_installed ${KMOD}-${ETCHNHALF_KVER}; then
      aptitude -y install ${KMOD}-${ETCHNHALF_KVER}
    fi
  done

  println "A reboot is needed to complete your installation !"
  println "(but it is up to you to trigger it when ready)"
fi

println
println "Note: If this is a Proformatique installation with maintenance, please install pf-sys-ssh too."

