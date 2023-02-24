#!/usr/bin/env bash
#
# Description:      Update Linux kernel to the latest version
# System Required:  CentOS 6+, Debian8+, Ubuntu16+
#
# Copyright (C) 2023 zxcvos
# Thanks: Teddysun <i@teddysun.com>
# Original: https://teddysun.com/489.html
# Github: https://github.com/zxcvos/system-automation-scripts/blob/main/update-kernel.sh

trap 'rm -rf "${TMPFILE}"' EXIT
TMPFILE=$(mktemp -d -p ${HOME} -t update_kernel.XXXXXXX) || exit 1

cur_dir="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
RED='\033[1;31;31m'
GREEN='\033[1;31;32m'
YELLOW='\033[1;31;33m'
NC='\033[0m'

function _info() {
    printf "${GREEN}[Info] ${NC}"
    printf -- "%s" "$1"
    printf "\n"
}

function _warn() {
    printf "${YELLOW}[Warning] ${NC}"
    printf -- "%s" "$1"
    printf "\n"
}

function _error() {
    printf "${RED}[Error] ${NC}"
    printf -- "%s" "$1"
    printf "\n"
    exit 1
}

function _exists() {
    local cmd="$1"
    if eval type type > /dev/null 2>&1; then
        eval type "$cmd" > /dev/null 2>&1
    elif command > /dev/null 2>&1; then
        command -v "$cmd" > /dev/null 2>&1
    else
        which "$cmd" > /dev/null 2>&1
    fi
    local rt=$?
    return ${rt}
}

function _os() {
    local os=""
    [ -f "/etc/debian_version" ] && source /etc/os-release && os="${ID}" && printf -- "%s" "${os}" && return
    [ -f "/etc/redhat-release" ] && os="centos" && printf -- "%s" "${os}" && return
}

function _os_full() {
    [ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

function _os_ver() {
    local main_ver="$( echo $(_os_full) | grep -oE  "[0-9.]+")"
    printf -- "%s" "${main_ver%%.*}"
}

function _error_detect() {
    local cmd="$1"
    _info "${cmd}"
    eval ${cmd}
    if [ $? -ne 0 ]; then
        _error "Execution command (${cmd}) failed, please check it and try again."
    fi
}

function _is_64bit() {
    if [ $(getconf WORD_BIT) = '32' ] && [ $(getconf LONG_BIT) = '64' ]; then
        return 0
    else
        return 1
    fi
}

function _version_ge() {
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"
}

function dpkg_repacked() {
    DEB_PACKAGE="${1}"
    cp -a ${DEB_PACKAGE} ${TMPFILE}/${DEB_PACKAGE}
    _error_detect "cd ${TMPFILE}"
    _error_detect "ar x ${DEB_PACKAGE}"
    if [[ -s control.tar.zst && -s data.tar.zst ]]; then
        _error_detect "rm -rf ${DEB_PACKAGE}"
        _error_detect "zstd -d < control.tar.zst | xz > control.tar.xz"
        _error_detect "zstd -d < data.tar.zst | xz > data.tar.xz"
        _error_detect "ar -m -c -a sdsd ${DEB_PACKAGE} debian-binary control.tar.xz data.tar.xz"
        _error_detect "rm -rf debian-binary control.tar.xz data.tar.xz control.tar.zst data.tar.zst"
    fi
    _error_detect "cd -"
    mv -f "${TMPFILE}/${DEB_PACKAGE}" ${DEB_PACKAGE}
    rm -rf "${TMPFILE}/*"
}

function get_rpm_latest_version() {
    local os_ver="$(_os_ver)"
    _error_detect "rpm --import https://raw.githubusercontent.com/elrepo/packages/master/elrepo-release/el${os_ver}/RPM-GPG-KEY-elrepo.org"
    case ${os_ver} in
        6)
            rpm_kernel_url="https://dl.lamp.sh/files/"
            rpm_kernel_version="4.18.20"
            if _is_64bit; then
                rpm_kernel_name="kernel-ml-4.18.20-1.el6.elrepo.x86_64.rpm"
                rpm_kernel_devel_name="kernel-ml-devel-4.18.20-1.el6.elrepo.x86_64.rpm"
            else
                rpm_kernel_name="kernel-ml-4.18.20-1.el6.elrepo.i686.rpm"
                rpm_kernel_devel_name="kernel-ml-devel-4.18.20-1.el6.elrepo.i686.rpm"
            fi
            ;;
        7|8|9)
            rpm_kernel_url="https://dl.lamp.sh/kernel/el${os_ver}/"
            if _is_64bit; then
                rpm_list=$(wget -qO- ${rpm_kernel_url})
                rpm_kernel_version=$(echo ${rpm_list} | grep -Eoi "kernel-ml-[5-9]+\.[0-9]+\.[0-9]+-1\.el${os_ver}\.(elrepo\.)?x86_64.rpm" | cut -d- -f3 | grep -v - | sort -V | tail -n 1)
                rpm_kernel_name=$(echo ${rpm_list} | grep -Eoi "kernel-ml-[5-9]+\.[0-9]+\.[0-9]+-1\.el${os_ver}\.(elrepo\.)?x86_64.rpm" | sort -V | uniq | tail -n 1)
                rpm_kernel_devel_name=$(echo ${rpm_list} | grep -Eoi "kernel-ml-devel-[5-9]+\.[0-9]+\.[0-9]+-1\.el${os_ver}\.(elrepo\.)?x86_64.rpm" | sort -V | uniq | tail -n 1)
                if [[ ${os_ver} -eq 8 || ${os_ver} -eq 9 ]]; then
                    rpm_kernel_core_name=$(echo ${rpm_list} | grep -Eoi "kernel-ml-core-[5-9]+\.[0-9]+\.[0-9]+-1\.el${os_ver}\.(elrepo\.)?x86_64.rpm" | sort -V | uniq | tail -n 1)
                    rpm_kernel_modules_name=$(echo ${rpm_list} | grep -Eoi "kernel-ml-modules-[5-9]+\.[0-9]+\.[0-9]+-1\.el${os_ver}\.(elrepo\.)?x86_64.rpm" | sort -V | uniq | tail -n 1)
                fi
            else
                _error "Not supported architecture, please change to 64-bit architecture."
            fi
            ;;
        *)
            ;; # do nothing
    esac
}

function get_deb_latest_version() {
    deb_kernel_version=$(wget -qO- https://kernel.ubuntu.com/~kernel-ppa/mainline/ | awk -F'\"v' '/v[4-9]./{print $2}' | cut -d/ -f1 | grep -v - | sort -V | tail -n 1)
    [[ -z ${deb_kernel_version} ]] && _error "Get latest kernel version failed."
    if _is_64bit; then
        deb_name=$(wget -qO- https://kernel.ubuntu.com/~kernel-ppa/mainline/v${deb_kernel_version}/ | grep "linux-image" | grep "generic" | awk -F'\">' '/amd64.deb/{print $2}' | cut -d'<' -f1 | head -1)
        deb_kernel_url="https://kernel.ubuntu.com/~kernel-ppa/mainline/v${deb_kernel_version}/${deb_name}"
        deb_kernel_name="linux-image-${deb_kernel_version}-amd64.deb"
        modules_deb_name=$(wget -qO- https://kernel.ubuntu.com/~kernel-ppa/mainline/v${deb_kernel_version}/ | grep "linux-modules" | grep "generic" | awk -F'\">' '/amd64.deb/{print $2}' | cut -d'<' -f1 | head -1)
        deb_kernel_modules_url="https://kernel.ubuntu.com/~kernel-ppa/mainline/v${deb_kernel_version}/${modules_deb_name}"
        deb_kernel_modules_name="linux-modules-${deb_kernel_version}-amd64.deb"
    else
        deb_name=$(wget -qO- https://kernel.ubuntu.com/~kernel-ppa/mainline/v${deb_kernel_version}/ | grep "linux-image" | grep "generic" | awk -F'\">' '/i386.deb/{print $2}' | cut -d'<' -f1 | head -1)
        deb_kernel_url="https://kernel.ubuntu.com/~kernel-ppa/mainline/v${deb_kernel_version}/${deb_name}"
        deb_kernel_name="linux-image-${deb_kernel_version}-i386.deb"
        modules_deb_name=$(wget -qO- https://kernel.ubuntu.com/~kernel-ppa/mainline/v${deb_kernel_version}/ | grep "linux-modules" | grep "generic" | awk -F'\">' '/i386.deb/{print $2}' | cut -d'<' -f1 | head -1)
        deb_kernel_modules_url="https://kernel.ubuntu.com/~kernel-ppa/mainline/v${deb_kernel_version}/${modules_deb_name}"
        deb_kernel_modules_name="linux-modules-${deb_kernel_version}-i386.deb"
    fi
    [ -z "${deb_name}" ] && _error "Getting Linux kernel binary package name failed, maybe kernel build failed. Please choose other one and try again."
}

function get_char() {
    SAVEDSTTY=`stty -g`
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}

function check_kernel_version() {
    local kernel_version=$(uname -r | cut -d- -f1)
    local latest_kernel_version
    case "$(_os)" in
        centos)
            get_rpm_latest_version
            latest_kernel_version="${rpm_kernel_version}"
            ;;
        ubuntu|debian)
            get_deb_latest_version
            latest_kernel_version="${deb_kernel_version}"
            ;;
    esac
    if _version_ge ${kernel_version} ${latest_kernel_version}; then
        return 0
    else
        return 1
    fi
}

# Check OS version
function check_os() {
    if _exists "virt-what"; then
        virt="$(virt-what)"
    elif _exists "systemd-detect-virt"; then
        virt="$(systemd-detect-virt)"
    fi
    if [ -n "${virt}" -a "${virt}" = "lxc" ]; then
        _error "Virtualization method is LXC, which is not supported."
    fi
    if [ -n "${virt}" -a "${virt}" = "openvz" ] || [ -d "/proc/vz" ]; then
        _error "Virtualization method is OpenVZ, which is not supported."
    fi
    [ -z "$(_os)" ] && _error "Not supported OS"
    case "$(_os)" in
        ubuntu)
            [ -n "$(_os_ver)" -a "$(_os_ver)" -lt 16 ] && _error "Not supported OS, please change to Ubuntu 16+ and try again."
            ;;
        debian)
            [ -n "$(_os_ver)" -a "$(_os_ver)" -lt 8 ] &&  _error "Not supported OS, please change to Debian 8+ and try again."
            ;;
        centos)
            [ -n "$(_os_ver)" -a "$(_os_ver)" -lt 6 ] &&  _error "Not supported OS, please change to CentOS 6+ and try again."
            ;;
        *)
            _error "Not supported OS"
            ;;
    esac
}

function sysctl_config() {
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
}

function install_kernel() {
    _info "Getting latest kernel version..."
    case "$(_os)" in
        centos)
            if [ -n "$(_os_ver)" ]; then
                if ! _exists "perl"; then
                    _error_detect "yum install -y perl"
                fi
                if [ "$(_os_ver)" -eq 6 ]; then
                    _error_detect "wget -c -t3 -T60 -O ${rpm_kernel_name} ${rpm_kernel_url}${rpm_kernel_name}"
                    _error_detect "wget -c -t3 -T60 -O ${rpm_kernel_devel_name} ${rpm_kernel_url}${rpm_kernel_devel_name}"
                    [ -s "${rpm_kernel_name}" ] && _error_detect "rpm -ivh ${rpm_kernel_name}" || _error "Download ${rpm_kernel_name} failed, please check it."
                    [ -s "${rpm_kernel_devel_name}" ] && _error_detect "rpm -ivh ${rpm_kernel_devel_name}" || _error "Download ${rpm_kernel_devel_name} failed, please check it."
                    rm -f ${rpm_kernel_name} ${rpm_kernel_devel_name}
                    [ ! -f "/boot/grub/grub.conf" ] && _error "/boot/grub/grub.conf not found, please check it."
                    sed -i 's/^default=.*/default=0/g' /boot/grub/grub.conf
                elif [[ "$(_os_ver)" -eq 7 || "$(_os_ver)" -eq 8 || "$(_os_ver)" -eq 9  ]]; then
                    if [[ "$(_os_ver)" -eq 8 || "$(_os_ver)" -eq 9 ]]; then
                        _error_detect "wget -c -t3 -T60 -O ${rpm_kernel_core_name} ${rpm_kernel_url}${rpm_kernel_core_name}"
                        _error_detect "wget -c -t3 -T60 -O ${rpm_kernel_modules_name} ${rpm_kernel_url}${rpm_kernel_modules_name}"
                        [ -s "${rpm_kernel_core_name}" ] || _error "Download ${rpm_kernel_core_name} failed, please check it."
                        [ -s "${rpm_kernel_modules_name}" ] || _error "Download ${rpm_kernel_modules_name} failed, please check it."
                    fi
                    _error_detect "wget -c -t3 -T60 -O ${rpm_kernel_name} ${rpm_kernel_url}${rpm_kernel_name}"
                    _error_detect "wget -c -t3 -T60 -O ${rpm_kernel_devel_name} ${rpm_kernel_url}${rpm_kernel_devel_name}"
                    [ -s "${rpm_kernel_core_name}" ] && _error_detect "rpm -ivh ${rpm_kernel_core_name}"
                    [ -s "${rpm_kernel_modules_name}" ] && _error_detect "rpm -ivh ${rpm_kernel_modules_name}"
                    [ -s "${rpm_kernel_name}" ] && _error_detect "rpm -ivh ${rpm_kernel_name}" || _error "Download ${rpm_kernel_name} failed, please check it."
                    [ -s "${rpm_kernel_devel_name}" ] && _error_detect "rpm -ivh ${rpm_kernel_devel_name}" || _error "Download ${rpm_kernel_devel_name} failed, please check it."
                    [ -s "${rpm_kernel_core_name}" ] && rm -f ${rpm_kernel_core_name}
                    [ -s "${rpm_kernel_modules_name}" ] && rm -f ${rpm_kernel_modules_name}
                    rm -f ${rpm_kernel_name} ${rpm_kernel_devel_name}
                    grubby --set-default $(grubby --info=ALL | grep -E ^kernel.*${rpm_kernel_version} | cut -d= -f2)
                fi
            fi
            ;;
        ubuntu|debian)
            if [ -n "${modules_deb_name}" ]; then
                _error_detect "wget -c -t3 -T60 -O ${deb_kernel_modules_name} ${deb_kernel_modules_url}"
            fi
            _error_detect "wget -c -t3 -T60 -O ${deb_kernel_name} ${deb_kernel_url}"
            if [[ "debian" = "$(_os)" ]]; then
                _error_detect "apt-get install -y zstd"
                dpkg_repacked ${deb_kernel_modules_name}
                dpkg_repacked ${deb_kernel_name}
            fi
            _error_detect "dpkg -i ${deb_kernel_modules_name} ${deb_kernel_name}"
            rm -f ${deb_kernel_modules_name} ${deb_kernel_name}
            _error_detect "/usr/sbin/update-grub"
            ;;
        *)
            ;; # do nothing
    esac
}

function reboot_os() {
    echo
    _info "The system needs to reboot."
    read -r -p  "Do you want to restart system? [y/N]" is_reboot
    if [[ ${is_reboot}  =~ ^[Yy]$ ]]; then
        reboot
    else
        _info "Reboot has been canceled..."
        exit 0
    fi
}

function update_kernel() {
    if check_kernel_version; then
        echo
        _info "The kernel version is the latest version..."
        exit 0
    fi
    check_os
    install_kernel
    sysctl_config
    reboot_os
}

[[ $EUID -ne 0 ]] && _error "This script must be run as root"
opsy=$( _os_full )
arch=$( uname -m )
lbit=$( getconf LONG_BIT )
kern=$( uname -r )

clear
echo "---------- System Information ----------"
echo " OS      : $opsy"
echo " Arch    : $arch ($lbit Bit)"
echo " Kernel  : $kern"
echo "----------------------------------------"
echo " Update Linux kernel to the latest version script"
echo
echo " URL: https://github.com/zxcvos/system-automation-scripts/blob/main/update-kernel.sh"
echo "----------------------------------------"
echo
echo "Press any key to start...or Press Ctrl+C to cancel"
char=$(get_char)

update_kernel 2>&1 | tee ${cur_dir}/update_kernel.log
