#!/usr/bin/env bash
#
# Description:      Remove extra kernels
# System Required:  CentOS, Debian, Ubuntu
#
# Copyright (C) 2023 zxcvos
# Github: https://github.com/zxcvos/system-automation-scripts/blob/main/remove-kernel.sh

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

function get_char() {
    SAVEDSTTY=`stty -g`
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
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

function remove_extra_kernel() {
    _info "Removing extra kernels..."
    case "$(_os)" in
        centos)
            if ! rpm -qa | grep -E "headers|devel|kernel|modules|core" | grep -v $(uname -r); then
                _info "No additional kernels found to remove"
                exit 0
            fi
            rpm -qa | grep -E "headers|devel|kernel|modules|core" | grep -v $(uname -r) | xargs rpm -e --nodeps
            if _exists "yum"; then
                yum -y autoremove
            elif _exists "dnf"; then
                dnf -y autoremove
            fi
            ;;
        ubuntu|debian)
            if ! dpkg -l | grep -E "linux-(image|modules|headers)" | awk '{print $2}' | grep -v "$(uname -r)"; then
                _info "No additional kernels found to remove"
                exit 0
            fi
            dpkg -l | grep -E "linux-(image|modules|headers)" | awk '{print $2}' | grep -v "$(uname -r)" | xargs apt-get -y purge
            apt-get -y autoreme
            ;;
        *)
            _error "Not supported OS"
            ;;
    esac
    _info "Extra kernels removed..."
}

function remove_kernel() {
    remove_extra_kernel
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
echo " Script to remove extra kernels"
echo
echo " URL: https://github.com/zxcvos/system-automation-scripts/blob/main/remove-kernel.sh"
echo "----------------------------------------"
echo
_warn "Please do not use this script in a production environment."
_warn "To ensure the safety of your data, please back up your data before trying this script."
echo "Press any key to start...or Press Ctrl+C to cancel"
char=$(get_char)

remove_kernel 2>&1 | tee ${cur_dir}/remove_kernel.log
