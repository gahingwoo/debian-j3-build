#!/bin/bash
# Samsung Galaxy J3 2016 Debian Build Script
# Directly using postmarketOS's configuration and resources
# Based on lk2nd + fastboot installation

set -e

DEVICE="samsung-j3ltetw"
DEBIAN_VERSION="bookworm"
WORK_DIR="$HOME/debian-j3-build"
DEVICE_DTB="$WORK_DIR/msm8916-samsung-j3ltetw.dtb"


echo "=== Preparing Build Environment ==="
mkdir -p $WORK_DIR
cd $WORK_DIR

# 1. Install Dependencies
echo "=== Installing Dependencies ==="
sudo apt update
sudo apt install -y \
    debootstrap \
    qemu-user-static \
    binfmt-support \
    git \
    build-essential \
    bc \
    kmod \
    cpio \
    flex \
    libncurses5-dev \
    libelf-dev \
    libssl-dev \
    dwarves \
    bison \
    mkbootimg \
    android-tools-fastboot \
    device-tree-compiler \
    e2fsprogs \
    dosfstools \
    gcc-aarch64-linux-gnu \
    python3 \
    python3-pip \
    wget \
    curl \
    e2fsprogs \
    rsync \

# 2. Clone pmaports (postmarketOS device configuration)
echo "=== Getting postmarketOS Device Configuration ==="
if [ ! -d "pmaports" ]; then
    git clone --depth=1 https://gitlab.postmarketos.org/postmarketOS/pmaports.git
fi

# 3. Get lk2nd
echo "=== Downloading lk2nd ==="
if [ ! -f "lk2nd.img" ]; then
    wget https://github.com/msm8916-mainline/lk2nd/releases/download/21.0/lk2nd-msm8916.img -O lk2nd.img
    echo ""
    echo "!!! You need to flash lk2nd first for initial use !!!"
    echo "Steps:"
    echo "  1. Put the phone into Download mode (Volume Down + Home + Power)"
    echo "  2. Use Heimdall: heimdall flash --BOOT lk2nd.img"
    echo "  3. After reboot, hold Volume Down to enter lk2nd fastboot mode"
    echo ""
    read -p "Is lk2nd already installed? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Please install lk2nd first, then run this script again"
        exit 1
    fi
fi

# 4. Extract Kernel Configuration from pmaports
echo "=== Parsing postmarketOS Kernel Configuration ==="
cd pmaports/device/community/linux-postmarketos-qcom-msm8916

# Read APKBUILD to get kernel source info
KERNEL_SOURCE=$(grep "^source=" APKBUILD | cut -d'"' -f2 | grep "\.tar" | head -n1)
KERNEL_VERSION=$(grep "^pkgver=" APKBUILD | cut -d'=' -f2)

cd $WORK_DIR

# 5. Get Kernel Source
echo "=== Cloning Kernel Source ==="
if [ ! -d "linux-msm8916" ]; then
    # Use msm8916-mainline kernel
    git clone --depth=1 https://github.com/msm8916-mainline/linux.git linux-msm8916
fi

# 6. Get Firmware and Device Configuration Files
echo "=== Preparing Firmware and Device Files ==="

# Get from linux-firmware
if [ ! -d "linux-firmware" ]; then
    echo "Cloning linux-firmware (This may take a while)..."
    git clone --depth=1 https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
fi

# Copy device-specific files from pmaports
mkdir -p device-files
cp -r pmaports/device/testing/device-samsung-j3ltetw/* device-files/ 2>/dev/null || true

# 7. Compile Kernel
cd $WORK_DIR/linux-msm8916

# Check if the kernel already exists
if [ -f "arch/arm64/boot/Image" ]; then
    echo "Kernel already exists, skipping compilation"
else
    echo "=== Compiling Kernel ==="
    
    # Use postmarketOS's kernel configuration
    if [ -f "$WORK_DIR/pmaports/device/community/linux-postmarketos-qcom-msm8916/config-postmarketos-qcom-msm8916.aarch64" ]; then
        cp "$WORK_DIR/pmaports/device/community/linux-postmarketos-qcom-msm8916/config-postmarketos-qcom-msm8916.aarch64" .config
    else
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
    fi

    # Apply patches (if any)
    if [ -d "$WORK_DIR/pmaports/device/community/linux-postmarketos-qcom-msm8916" ]; then
        for patch in $WORK_DIR/pmaports/device/community/linux-postmarketos-qcom-msm8916/*.patch; do
            [ -f "$patch" ] && echo "Applying patch: $(basename $patch)" && patch -p1 < "$patch" || true
        done
    fi

    # Ensure critical drivers are enabled
    scripts/config --enable CONFIG_MODULES
    scripts/config --enable CONFIG_MODULE_UNLOAD
    scripts/config --enable CONFIG_DRM_MSM
    scripts/config --enable CONFIG_TOUCHSCREEN_ZINITIX
    scripts/config --enable CONFIG_WCN36XX
    scripts/config --enable CONFIG_BT_HCIUART_BCM
    scripts/config --enable CONFIG_SND_SOC_MSM8916_WCD_ANALOG
    scripts/config --enable CONFIG_USB_DWC3_QCOM

    # Compile kernel
    echo "Starting kernel compilation (may take 10-30 minutes)..."
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
fi

# 8. Create Debian rootfs
echo "=== Creating Debian rootfs ==="
cd $WORK_DIR
ROOTFS_DIR="$WORK_DIR/rootfs"
sudo rm -rf $ROOTFS_DIR
sudo debootstrap --arch=arm64 --foreign $DEBIAN_VERSION $ROOTFS_DIR http://deb.debian.org/debian

# Configure QEMU
sudo cp /usr/bin/qemu-aarch64-static $ROOTFS_DIR/usr/bin/

# Complete debootstrap
sudo chroot $ROOTFS_DIR /debootstrap/debootstrap --second-stage

# 9. Configure System
echo "=== Configuring Debian System ==="
sudo chroot $ROOTFS_DIR /bin/bash <<'CHROOT_EOF'
export DEBIAN_FRONTEND=noninteractive

# Password
echo "root:147258" | chpasswd
useradd -m -G sudo,video,audio,input,plugdev,netdev -s /bin/bash user
echo "user:147258" | chpasswd

# Hostname
echo "j3ltetw-debian" > /etc/hostname

# APT Sources
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF

# Update and install packages
apt update
apt install -y \
    systemd systemd-sysv udev kmod \
    firmware-linux firmware-misc-nonfree firmware-atheros \
    network-manager wpasupplicant iw wireless-tools \
    bluez sudo ssh vim nano

# Enable services
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable ssh

# fstab (lk2nd partitions)
cat > /etc/fstab <<EOF
/dev/disk/by-partlabel/userdata  /      ext4  defaults,noatime  0  1
/dev/disk/by-partlabel/boot      /boot  ext4  defaults          0  2
EOF

# Serial autologin
mkdir -p /etc/systemd/system/serial-getty@ttyMSM0.service.d
cat > /etc/systemd/system/serial-getty@ttyMSM0.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF

# Predictable network interface names
ln -sf /dev/null /etc/systemd/network/99-default.link

CHROOT_EOF

# 10. Install Kernel Modules
echo "=== Installing Kernel Modules ==="
cd $WORK_DIR/linux-msm8916
sudo make ARCH=arm64 INSTALL_MOD_PATH=$ROOTFS_DIR modules_install

# 11. Install Firmware
echo "=== Installing Firmware Files ==="
sudo mkdir -p $ROOTFS_DIR/lib/firmware

# Copy Qualcomm firmware
if [ -d "$WORK_DIR/linux-firmware/qcom" ]; then
    sudo cp -r $WORK_DIR/linux-firmware/qcom $ROOTFS_DIR/lib/firmware/
fi

# Copy other firmware
for fw_dir in ath9k ath10k brcm ti-connectivity; do
    if [ -d "$WORK_DIR/linux-firmware/$fw_dir" ]; then
        sudo cp -r $WORK_DIR/linux-firmware/$fw_dir $ROOTFS_DIR/lib/firmware/
    fi
done

# Copy device-specific firmware from pmaports (if any)
if [ -d "$WORK_DIR/pmaports/device/testing/firmware-samsung-j3ltetw" ]; then
    sudo cp -r $WORK_DIR/pmaports/device/testing/firmware-samsung-j3ltetw/firmware/* $ROOTFS_DIR/lib/firmware/ 2>/dev/null || true
fi

# 12. Create boot.img
echo "=== Creating boot.img ==="
cd $WORK_DIR

# Create initramfs
mkdir -p initramfs/{bin,sbin,etc,proc,sys,dev,newroot}
cat > initramfs/init <<'INIT_EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
sleep 2
mount -o ro /dev/disk/by-partlabel/userdata /newroot || mount /dev/mmcblk0p26 /newroot
exec switch_root /newroot /sbin/init
INIT_EOF
chmod +x initramfs/init

# Copy busybox
if command -v busybox &> /dev/null; then
    cp $(which busybox) initramfs/bin/
else
    sudo apt install -y busybox-static
    cp /bin/busybox initramfs/bin/
fi

for cmd in sh mount umount switch_root sleep; do
    ln -sf busybox initramfs/bin/$cmd
done

cd initramfs
find . | cpio -o -H newc | gzip > ../initramfs.cpio.gz
cd ..

# Package boot.img
mkbootimg \
    --kernel linux-msm8916/arch/arm64/boot/Image \
    --ramdisk initramfs.cpio.gz \
    --dtb $DEVICE_DTB \
    --cmdline "console=ttyMSM0,115200 root=/dev/disk/by-partlabel/userdata rw rootwait" \
    --base 0x80000000 \
    --pagesize 2048 \
    --kernel_offset 0x00080000 \
    --ramdisk_offset 0x02000000 \
    --tags_offset 0x01e00000 \
    --output boot.img

echo "boot.img created"

# 13. Package rootfs
echo "=== Creating rootfs image ==="
dd if=/dev/zero of=rootfs.img bs=1M count=8192 status=progress 
sudo /usr/sbin/mkfs.ext4 -L debian-rootfs rootfs.img

mkdir -p mnt
sudo mount rootfs.img mnt

sudo rsync -a \
    --exclude='/proc' \
    --exclude='/sys' \
    --exclude='/dev' \
    --exclude='/run' \
    --exclude='/tmp' \
    --exclude='/mnt' \
    --exclude='/media' \
    --exclude='/linux-msm8916' \
    --exclude='/pmaports' \
    --exclude='/initramfs' \
    --exclude='/device-files' \
    --exclude='/home' \
    $ROOTFS_DIR/ mnt/

sudo umount mnt
rmdir mnt

# 14. Generate Flash Script
cat > flash.sh <<'FLASH_EOF'
#!/bin/bash
echo "=== Samsung Galaxy J3 2016 Debian Flash Script ==="
echo ""
echo "Please ensure:"
echo "  1. lk2nd is already installed"
echo "  2. The phone is in fastboot mode"
echo ""
read -p "Press Enter to continue..."

# Check device
if ! fastboot devices | grep -q .; then
    echo "Error: No fastboot device detected!"
    echo "Please ensure the phone is in fastboot mode and connected to the computer"
    exit 1
fi

echo ""
echo "Starting flashing process..."
echo ""

# Flash boot
echo "Flashing boot.img..."
fastboot flash boot boot.img

# Flash rootfs
echo "Flashing rootfs.img (This may take a few minutes)..."
fastboot flash userdata rootfs.img

# Optional: Erase cache
echo "Erasing cache..."
fastboot erase cache

echo ""
echo "Flashing complete!"
echo ""
read -p "Do you want to reboot the phone? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    fastboot reboot
    echo "Phone is rebooting..."
fi
FLASH_EOF

chmod +x flash.sh

echo ""
echo "=========================================="
echo "✅ Build complete!"
echo "=========================================="
echo ""
echo "Generated files:"
echo "  📦 boot.img       - Kernel + DTB + initramfs"
echo "  📦 rootfs.img     - Debian Root Filesystem (4GB)"
echo "  🔧 flash.sh       - Automatic flash script"
echo "  💾 lk2nd.img      - lk2nd bootloader"
echo ""
echo "=== Flashing Method ==="
echo ""
echo "Method 1: Using the automatic script"
echo "  ./flash.sh"
echo ""
echo "Method 2: Manual flashing"
echo "  1. Put the phone into fastboot mode (Volume Down + Power)"
echo "  2. fastboot flash boot boot.img"
echo "  3. fastboot flash userdata rootfs.img"
echo "  4. fastboot reboot"
echo ""
echo "=== Login Information ==="
echo "  Users: user / root"
echo "  Password: 147258"
echo ""
echo "=== First Boot Tips ==="
echo "  - WiFi and Bluetooth need to be manually enabled in settings"
echo "  - Touchscreen calibration may need adjustment"
echo "  - SSH is enabled by default and accessible over the network"
echo ""
echo "=== Troubleshooting ==="
echo "  If the device doesn't boot, check the boot logs via serial connection:"
echo "    screen /dev/ttyUSB0 115200"
echo "=========================================="