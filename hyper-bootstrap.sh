#!/bin/bash
# Description:  This script is used to install hyperctl and hyperd
# Usage:
#  install from remote
#    wget -qO- https://hypercontainer.io/install | bash
#    curl -sSL https://hypercontainer.io/install | bash
# install from local
#    ./hyper-bootstrap.sh
BASE_DIR=$(cd "$(dirname "$0")"; pwd); cd ${BASE_DIR}
SLEEP_SEC=10
set -e
########## Variable ##########
CURRENT_USER="$(id -un 2>/dev/null || true)"
BOOTSTRAP_DIR="/tmp/hyper-bootstrap-${CURRENT_USER}"
BASH_C="bash -c"
########## Parameter ##########
S3_URL="http://hypercontainer-install.s3.amazonaws.com"
PKG_FILE="hyper-latest.tgz"
UNTAR_DIR="hyper-pkg"
SUPPORT_EMAIL="support@hyper.sh"
############ RPM ##############
CENTOS7_QEMU_HYPER="qemu-hyper-2.4.1-3.el7.centos.x86_64"
CENTOS7_HYPERSTART="hyperstart-0.8.0-1.el7.centos.x86_64"
CENTOS7_HYPER="hyper-container-0.8.0-1.el7.centos.x86_64"
FC23_HYPERSTART="hyperstart-0.8.0-1.fc25.x86_64"
FC23_HYPER="hyper-container-0.8.0-1.fc25.x86_64"
############ DEB ##############
DEBIAN_HYPER="hypercontainer_0.8.0-1_amd64"
DEBIAN_HYPERSTART="hyperstart_0.8.0-1_amd64"
########## Constant ##########
SUPPORT_DISTRO=(debian ubuntu fedora centos linuxmint)
LINUX_MINT_CODE=(rafaela rebecca qiana)
UBUNTU_CODE=(trusty utopic vivid wily xenial)
DEBIAN_CODE=(jessie wheezy)
CENTOS_VER=(6 7)
FEDORA_VER=(20 21 22 23 24 25)
#Color Constant
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
WHITE=`tput setaf 7`
LIGHT=`tput bold `
RESET=`tput sgr0`
#Error Message
ERR_ROOT_PRIVILEGE_REQUIRED=(10 "This install script need root privilege, please retry use 'sudo' or root user!")
ERR_NOT_SUPPORT_PLATFORM=(20 "Sorry, Hyper only support x86_64 platform!")
ERR_NOT_SUPPORT_DISTRO=(21 "Sorry, Hyper only support ubuntu/debian/fedora/centos/linuxmint(17.x) now!")
ERR_NOT_SUPPORT_DISTRO_VERSION=(22)
ERR_NO_HYPERVISOR=(39 "You should have either Xen 4.5+ or Qemu 2.0+ installed to run hyper")
ERR_QEMU_NOT_INSTALL=(40 "Please install Qemu 2.0+ first!")
ERR_QEMU_LOW_VERSION=(41 "Need Qemu version 2.0 at least!")
ERR_XEN_NOT_INSTALL=(50 "Please install xen 4.5+ first!")
ERR_XEN_GET_VER_FAILED=(51 "Can not get xen version, xen daemon isn't running!")
ERR_XEN_VER_LOW=(52 "Sorry, hyper only support xen 4.5+")
ERR_LIBVIRT_NOT_INSTALL=(53 "hypercontainer depends on libvirt0, please install libvirt0 first!")
ERR_FETCH_INST_PKG_FAILED=(60 "Fetch install package failed, please retry!")
ERR_INST_PKG_MD5_ERROR=(61 "Checksum of install package error, please retry!")
ERR_UNTAR_PKG_FAILED=(62 "Untar install package failed!")
ERR_EXEC_INSTALL_FAILED=(70 "Install hyper failed!")
ERR_INSTALL_SERVICE_FAILED=(71 "Install hyperd as service failed!")
ERR_HYPER_NOT_FOUND=(72 "Can not find hyper and hyperd after setup!")
ERR_HYPER_NO_NEW_VERSION=(80 "You are using the newest hyper\n")
ERR_UNKNOWN_MSG_TYPE=98
ERR_UNKNOWN=99
########## Function Definition ##########
main() {
  show_message info "Welcome to Install HyperContainer...\n"
  check_user
  check_os_platform
  check_os_distro
  if [[ "${LSB_DISTRO}" == "centos" ]] && [[ "${CMAJOR}" == "7" ]];then
    install_from_rpm "centos7"
  elif [[ "${LSB_DISTRO}" == "fedora" ]] && [[ "${CMAJOR}" == "23" ]];then
    install_from_rpm "fedora23"
  elif [[ "${LSB_DISTRO}" == "fedora" ]] && [[ "${CMAJOR}" == "24" ]];then
    install_from_rpm "fedora24"
  elif [[ "${LSB_DISTRO}" == "fedora" ]] && [[ "${CMAJOR}" == "25" ]];then
    install_from_rpm "fedora25"
  elif [[ "${LSB_DISTRO}" == "ubuntu" ]];then
    check_deps
    install_from_deb "ubuntu"
  elif [[ "${LSB_DISTRO}" == "debian" ]];then
    check_deps
    install_from_deb "debian"
  else
    check_deps
    check_hyper_before_install
    if [[ -f install.sh ]] && [[ -d bin ]] && [[ -d boot ]] && [[ -d service ]];then
      show_message debug "Install from local ${BASE_DIR}/"
      BOOTSTRAP_DIR="${BASE_DIR}"
    else
      show_message debug "Install from remote"
      fetch_hyper_package
    fi
    stop_running_hyperd
    install_hyper
  fi
  start_hyperd_service
  exit 0
}
check_hyper_before_install() {
  if (command_exist hyperctl hyperd);then
    echo "${WHITE}"
    cat <<COMMENT
Prompt: "hyper-container" appears to already installed, hyperd serive will be restart during install.
You may press Ctrl+C to abort this process.
COMMENT
    echo -e -n "+ sleep ${SLEEP_SEC} seconds${RESET}"
    n=${SLEEP_SEC}
    until [ ${n} -le 0 ]; do
      echo -n "." && n=$((n-1)) && sleep 1
    done
    echo
  fi
}
check_user() {
  if [[ "${CURRENT_USER}" != "root" ]];then
    if (command_exist sudo);then
      BASH_C="sudo -E bash -c"
    else
      show_message error "${ERR_ROOT_PRIVILEGE_REQUIRED[1]}" && exit ${ERR_ROOT_PRIVILEGE_REQUIRED[0]}
    fi
    show_message info "${WHITE}Hint: Hyper installer need root privilege\n"
    ${BASH_C} "echo -n"
  fi
}
check_deps() {
  show_message info "Check dependency "
  check_deps_qemu || check_deps_xen || exit ${ERR_NO_HYPERVISOR[0]}
  check_deps_initsystem
  show_message done " Done"
}
check_os_platform() {
  ARCH="$(uname -m)"
  if [[ "${ARCH}" != "x86_64" ]];then
    show_message error "${ERR_NOT_SUPPORT_PLATFORM[1]}" && exit ${ERR_NOT_SUPPORT_PLATFORM[0]}
  fi
}
check_os_distro() {
  LSB_DISTRO=""; LSB_VER=""; LSB_CODE=""
  if (command_exist lsb_release);then
    LSB_DISTRO="$(lsb_release -si)"
    LSB_VER="$(lsb_release -sr)"
    LSB_CODE="$(lsb_release -sc)"
  fi
  if [[ -z "${LSB_DISTRO}" ]];then
    if [[ -r /etc/lsb-release ]];then
      LSB_DISTRO="$(. /etc/lsb-release && echo "${DISTRIB_ID}")"
      LSB_VER="$(. /etc/lsb-release && echo "${DISTRIB_RELEASE}")"
      LSB_CODE="$(. /etc/lsb-release && echo "${DISTRIB_CODENAME}")"
    elif [[ -r /etc/os-release ]];then
      LSB_DISTRO="$(. /etc/os-release && echo "$ID")"
      LSB_VER="$(. /etc/os-release && echo "$VERSION_ID")"
    elif [[ -r /etc/fedora-release ]];then
      LSB_DISTRO="fedora"
    elif [[ -r /etc/debian_version ]];then
      LSB_DISTRO="Debian"
      LSB_VER="$(cat /etc/debian_version)"
    elif [[ -r /etc/centos-release ]];then
      LSB_DISTRO="CentOS"
      LSB_VER="$(cat /etc/centos-release | cut -d' ' -f3)"
    fi
  fi
  LSB_DISTRO=$(echo "${LSB_DISTRO}" | tr '[:upper:]' '[:lower:]')
  if [[ "${LSB_DISTRO}" == "debian" ]];then
    case ${LSB_VER} in
      8) LSB_CODE="jessie";;
      7) LSB_CODE="wheezy";;
    esac
  fi
  case "${LSB_DISTRO}" in
    linuxmint)
      if [[ "${LSB_DISTRO}" == "linuxmint" ]]
      then SUPPORT_CODE_LIST="${LINUX_MINT_CODE[@]}";
      fi
      if (echo "${SUPPORT_CODE_LIST}" | grep -vqw "${LSB_CODE}");then
        show_message error "Hyper support ${LSB_DISTRO}( ${SUPPORT_CODE_LIST} ), but current is ${LSB_CODE}(${LSB_VER})"
        exit ${ERR_NOT_SUPPORT_DISTRO_VERSION[0]}
      fi
    ;;
    ubuntu|debian)
      if [[ "${LSB_DISTRO}" == "ubuntu" ]]
      then SUPPORT_CODE_LIST="${UBUNTU_CODE[@]}";
      else SUPPORT_CODE_LIST="${DEBIAN_CODE[@]}";
      fi
      if (echo "${SUPPORT_CODE_LIST}" | grep -vqw "${LSB_CODE}");then
        show_message error "Hyper support ${LSB_DISTRO}( ${SUPPORT_CODE_LIST} ), but current is ${LSB_CODE}(${LSB_VER})"
        exit ${ERR_NOT_SUPPORT_DISTRO_VERSION[0]}
      fi
    ;;
    centos|fedora)
      CMAJOR=$( echo ${LSB_VER} | cut -d"." -f1 )
      if [[  "${LSB_DISTRO}" == "centos" ]]
      then SUPPORT_VER_LIST="${CENTOS_VER[@]}";
      else SUPPORT_VER_LIST="${FEDORA_VER[@]}";
      fi
      if (echo "${SUPPORT_VER_LIST}" | grep -qvw "${CMAJOR}");then
        show_message error "Hyper support ${LSB_DISTRO}( ${SUPPORT_VER_LIST} ), but current is ${LSB_VER}"
        exit ${ERR_NOT_SUPPORT_DISTRO_VERSION[0]}
      fi
    ;;
    *) if [[ ! -z ${LSB_DISTRO} ]];then echo -e -n "\nCurrent OS is '${LSB_DISTRO} ${LSB_VER}(${LSB_CODE})'";
       else echo -e -n "\nCan not detect OS type"; fi
      show_message error "${ERR_NOT_SUPPORT_DISTRO[1]}"
      exit ${ERR_NOT_SUPPORT_DISTRO[0]}
    ;;
  esac
}
check_deps_xen() {
  set +e
  ${BASH_C} "which xl" >/dev/null 2>&1
  if [[ $? -ne 0 ]];then
    show_message info "${ERR_XEN_NOT_INSTALL[1]}"
    return ${ERR_XEN_NOT_INSTALL[0]}
  else
    ${BASH_C} "xl info" >/dev/null 2>&1
    if [[ $? -eq 0 ]];then
      XEN_MAJOR=$( ${BASH_C} "xl info" | grep xen_major | awk '{print $3}' )
      XEN_MINOR=$( ${BASH_C} "xl info" | grep xen_minor | awk '{print $3}' )
      XEN_VERSION=$( ${BASH_C} "xl info" | grep xen_version | awk '{print $3}' )
      show_message debug "xen(${XEN_VERSION}) found"
      if [[ $XEN_MAJOR -ge 4 ]] && [[ $XEN_MINOR -ge 5 ]];then
        PKG_FILE="hyper-latest.tgz"
        UNTAR_DIR="hyper-pkg"
      else
        show_message info "${ERR_XEN_VER_LOW[1]}"
        return ${ERR_XEN_VER_LOW[0]}
      fi
    else
        show_message info "${ERR_XEN_GET_VER_FAILED[1]}"
        return ${ERR_XEN_GET_VER_FAILED[0]}
    fi
  fi
  set -e
  return 0
}
check_deps_qemu() { #QEMU 2.0+ should be installed
  if (command_exist qemu-system-x86_64);then
    local QEMU_VER=$(qemu-system-x86_64 --version | awk '{print $4}' | cut -d"," -f1)
    read QMAJOR QMINOR QFIX < <( echo ${QEMU_VER} | awk -F'.' '{print $1,$2,$3 }')
    if [[ ${QMAJOR} -lt 2 ]] ;then
      show_message info "${ERR_QEMU_LOW_VERSION[1]}\n" && return ${ERR_QEMU_LOW_VERSION[0]}
    fi
  else
    show_message info "${ERR_QEMU_NOT_INSTALL[1]}\n" && return ${ERR_QEMU_NOT_INSTALL[0]}
  fi
  echo -n "."
  return 0
}
check_deps_initsystem() {
  if [[ "${LSB_DISTRO}" == "ubuntu" ]] && [[ "${LSB_CODE}" == "utopic" ]];then
    INIT_SYSTEM="sysvinit"
  elif (command_exist systemctl);then
    INIT_SYSTEM="systemd"
  else
    INIT_SYSTEM="sysvinit"
  fi
  echo -n "."
}
fetch_hyper_package() {
  show_message info "Fetch checksum and package...\n"
  set +e
  ${BASH_C} "ping -c 3 -W 2 hypercontainer-install.s3.amazonaws.com >/dev/null 2>&1"
  if [[ $? -ne 0 ]];then
    S3_URL="http://mirror-hypercontainer-install.s3.amazonaws.com"
  else
    S3_URL="http://hypercontainer-install.s3.amazonaws.com"
  fi
  local SRC_URL="${S3_URL}/${PKG_FILE}"
  local TGT_FILE="${BOOTSTRAP_DIR}/${PKG_FILE}"
  local USE_WGET=$( echo $(get_curl) | awk -F"|" '{print $1}' )
  local CURL_C=$( echo $(get_curl) | awk -F"|" '{print $2}' )
  show_message debug "${SRC_URL} => ${TGT_FILE}"
  mkdir -p ${BOOTSTRAP_DIR} && cd ${BOOTSTRAP_DIR}
  if [[ -s ${TGT_FILE} ]];then
    if [[ "${USE_WGET}" == "true" ]];then
      ${CURL_C} ${SRC_URL}.md5 2>&1 | grep --line-buffered "%" | sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    else
      ${CURL_C} ${TGT_FILE}.md5 ${SRC_URL}.md5
    fi
    if [[ -s "${TGT_FILE}.md5" ]];then
        NEW_MD5=$( cat ${TGT_FILE}.md5 | awk '{print $1}' )
        OLD_MD5=$( md5sum ${TGT_FILE} | awk '{print $1}' )
        if [[ ! -z ${OLD_MD5} ]] && [[ ! -z ${NEW_MD5} ]] && [[ "${OLD_MD5}" != "${NEW_MD5}" ]];then
          show_message info "${LIGHT}Found new hyper version, will download it now!\n"
          ${BASH_C} "\rm  -rf ${BOOTSTRAP_DIR}/*"
        elif [[ ! -z ${OLD_MD5} ]] && [[ "${OLD_MD5}" == "${NEW_MD5}" ]];then #no update
          ${BASH_C} "\rm  -rf ${BOOTSTRAP_DIR}/${UNTAR_DIR}"
        else
          ${BASH_C} "\rm -rf ${BOOTSTRAP_DIR}/*"
        fi
    fi
  elif [[ -f ${TGT_FILE} ]];then
    ${BASH_C} "\rm -rf ${BOOTSTRAP_DIR}/*"
  fi
  if [[ ! -f ${TGT_FILE} ]];then
    \rm -rf ${TGT_FILE}.md5 >/dev/null 2>&1
    if [[ "${USE_WGET}" == "true" ]];then
      ${CURL_C} ${SRC_URL}.md5 2>&1 | grep --line-buffered "%" | sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
      ${CURL_C} ${SRC_URL} 2>&1 | grep --line-buffered "%" | sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    else
      ${CURL_C} ${TGT_FILE}.md5 ${SRC_URL}.md5
      ${CURL_C} ${TGT_FILE} ${SRC_URL}
    fi
    if [[ $? -ne 0 ]];then
      show_message error "${ERR_FETCH_INST_PKG_FAILED[1]}" && exit "${ERR_FETCH_INST_PKG_FAILED[0]}"
    else
      MD5_REMOTE=$(cat ${TGT_FILE}.md5 | awk '{print $1}'); MD5_LOCAL=$(md5sum ${TGT_FILE} | awk '{print $1}')
      if [[ ${MD5_REMOTE} != ${MD5_LOCAL} ]];then
        echo "required checksum: ${MD5_REMOTE}, but downloaded package is ${MD5_LOCAL}"
        show_message error "${ERR_INST_PKG_MD5_ERROR[1]}" && exit "${ERR_INST_PKG_MD5_ERROR[0]}"
      fi
    fi
  fi
  ${BASH_C} "cd ${BOOTSTRAP_DIR} && tar xzf ${PKG_FILE}"
  if [[ $? -ne 0 ]];then
    show_message error "${ERR_UNTAR_PKG_FAILED[1]}" && exit "${ERR_UNTAR_PKG_FAILED[0]}"
  fi
  BOOTSTRAP_DIR="${BOOTSTRAP_DIR}/${UNTAR_DIR}"
  show_message done " Done"
  set -e
}
install_hyper() {
  show_message info "Installing "
  set +e
  cd ${BOOTSTRAP_DIR}
  ${BASH_C} "./install.sh" 1>/dev/null
  if [[ $? -ne 0 ]];then
    show_message error "${ERR_EXEC_INSTALL_FAILED[1]}" && exit "${ERR_EXEC_INSTALL_FAILED[0]}"
  fi
  echo -n "."
  if [[ -f /usr/local/bin/hyperctl ]] && [[ -f /usr/local/bin/hyperd ]] && [[ ! -f /usr/bin/hyperctl ]] && [[ ! -f /usr/bin/hyperd ]] ;then
    ${BASH_C} "ln -s /usr/local/bin/hyperctl /usr/bin/hyperctl"
    ${BASH_C} "ln -s /usr/local/bin/hyperd /usr/bin/hyperd"
  fi
  if (command_exist hyperctl hyperd);then
    install_hyperd_service
    echo -n "."
  else
    show_message error "${ERR_HYPER_NOT_FOUND[1]}"
    display_support ${ERR_HYPER_NOT_FOUND[0]}
    exit ${ERR_HYPER_NOT_FOUND[0]}
  fi
  set -e
  show_message done " Done"
}
install_hyperd_service() {
  local SRC_INIT_FILE=""
  local TGT_INIT_FILE=""
  if [[ "${INIT_SYSTEM}" == "sysvinit" ]];then
    if [[ "${LSB_DISTRO}" == "debian" ]] && [[ "${LSB_CODE}" == "wheezy" ]] ; then
      SRC_INIT_FILE="${BOOTSTRAP_DIR}/service/init.d/hyperd.ubuntu"
    elif [[ "${LSB_DISTRO}" == "linuxmint" ]] ; then
      SRC_INIT_FILE="${BOOTSTRAP_DIR}/service/init.d/hyperd.ubuntu"
    else
      SRC_INIT_FILE="${BOOTSTRAP_DIR}/service/init.d/hyperd.${LSB_DISTRO}"
    fi
    TGT_INIT_FILE="/etc/init.d/hyperd"
  elif [[ "${INIT_SYSTEM}" == "systemd" ]];then
    SRC_INIT_FILE="${BOOTSTRAP_DIR}/service/systemd/hyperd.service"
    TGT_INIT_FILE="/lib/systemd/system/hyperd.service"
  fi
  if [[ -s ${SRC_INIT_FILE} ]];then
    ${BASH_C} "cp ${SRC_INIT_FILE} ${TGT_INIT_FILE}"
    ${BASH_C} "chmod +x ${TGT_INIT_FILE}"
  else
    show_message error "${ERR_INSTALL_SERVICE_FAILED[1]}"
    display_support ${ERR_INSTALL_SERVICE_FAILED[1]}
    exit ${ERR_INSTALL_SERVICE_FAILED[0]}
  fi
}
stop_running_hyperd() {
  set +e
  pgrep hyperd >/dev/null 2>&1
  if [[ $? -eq 0 ]];then
    echo -e "\nStopping running hyperd service before install"
    if [[ "${INIT_SYSTEM}" == "systemd" ]]
    then ${BASH_C} "systemctl stop hyperd"
    else ${BASH_C} "service hyperd stop";
    fi
    sleep 3
  fi
  set -e
}
start_hyperd_service() {
  show_message info "Start hyperd service\n"
  if [[ "${INIT_SYSTEM}" == "systemd" ]]
  then ${BASH_C} "systemctl start hyperd"
  else ${BASH_C} "service hyperd start";
  fi
  sleep 3
  set +e
  pgrep hyperd >/dev/null 2>&1
  if [[ $? -eq 0 ]];then
    show_message success "\nhyperd is running."
    cat <<COMMENT
----------------------------------------------------
To see how to use hyperctl:
  sudo hyperctl help
To manage hyperd service:
  sudo service hyperd {start|stop|restart|status}
To get more information:
  http://hyper.sh
COMMENT
  else
    show_message warn "\nhyperd isn't running."
    cat <<COMMENT
Please try to start hyperd by manual:
  sudo service hyperd restart
  sudo service hyperd status
COMMENT
  fi
  set -e
}
handle_hyper_rpm_rename(){
  if (command_exist hyper hyperd && ! command_exist hyperctl);then
    ${BASH_C} "cp -f /etc/hyper/config /etc/hyper/config.rpmsave"
    ${BASH_C} "yum remove -y hyper hyperstart"
    ${BASH_C} "cp -f /etc/hyper/config.rpmsave /etc/hyper/config"
  fi
}
install_from_rpm(){
  show_message info "Fetch rpm package for $1...\n"
  set +e
  ${BASH_C} "ping -c 3 -W 2 hypercontainer-install.s3.amazonaws.com >/dev/null 2>&1"
  if [[ $? -ne 0 ]];then
    S3_URL="http://mirror-hypercontainer-install.s3.amazonaws.com"
  else
    S3_URL="http://hypercontainer-install.s3.amazonaws.com"
  fi
  case "$1" in
    centos7)
      rpm -qa | grep ${CENTOS7_HYPER} > /dev/null 2>&1
      if [[ $? -eq 0 ]];then
        show_message info "${ERR_HYPER_NO_NEW_VERSION[1]}"; exit 1
      fi
      if (command_exist hyperctl hyperd);then
        _ACT="update"
      else
        _ACT="install"
      fi
      handle_hyper_rpm_rename
      ${BASH_C} "yum ${_ACT} -y ${S3_URL}/${CENTOS7_QEMU_HYPER}.rpm ${S3_URL}/${CENTOS7_HYPERSTART}.rpm ${S3_URL}/${CENTOS7_HYPER}.rpm"
      ;;
    fedora23|fedora24)
      rpm -qa | grep ${FC23_HYPER} > /dev/null 2>&1
      if [[ $? -eq 0 ]];then
        show_message info "${ERR_HYPER_NO_NEW_VERSION[1]}"; exit 1
      fi
      if (command_exist hyperctl hyperd);then
        _ACT="update"
      else
        _ACT="install"
      fi
      handle_hyper_rpm_rename
      ${BASH_C} "dnf ${_ACT} -y ${S3_URL}/${FC23_HYPERSTART}.rpm ${S3_URL}/${FC23_HYPER}.rpm"
      ;;
    *) show_message error "rpm install support centos7 & fedora23 only"; exit 1;;
  esac
  set -e
}
install_from_deb(){
  show_message info "Fetch deb package for $1...\n"
  set +e
  local USE_WGET=$( echo $(get_curl) | awk -F"|" '{print $1}' )
  local CURL_C=$( echo $(get_curl) | awk -F"|" '{print $2}' )
  LIBVIRT0=`dpkg -s libvirt0 2>/dev/null| grep Version| wc -l`
  if [ ${LIBVIRT0} -eq 0 ];then
    show_message info "hypercontainer depends on libvirt0(1.2.16-2+), start install libvirt0...\n"
    show_message error "${ERR_LIBVIRT_NOT_INSTALL[1]}"
    exit ${ERR_LIBVIRT_NOT_INSTALL[0]}
  fi

  ${BASH_C} "ping -c 3 -W 2 hypercontainer-install.s3.amazonaws.com >/dev/null 2>&1"
  if [[ $? -ne 0 ]];then
    S3_URL="http://mirror-hypercontainer-install.s3.amazonaws.com"
  else
    S3_URL="http://hypercontainer-install.s3.amazonaws.com"
  fi
  case "$1" in
    ubuntu|debian)
      dpkg -l ${DEBIAN_HYPER} > /dev/null 2>&1
      if [[ $? -eq 0 ]];then
        show_message info "${ERR_HYPER_NO_NEW_VERSION[1]}"; exit 1
      fi
      if (command_exist hyperctl hyperd);then
        _ACT="update"
      else
        _ACT="install"
      fi
      if [[ "${USE_WGET}" == "true" ]];then
        ${BASH_C} "${CURL_C} -O /tmp/${DEBIAN_HYPERSTART}.deb ${S3_URL}/${DEBIAN_HYPERSTART}.deb && dpkg -i /tmp/${DEBIAN_HYPERSTART}.deb"
        ${BASH_C} "${CURL_C} -O /tmp/${DEBIAN_HYPER}.deb ${S3_URL}/${DEBIAN_HYPER}.deb && dpkg -i /tmp/${DEBIAN_HYPER}.deb"
      else
        ${BASH_C} "${CURL_C} /tmp/${DEBIAN_HYPERSTART}.deb ${S3_URL}/${DEBIAN_HYPERSTART}.deb && dpkg -i /tmp/${DEBIAN_HYPERSTART}.deb"
        ${BASH_C} "${CURL_C} /tmp/${DEBIAN_HYPER}.deb ${S3_URL}/${DEBIAN_HYPER}.deb && dpkg -i /tmp/${DEBIAN_HYPER}.deb"
      fi
      ;;
    *) show_message error "deb install support debian & ubuntu only"; exit 1;;
  esac
  set -e
}
display_support() {
  echo "Sorry, we are suffering from some technical issue($1), please contact ${SUPPORT_EMAIL}"
  if [[ $# -eq 0 ]];then exit ${ERR_UNKNOWN}
  else exit $1
  fi
}
command_exist() {
  type "$@" > /dev/null 2>&1
}
get_curl() {
  CURL_C=""; USE_WGET="false"
  if (command_exist curl);then
    CURL_C='curl -SL -o '
  elif (command_exist wget);then
    USE_WGET="true"
    CURL_C='wget -O '
  fi
  echo "${USE_WGET}|${CURL_C}"
}
show_message() {
  case "$1" in
    debug)  echo -e "\n[${BLUE}DEBUG${RESET}] : $2";;
    info)   echo -e -n "\n${WHITE}$2${RESET}" ;;
    warn)   echo -e    "\n[${YELLOW}WARN${RESET}] : $2" ;;
    done|success) echo -e "${LIGHT}${GREEN}$2${RESET}" ;;
    error|failed) echo -e "\n[${RED}ERROR${RESET}] : $2" ;;
  esac
}
#################
main
