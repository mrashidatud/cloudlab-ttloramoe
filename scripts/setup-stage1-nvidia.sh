#!/usr/bin/env bash
set -euxo pipefail

LOGDIR=/var/log/cloudlab-setup
mkdir -p "$LOGDIR"
exec &> >(tee -a "$LOGDIR/stage1-nvidia.log")

# Ensure apt is happy
export DEBIAN_FRONTEND=noninteractive
APT='apt-get -y -o Dpkg::Options::=--force-confnew --allow-change-held-packages'

$APT update
$APT dist-upgrade
$APT install build-essential dkms linux-headers-$(uname -r) curl wget ca-certificates gnupg lsb-release pciutils

# Disable nouveau if present
if ! grep -q "blacklist nouveau" /etc/modprobe.d/blacklist-nouveau.conf 2>/dev/null; then
  cat <<EOF >/etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF
  update-initramfs -u
fi

# Install a recent production driver (V100S is fine with 535+)
$APT install nvidia-driver-535

# Add a simple systemd unit that continues after reboot
cp /local/repository/scripts/cloudlab-continue.service /etc/systemd/system/cloudlab-continue.service
systemctl daemon-reload

# Enable the continue unit to run stage 2 on next boot
systemctl enable cloudlab-continue.service

# Flag file so stage2 knows stage1 completed
mkdir -p /opt/cloudlab-setup
touch /opt/cloudlab-setup/STAGE1_DONE

sleep 90 || true
/sbin/shutdown -r +1 "Rebooting to load the NVIDIA driver..."
exit 0
