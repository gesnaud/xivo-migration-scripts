#!/bin/bash

mirror_xivo="http://mirror.xivo.io"
update='apt-get update'
install='apt-get install --assume-yes'
download='apt-get install --assume-yes --download-only'
repo='debian'
debian_name='jessie'

error_on_debian_version() {
    echo 'You must install XiVO on a Debian version' $debian_version'.X'
    echo 'Your actual version is version' $version
    exit 1
}

check_system() {
    xivo_target_version=${distribution:5}
    local version_file='/etc/debian_version'
    if [ ! -f $version_file ]; then
        error_on_debian_version
    else
        version=$(cut -d '.' -f 1 "$version_file")
    fi

    if [[ $xivo_target_version == 'dev' || $xivo_target_version == 'rc' || $xivo_target_version == 'five' ]]; then
        debian_version='8'
    else
        if [[ "$xivo_target_version" > "15.19" ]]; then
            debian_version='8'
        else
            debian_version='7'
            debian_name='wheezy'
        fi
    fi

    if [ $version != $debian_version ]; then
        error_on_debian_version
    fi
}



add_xivo_key() {
    wget $mirror_xivo/xivo_current.key -O - | apt-key add -
}

add_mirror() {
    echo "Add mirrors informations"
    local mirror="deb $mirror_xivo/$repo $distribution main"
    apt_dir="/etc/apt"
    sources_list_dir="$apt_dir/sources.list.d"
    if ! grep -qr "$mirror" "$apt_dir"; then
        echo "$mirror" > $sources_list_dir/tmp-pf.sources.list
    fi
    add_xivo_key

    export DEBIAN_FRONTEND=noninteractive
    $update
    $install xivo-dist
    xivo-dist "$distribution"

    rm -f "$sources_list_dir/tmp-pf.sources.list"
    $update
}

install_xivo () {
    wget -q -O - $mirror_xivo/d-i/$debian_name/pkg.cfg | debconf-set-selections

    kernel_release=$(uname -r)
    $install --purge postfix
    $download dahdi-linux-modules-$kernel_release xivo
    $install dahdi-linux-modules-$kernel_release
    $install xivo

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

    usage : $(basename $0) {-d|-r|-a}
        whitout arg : install production version
        -r          : install release candidate version
        -d          : install development version
        -a          : install archived version (XX.XX)

EOF
}

while getopts :dra opt; do
    case ${opt} in
        d)distribution='xivo-dev';;
        r)distribution='xivo-rc';;
        a)distribution='xivo-'$2; repo='archive';;
        *)usage;;
    esac
done

distribution=${distribution:-'xivo-five'}
check_system
add_mirror
install_xivo
