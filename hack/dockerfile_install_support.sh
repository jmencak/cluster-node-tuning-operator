#!/bin/bash

set -euo pipefail
set -o xtrace

INSTALL_PKGS="nmap-ncat procps-ng pciutils"

# TuneD pre-installation steps
cp -r /root/assets/bin/* /usr/local/bin
mkdir -p /etc/grub.d/ /boot /run/ocp-tuned
chown -R 499:499 /run/ocp-tuned	# the operator must be able to write metrics client CA in a temporary directory

source /etc/os-release
if [[ "${ID}" == "centos" ]]; then

  # CentOS OKD build
  BUILD_INSTALL_PKGS="gcc git rpm-build make desktop-file-utils patch dnf-plugins-core"
  dnf install --setopt=tsflags=nodocs -y ${BUILD_INSTALL_PKGS}
  cd /root/assets/tuned/tuned
  LC_COLLATE=C cat ../patches/*.diff | patch -Np1
  dnf build-dep tuned.spec -y
  make rpm PYTHON=/usr/bin/python3
  rm -rf /root/rpmbuild/RPMS/noarch/{tuned-gtk*,tuned-utils*,tuned-profiles-compat*}
  dnf --setopt=protected_packages= history -y undo 0  # Remove builddep

  cp -r /root/rpmbuild/RPMS/noarch /root/rpms
  dnf install --setopt=tsflags=nodocs -y ${INSTALL_PKGS}
  dnf --setopt=tsflags=nodocs -y install /root/rpms/*.rpm

  # Clean up build tools to remove image footprint
  dnf remove --setopt=protected_packages= -y ${BUILD_INSTALL_PKGS}
  dnf autoremove -y

else

  # RHEL OCP build
  INSTALL_PKGS=" \
     tuned tuned-profiles-atomic tuned-profiles-cpu-partitioning tuned-profiles-mssql tuned-profiles-nfv tuned-profiles-nfv-guest \
     tuned-profiles-nfv-host tuned-profiles-openshift tuned-profiles-oracle tuned-profiles-postgresql tuned-profiles-realtime \
     tuned-profiles-sap tuned-profiles-sap-hana tuned-profiles-spectrumscale \
     $INSTALL_PKGS"
  dnf install --setopt=tsflags=nodocs -y ${INSTALL_PKGS}

fi

# TuneD post-installation steps
rm -rf /etc/tuned/recommend.d /var/lib/tuned
echo auto > /etc/tuned/profile_mode
sed -Ei 's|^#?\s*enable_unix_socket\s*=.*$|enable_unix_socket = 1|;s|^#?\s*rollback\s*=.*$|rollback = not_on_exit|;s|^#?\s*profile_dirs\s*=.*$|profile_dirs = /usr/lib/tuned/profiles,/usr/lib/tuned,/var/lib/ocp-tuned/profiles|' \
  /etc/tuned/tuned-main.conf
mv /etc/tuned /etc/tuned.orig
ln -s /var/lib/ocp-tuned/tuned /etc/tuned
ln -s /host/var/lib/ocp-tuned /var/lib/ocp-tuned
ln -s /host/var/lib/tuned /var/lib/tuned
touch /etc/sysctl.conf
