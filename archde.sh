#!/usr/bin/env bash
set -e

# Arch Linux Desktop Environment (archde)
#
#

#



BIOS_TYPE=""
PARTITION_BIOS=""
PARTITION_BOOT=""
PARTITION_ROOT=""
DEVICE_ROOT=""
DEVICE_ROOT_MAPPER=""
PARTITION_BOOT_NUMBER=0
UUID_BOOT=""
UUID_ROOT=""
DEVICE_TRIM=""
ALLOW_DISCARDS=""
CPU_INTEL=""
VIRTUALBOX=""
GRUB_CMDLINE_LINUX=""

RED='\033[0;31m'
NC='\033[0m'

function configuration_install() {
    source archde.conf
}

function check_variables() {
    check_variables_value "KEYS" "$KEYS"
    check_variables_value "DEVICE" "$DEVICE"
    check_variables_boolean "LVM" "$LVM"
    check_variables_list "FILE_SYSTEM_TYPE" "$FILE_SYSTEM_TYPE" "ext4 btrfs xfs"
    check_variables_value "PING_HOSTNAME" "$PING_HOSTNAME"
    check_variables_value "TIMEZONE" "$TIMEZONE"
    check_variables_value "LOCALE" "$LOCALE"
    check_variables_value "LANG" "$LANG"
    check_variables_value "KEYMAP" "$KEYMAP"
    check_variables_value "HOSTNAME" "$HOSTNAME"
    check_variables_value "USER_NAME" "$USER_NAME"
    check_variables_value "USER_PASSWORD" "$USER_PASSWORD"
    check_variables_boolean "YAOURT" "$YAOURT"
    check_variables_list "DESKTOP_ENVIRONMENT" "$DESKTOP_ENVIRONMENT" "gnome kde xfce mate cinnamon lxde budgie" "false"
    check_variables_list "DISPLAY_DRIVER" "$DISPLAY_DRIVER" "xf86-video-intel xf86-video-amdgpu xf86-video-ati nvidia nvidia-340xx nvidia-304xx xf86-video-nouveau" "false"
    check_variables_boolean "REBOOT" "$REBOOT"
}

function check_variables_value() {
    NAME=$1
    VALUE=$2
    if [ -z "$VALUE" ]; then
        echo "$NAME environment variable must have a value."
        exit
    fi
}

function check_variables_boolean() {
    NAME=$1
    VALUE=$2
    check_variables_list "$NAME" "$VALUE" "true false"
}

function check_variables_list() {
    NAME=$1
    VALUE=$2
    VALUES=$3
    REQUIRED=$4
    if [ "$REQUIRED" == "" -o "$REQUIRED" == "true" ]; then
        check_variables_value "$NAME" "$VALUE"
    fi

    if [ "$VALUE" != "" -a -z "$(echo "$VALUES" | grep -F -w "$VALUE")" ]; then
        echo "$NAME environment variable value [$VALUE] must be in [$VALUES]."
        exit
    fi
}

function warning() {
    echo "Bienvenido al script de instalacion de Arch Linux"
    echo ""
    echo -e "${RED}Precaucion"'!'"${NC}"
    echo -e "${RED}Toda tu informacion sera eliminada del disco${NC}"
    echo -e "${RED}Sin posibilidad de Recuperacion.${NC}"
    echo -e "${RED}NOTA: Este software se entrega tal como esta, sin soporte ni garanatias de ningun tipo.${NC}"
    echo ""
    read -p "Quieres continuar? [y/n] " yn
    case $yn in
        [Yy]* )
            ;;
        [Nn]* )
            exit
            ;;
        * )
            exit
            ;;
    esac
}

function init() {
    loadkeys $KEYS
}

function facts() {
    if [ -d /sys/firmware/efi ]; then
        BIOS_TYPE="uefi"
    else
        BIOS_TYPE="bios"
    fi

    if [ -n "$(hdparm -I $DEVICE | grep TRIM)" ]; then
        DEVICE_TRIM="true"
    else
        DEVICE_TRIM="false"
    fi

    if [ -n "$(lscpu | grep GenuineIntel)" ]; then
        CPU_INTEL="true"
    fi

    if [ -n "$(lspci | grep -i virtualbox)" ]; then
        VIRTUALBOX="true"
    fi
}

function network_install() {
    if [ -n "$WIFI_INTERFACE" ]; then
        cp /etc/netctl/examples/wireless-wpa /etc/netctl
      	chmod 600 /etc/netctl

      	sed -i 's/^Interface=.*/Interface='"$WIFI_INTERFACE"'/' /etc/netctl
      	sed -i 's/^ESSID=.*/ESSID='"$WIFI_ESSID"'/' /etc/netctl
      	sed -i 's/^Key=.*/Key='\''$WIFI_KEY'\''/' /etc/netctl
      	if [ "$WIFI_HIDDEN" == "true" ]; then
      		sed -i 's/^#Hidden=.*/Hidden=yes/' /etc/netctl
      	fi

      	netctl start wireless-wpa
    fi

    ping -c 5 $PING_HOSTNAME
    if [ $? -ne 0 ]; then
        echo "ERROR!! conexion no disponible, no se puede continuar."
        exit
    fi
}

function partition() {
    sgdisk --zap-all $DEVICE
    wipefs -a $DEVICE

    if [ "$BIOS_TYPE" == "uefi" ]; then
        PARTITION_BOOT="/dev/sda1"
        PARTITION_ROOT="/dev/sda2"
        PARTITION_BOOT_NUMBER=1
        DEVICE_ROOT="/dev/sda2"
        DEVICE_ROOT_MAPPER="root"

        parted -s $DEVICE mklabel gpt mkpart primary fat32 1MiB 512MiB mkpart primary $FILE_SYSTEM_TYPE 512MiB 100% set 1 boot on
        sgdisk -t=1:ef00 $DEVICE
    fi

    if [ "$BIOS_TYPE" == "bios" ]; then
        PARTITION_BIOS="/dev/sda1"
        PARTITION_BOOT="/dev/sda2"
        PARTITION_ROOT="/dev/sda3"
        PARTITION_BOOT_NUMBER=2
        DEVICE_ROOT="/dev/sda3"
        DEVICE_ROOT_MAPPER="root"

        parted -s $DEVICE mklabel gpt mkpart primary fat32 1MiB 128MiB mkpart primary $FILE_SYSTEM_TYPE 128MiB 512MiB mkpart primary $FILE_SYSTEM_TYPE 512MiB 100% set 1 boot on
        sgdisk -t=1:ef02 $DEVICE
    fi

    if [ "$LVM" == "true" ]; then
        DEVICE_ROOT_MAPPER="lvm"
    fi

    if [ -n "$PARTITION_ROOT_ENCRYPTION_PASSWORD" ]; then
        echo -n $PARTITION_ROOT_ENCRYPTION_PASSWORD | cryptsetup --key-size=512 --key-file=- luksFormat $PARTITION_ROOT
        echo -n $PARTITION_ROOT_ENCRYPTION_PASSWORD | cryptsetup --key-file=- open $PARTITION_ROOT $DEVICE_ROOT_MAPPER

        DEVICE_ROOT="/dev/mapper/$DEVICE_ROOT_MAPPER"
    fi

    if [ "$LVM" == "true" ]; then
        pvcreate /dev/mapper/$DEVICE_ROOT_MAPPER
        vgcreate lvm /dev/mapper/$DEVICE_ROOT_MAPPER
        lvcreate -l 100%FREE -n lvroot $DEVICE_ROOT_MAPPER

        DEVICE_ROOT_MAPPER="lvm-lvroot"
        DEVICE_ROOT="/dev/mapper/$DEVICE_ROOT_MAPPER"
    fi

    if [ "$BIOS_TYPE" == "uefi" ]; then
        wipefs -a $PARTITION_BOOT
        mkfs.fat -n ESP -F32 $PARTITION_BOOT
        if [ "$FILE_SYSTEM_TYPE" == "ext4" ]; then
            wipefs -a $DEVICE_ROOT
            mkfs."$FILE_SYSTEM_TYPE" -L root -E discard $DEVICE_ROOT
        else
            wipefs -a $DEVICE_ROOT
            mkfs."$FILE_SYSTEM_TYPE" -L root $DEVICE_ROOT
        fi
    fi

    if [ "$BIOS_TYPE" == "bios" ]; then
        wipefs -a $PARTITION_BIOS
        mkfs.fat -n BIOS -F32 $PARTITION_BIOS
        if [ "$FILE_SYSTEM_TYPE" == "ext4" ]; then
            wipefs -a $PARTITION_BOOT
            wipefs -a $DEVICE_ROOT
            mkfs."$FILE_SYSTEM_TYPE" -L boot -E discard $PARTITION_BOOT
            mkfs."$FILE_SYSTEM_TYPE" -L root -E discard $DEVICE_ROOT
        elif [ "$FILE_SYSTEM_TYPE" == "xfs" ]; then
            wipefs -a $PARTITION_BOOT
            wipefs -a $DEVICE_ROOT
            mkfs."$FILE_SYSTEM_TYPE" -L boot -f $PARTITION_BOOT
            mkfs."$FILE_SYSTEM_TYPE" -L root -f $DEVICE_ROOT
        else
            wipefs -a $PARTITION_BOOT
            wipefs -a $DEVICE_ROOT
            mkfs."$FILE_SYSTEM_TYPE" -L boot $PARTITION_BOOT
            mkfs."$FILE_SYSTEM_TYPE" -L root $DEVICE_ROOT
        fi
    fi

    mount $DEVICE_ROOT /mnt

    mkdir /mnt/boot
    mount $PARTITION_BOOT /mnt/boot

    if [ -n "$SWAP_SIZE" -a "$FILE_SYSTEM_TYPE" != "btrfs" ]; then
        fallocate -l $SWAP_SIZE /mnt/swap
        chmod 600 /mnt/swap
        mkswap /mnt/swap
    fi

    UUID_BOOT=$(blkid -s UUID -o value $PARTITION_BOOT)
    UUID_ROOT=$(blkid -s UUID -o value $PARTITION_ROOT)
}

function install() {
    pacman -Sy --noconfirm reflector
    reflector --verbose -l 5 --sort rate --save /etc/pacman.d/mirrorlist
    pacman -Syy
    pacstrap /mnt base base-devel
}

function kernels() {
    arch-chroot /mnt pacman -Sy --noconfirm linux-headers
    if [ -n "$KERNELS" ]; then
        arch-chroot /mnt pacman -Sy --noconfirm $KERNELS
    fi
}

function configuration() {
    genfstab -U /mnt >> /mnt/etc/fstab

    if [ "$DEVICE_TRIM" == "true" ]; then
        sed -i 's/relatime/noatime,discard/' /mnt/etc/fstab
        sed -i 's/issue_discards = 0/issue_discards = 1/' /mnt/etc/lvm/lvm.conf
    fi

    if [ -n "$SWAP_SIZE" -a "$FILE_SYSTEM_TYPE" != "btrfs" ]; then
        echo "# swap" >> /mnt/etc/fstab
        echo "/swap none swap defaults 0 0" >> /mnt/etc/fstab
        echo "" >> /mnt/etc/fstab
    fi

    arch-chroot /mnt ln -s -f $TIMEZONE /etc/localtime
    arch-chroot /mnt hwclock --systohc
    sed -i "s/#$LOCALE/$LOCALE/" /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo $LANG > /mnt/etc/locale.conf
    echo $KEYMAP > /mnt/etc/vconsole.conf
    echo $HOSTNAME > /mnt/etc/hostname

    if [ -n "$SWAP_SIZE" ]; then
        echo "vm.swappiness=10" > /mnt/etc/sysctl.d/99-sysctl.conf
    fi

    printf "$ROOT_PASSWORD\n$ROOT_PASSWORD" | arch-chroot /mnt passwd
}

function network() {
    arch-chroot /mnt pacman -Sy --noconfirm networkmanager
    arch-chroot /mnt pacman -Sy --noconfirm net-tools
    arch-chroot /mnt systemctl enable NetworkManager.service
}

function virtualbox() {
    if [ -z "$KERNELS" ]; then
        arch-chroot /mnt pacman -Sy --noconfirm virtualbox-guest-utils virtualbox-guest-modules-arch
    else
        arch-chroot /mnt pacman -Sy --noconfirm virtualbox-guest-utils virtualbox-guest-dkms
    fi
}

function packages() {
    if [ "$FILE_SYSTEM_TYPE" == "btrfs" ]; then
        arch-chroot /mnt pacman -Sy --noconfirm btrfs-progs
    fi

    if [ "$YAOURT" == "true" -o -n "$PACKAGES_YAOURT" ]; then
        echo "" >> /mnt/etc/pacman.conf
        echo "[archlinuxfr]" >> /mnt/etc/pacman.conf
        echo "SigLevel=Optional TrustAll" >> /mnt/etc/pacman.conf
        echo "Server=http://repo.archlinux.fr/\$arch" >> /mnt/etc/pacman.conf

        arch-chroot /mnt pacman -Sy --noconfirm yaourt
    fi

    if [ -n "$PACKAGES_PACMAN" ]; then
        arch-chroot /mnt pacman -Sy --noconfirm --needed $PACKAGES_PACMAN
    fi

    if [ -n "$PACKAGES_YAOURT" ]; then
        arch-chroot /mnt yaourt -S --noconfirm --needed $PACKAGES_YAOURT
    fi
}

function mkinitcpio() {
    if [ "$LVM" == "true" -a -n "$PARTITION_ROOT_ENCRYPTION_PASSWORD" ]; then
        arch-chroot /mnt sed -i 's/ filesystems / lvm2 encrypt keymap filesystems /' /etc/mkinitcpio.conf
    elif [ "$LVM" == "true" ]; then
        arch-chroot /mnt sed -i 's/ filesystems / lvm2 filesystems /' /etc/mkinitcpio.conf
    elif [ -n "$PARTITION_ROOT_ENCRYPTION_PASSWORD" ]; then
        arch-chroot /mnt sed -i 's/ filesystems / encrypt keymap filesystems /' /etc/mkinitcpio.conf
    fi
    arch-chroot /mnt sed -i 's/#COMPRESSION="gzip"/COMPRESSION="gzip"/' /etc/mkinitcpio.conf
    arch-chroot /mnt mkinitcpio -P
}

function bootloader() {
    if [ "$CPU_INTEL" == "true" -a "$VIRTUALBOX" != "true" ]; then
        arch-chroot /mnt pacman -Sy --noconfirm intel-ucode
    fi

    if [ -n "$PARTITION_ROOT_ENCRYPTION_PASSWORD" ]; then
        if [ "$DEVICE_TRIM" == "true" ]; then
            ALLOW_DISCARDS=":allow-discards"
        fi

        GRUB_CMDLINE_LINUX="cryptdevice=UUID='"$UUID_ROOT"':lvm'"$ALLOW_DISCARDS"'"
    fi

    arch-chroot /mnt pacman -Sy --noconfirm grub dosfstools
    arch-chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub
    arch-chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="'$GRUB_CMDLINE_LINUX'"/' /etc/default/grub

    if [ "$BIOS_TYPE" == "uefi" ]; then
        arch-chroot /mnt pacman -Sy --noconfirm efibootmgr
        arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=grub --efi-directory=/boot --recheck
        #arch-chroot /mnt efibootmgr --create --disk $DEVICE --part $PARTITION_BOOT_NUMBER --loader /EFI/grub/grubx64.efi --label "GRUB"
    fi
    if [ "$BIOS_TYPE" == "bios" ]; then
        arch-chroot /mnt grub-install --target=i386-pc --recheck $DEVICE
    fi

    if [ "$VIRTUALBOX" == "true" ]; then
        echo -n "\EFI\grub\grubx64.efi" > /mnt/boot/startup.nsh
    fi

    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

function user() {
    arch-chroot /mnt useradd -m -g users -G audio,lp,optical,storage,video,wheel,games,power,scanner -s /bin/bash $USER_NAME
    printf "$USER_PASSWORD\n$USER_PASSWORD" | arch-chroot /mnt passwd $USER_NAME
    arch-chroot /mnt pacman -Sy sudo
    sed -i 's/#%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
}

function desktop_environment() {
    case "$DISPLAY_DRIVER" in
        "xf86-video-intel" )
            MESA_LIBGL="mesa-libgl"
            ;;
        "xf86-video-ati" )
            MESA_LIBGL="mesa-libgl"
            ;;
        "xf86-video-amdgpu" )
            MESA_LIBGL="mesa-libgl"
            ;;
        "xf86-video-nouveau" )
            MESA_LIBGL="mesa-libgl"
            ;;
        "nvidia" )
            MESA_LIBGL="nvidia-libgl"
            ;;
        "nvidia-340xx" )
            MESA_LIBGL="nvidia-340xx-libgl"
            ;;
        "nvidia-304xx" )
            MESA_LIBGL="nvidia-304xx-libgl"
            ;;
        * )
            MESA_LIBGL="mesa-libgl"
            ;;
    esac

    arch-chroot /mnt pacman -Sy --noconfirm xorg-server xorg-server-utils xorg-apps $DISPLAY_DRIVER mesa $MESA_LIBGL ttf-dejavu  ttf-droid  ttf-inconsolata

    case "$DESKTOP_ENVIRONMENT" in
        "gnome" )
            desktop_environment_gnome
            ;;
        "kde" )
            desktop_environment_kde
            ;;
        "xfce" )
            desktop_environment_xfce
            ;;
        "mate" )
            desktop_environment_mate
            ;;
        "cinnamon" )
            desktop_environment_cinnamon
            ;;
        "lxde" )
            desktop_environment_lxde
            ;;
        "budgie" )
            desktop_environment_budgie
            ;;
    esac
}

function desktop_environment_gnome() {
    arch-chroot /mnt pacman -Sy --noconfirm gnome gnome-extra
    arch-chroot /mnt systemctl enable gdm.service
}
function desktop_environment_budgie() {
    arch-chroot /mnt pacman -Sy --noconfirm budgie-desktop gdm gnome-themes-standard gnome-session gnome-shell-extensions gnome-backgrounds gnome-calculator gnome-control-center gnome-screenshot gnome-system-monitor gnome-terminal gnome-tweak-tool nautilus noise vala viewnior file-roller
    arch-chroot /mnt systemctl enable gdm.service
}

function desktop_environment_kde() {
    arch-chroot /mnt pacman -Sy --noconfirm plasma-meta kde-applications-meta
    arch-chroot /mnt sed -i 's/Current=.*/Current=breeze/' /etc/sddm.conf
    arch-chroot /mnt systemctl enable sddm.service
}

function desktop_environment_xfce() {
    arch-chroot /mnt pacman -Sy --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
    arch-chroot /mnt systemctl enable lightdm.service
}

function desktop_environment_mate() {
    arch-chroot /mnt pacman -Sy --noconfirm mate mate-extra lightdm lightdm-gtk-greeter
    arch-chroot /mnt systemctl enable lightdm.service
}

function desktop_environment_cinnamon() {
    arch-chroot /mnt pacman -Sy --noconfirm cinnamon lightdm lightdm-gtk-greeter
    arch-chroot /mnt systemctl enable lightdm.service
}

function desktop_environment_lxde() {
    arch-chroot /mnt pacman -Sy --noconfirm lxde lxdm
    arch-chroot /mnt systemctl enable lxdm.service
}

function end() {
    umount -R /mnt
    reboot
}

function main() {
    configuration_install
    check_variables
    warning
    init
    facts
    network_install
    partition
    install
    kernels
    configuration
    network
    if [ "$VIRTUALBOX" == "true" ]; then
        virtualbox
    fi
    packages
    user
    mkinitcpio
    bootloader
    if [ "$DESKTOP_ENVIRONMENT" != "" ]; then
        desktop_environment
    fi
    if [ "$REBOOT" == "true" ]; then
        end
    fi
}

main
