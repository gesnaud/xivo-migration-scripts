#!/bin/bash

mirror_xivo="http://mirror.xivo.fr"
error_on_debian_version() {
    echo 'You must install XiVO on a Debian "wheezy" system'
    exit
}

check_system() {
    local version_file='/etc/debian_version'
    if [ ! -f $version_file ]; then
        error_on_debian_version
    else
        version=$(cut -d '.' -f 1 "$version_file")
    fi
    if [ $version != '7' ]; then
        error_on_debian_version
    fi
}

add_xivo_key() {
    wget $mirror_xivo/xivo_current.key -O - | apt-key add -
}

add_mirror() {
    echo "Add mirrors informations"
    local mirror="deb $mirror_xivo/debian $distribution main"
    apt_dir="/etc/apt/"
    sources_list_dir="$apt_dir/sources.list.d"
    if ! grep -qr "$mirror" "$apt_dir"; then
        echo "$mirror" > $sources_list_dir/tmp-pf.sources.list
    fi
    add_xivo_key
}

install_xivo () {
    wget -q -O - $mirror_xivo/d-i/wheezy/pkg.cfg | debconf-set-selections
    wget -q -O - $mirror_xivo/d-i/wheezy/classes/wheezy-xivo-skaro-dev/custom.cfg | debconf-set-selections
    echo startup=no > /etc/default/xivo
    update='apt-get update'
    install='apt-get install --assume-yes'
    download='apt-get install --assume-yes --download-only'
    $update
    $install $fai_package
    if [ -f $sources_list_dir/tmp-pf.sources.list ]; then
        rm $sources_list_dir/tmp-pf.sources.list
    fi
    $update
    kernel_release=$(uname -r)
    $install --purge postfix
    $download dahdi-linux-modules-$kernel_release xivo
    $install dahdi-linux-modules-$kernel_release
    $install xivo

    invoke-rc.d dahdi restart
    /usr/sbin/dahdi_genconf
    xivo-service restart all

    if [ $? -eq 0 ]; then
        echo 'You must now finish the installation'
        xivo_ip=$(ip a s eth0 | grep -E 'inet.*eth0' | awk '{print $2}' | cut -d '/' -f 1 )
        echo "open http://$xivo_ip to configure XiVO"
    fi
}

usage() {
    cat << EOF
    This script is used to install XiVO

    usage : $(basename $0) {-d|-r}
        whitout arg : install production version 
        -r          : install release candidate version
        -d          : install development version

EOF
}

while getopts :dr opt; do
    case ${opt} in
        d)xivo_version='dev';;
        r)xivo_version='rc';;
        *) usage;;
    esac
done

xivo_version=${xivo_version:-'prod'}

if [ "$xivo_version" = 'prod' ]; then
    echo "installation $xivo_version not supported presently" >&2
    exit 1
    fai_package='xivo-fai'
    distribution='xivo-five'
elif [ "$xivo_version" = 'rc' ]; then
    echo "installation $xivo_version not supported presently" >&2
    exit 1
    fai_package='xivo-fai-rc'
    distribution='xivo-rc'
elif [ "$xivo_version" = 'dev' ]; then
    fai_package='xivo-fai-dev'
    distribution='xivo-dev'
fi

check_system
add_mirror
install_xivo
