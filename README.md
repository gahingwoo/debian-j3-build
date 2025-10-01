# Samsung Galaxy J3 2016 Debian Port Product Documentation

## Introduction

This project aims to port **Debian Bookworm** to the **Samsung Galaxy J3 2016** (model: j3ltetw) mobile phone. It is based on **postmarketOS** device configuration and resources, utilizing the **lk2nd + fastboot** installation method. The accompanying script automates kernel compilation, root filesystem creation, firmware preparation, and flash script generation.

-----

## Key Features

  - Based on **Debian Bookworm**, supporting mainstream **ARM64** packages.
  - Utilizes postmarketOS device configuration for mainline kernel compatibility.
  - Automated build and flashing process.
  - Support for key hardware, including **WiFi**, **Bluetooth**, **touchscreen**, and **audio**.
  - **SSH** is enabled by default for easy remote management.

-----

## Environment Setup

  - Recommended OS: **Debian 12 or newer**.
  - Dependencies required: `debootstrap`, `qemu-user-static`, `git`, `build-essential`, `android-tools-fastboot`, etc. (The script installs them automatically).
  - The phone must have the **lk2nd bootloader** already flashed.

-----

## Usage Guide

### 1\. Build the System

```bash
chmod +x build.sh
./build.sh
```

The script will automatically perform the following steps:

  - Install dependencies.
  - Download postmarketOS device configuration.
  - Download and check lk2nd.
  - Download and compile the mainline kernel.
  - Create the Debian root filesystem.
  - Install kernel modules and firmware.
  - Generate **boot.img**, **rootfs.img**, and the automatic flash script **flash.sh**.

### 2\. Flashing Procedure

#### Method 1: Automatic Flashing

```bash
./flash.sh
```

#### Method 2: Manual Flashing

1.  Put the phone into **fastboot mode** (Volume Down + Power).
2.  Execute the following:
    ```bash
    fastboot flash boot boot.img
    fastboot flash userdata rootfs.img
    fastboot reboot
    ```

-----

## Default Account Information

  - Users: **user** / **root**
  - Password: **147258**

-----

## First Boot Notes

  - **WiFi** and **Bluetooth** need to be manually enabled in system settings.
  - **Touchscreen calibration** may require adjustment.
  - **SSH** is enabled by default and accessible over the local network.

-----

## Troubleshooting
You can access the serial output of the Samsung Galaxy J3 2016 via the MicroUSB port.
To view boot logs or debug output, connect the phone to your computer with a USB cable and use the following command in your terminal:

```bash
screen /dev/ttyUSB0 115200
```

If `/dev/ttyUSB0` does not appear, you may need a USB-to-serial adapter or check your drivers.
This allows you to monitor the device’s serial console during boot and troubleshooting.

If the device fails to boot, you can also check the boot logs via a serial connection.

-----

## Directory Structure

  - `boot.img`: Kernel + DTB + initramfs
  - `rootfs.img`: Debian root filesystem (approx. 8GB)
  - `flash.sh`: Automatic flash script
  - `lk2nd.img`: lk2nd bootloader image

-----

## Disclaimer

This project is a community port and may have compatibility issues. **Flashing carries risks; please proceed with caution** and it is recommended to back up your data beforehand.
