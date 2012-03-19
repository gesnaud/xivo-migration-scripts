#!/bin/bash

mirror_xivo="http://mirror.xivo.fr"
error_on_debian_version() {
    echo 'You must install XiVO Skaro on Debian Squeeze system'
    exit
}

check_system() {
    local version_file='/etc/debian_version'
    if [ ! -f $version_file ]; then
        error_on_debian_version
    else
        version=$(cat $version_file | cut -d '.' -f 1-2)
    fi
    if [ $version != '6.0' ]; then
        error_on_debian_version
    fi
}
add_xivo_key() {
    wget $mirror_xivo/xivo_current.key -O - | apt-key add -
}

add_mirror() {
    echo "Add mirrors informations"
    mirror_squeeze="deb $mirror_xivo/debian squeeze main contrib non-free"
    apt_dir="/etc/apt/"
    sources_list_dir="$apt_dir/sources.list.d"
    grep -r "$mirror_squeeze" $apt_dir
    if [ $? -ne 0 ]; then
        echo $mirror_squeeze > $sources_list_dir/tmp-pf.sources.list
    fi
    add_xivo_key
}

install_xivo () {
    wget -q -O - $mirror_xivo/d-i/squeeze/pkg.cfg | debconf-set-selections
    wget -q -O - $mirror_xivo/d-i/squeeze/classes/skaro/custom.cfg | debconf-set-selections
    update='apt-get update'
    install='apt-get install --assume-yes'
    download='apt-get install --assume-yes --download-only'
    $update
    $install $fai $fai_xivo
    if [ -f $sources_list_dir/tmp-pf.sources.list ]; then
        rm $sources_list_dir/tmp-pf.sources.list
    fi
    $update
    kernel_release=$(uname -r)
    $install --purge postfix
    $download dahdi-linux-modules-$kernel_release pf-xivo
    $install dahdi-linux-modules-$kernel_release
    $install pf-xivo

    invoke-rc.d dahdi restart
    /usr/sbin/dahdi_genconf
    # fix rights
    config="/etc/asterisk/dahdi-channels.conf"
    if [ -e "${config}" ]; then
        chown asterisk:www-data ${config}
        chmod 660 ${config}
    fi
    # (restart with new config)
    invoke-rc.d dahdi restart

    # Asterisk proper start
    invoke-rc.d asterisk restart

    if [ $? -eq 0 ]; then
        echo 'You must now finish the installation'
        xivo_ip=$(ip a s eth0 | grep -E 'inet.*eth0' | awk '{print $2}' | cut -d '/' -f 1 )
        echo "open http://$xivo_ip to configure XiVO"
    fi
}

usage() {
    cat << EOF
    This script is used to install XiVO Skaro

    usage : $(basename $0) {-d|-r}
        whitout arg : install production version 
        -r          : install release candidate version
        -d          : install development version

EOF
}

while getopts :dr opt; do
    case ${opt} in
        d)skaro_version='squeeze-xivo-skaro-dev';;
        r)skaro_version='squeeze-xivo-skaro-rc';;
        *) usage;;
    esac
done

skaro_version=${skaro_version:-'squeeze-xivo-skaro'}

if [ $skaro_version = 'squeeze-xivo-skaro' ]; then
    fai='pf-fai'
    fai_xivo='pf-fai-xivo-1.2-skaro'
elif [ $skaro_version = 'squeeze-xivo-skaro-rc' ]; then
    fai='pf-fai'
    fai_xivo='pf-fai-xivo-1.2-skaro-rc'
elif [ $skaro_version = 'squeeze-xivo-skaro-dev' ]; then
    fai='pf-fai-dev'
    fai_xivo='pf-fai-xivo-1.2-skaro-dev'
fi

check_system
add_mirror
install_xivo
