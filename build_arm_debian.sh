#!/bin/bash

SUDO_CMD=sudo
CUR_DIR=${PWD}
source ${CUR_DIR}/buildFuncDefine.sh

# bookworm bullseye buster jessie stretch
DEBIAN_NAME=bookworm
ROOTFS_NAME=${PWD}/rootfs
SOFTWARE_SOURCE=http://mirrors.ustc.edu.cn/debian/

HOSTNAME=imx6ull
SAMBA_USER=root
NEW_USERNAME=${DEBIAN_NAME}

TIMEZONE=Asia/Shanghai

NETCARD0_NAME=eth0
NETCARD0_MODE=static
NETCARD0_IPADDR=192.168.1.100
NETCARD0_NETMASK=255.255.255.0
NETCARD0_GATEWAY=192.168.1.1
NETCARD0_BOARDCAST=192.168.1.255

NETCARD1_NAME=eth1
NETCARD1_MODE=static
NETCARD1_IPADDR=192.168.1.101
NETCARD1_NETMASK=255.255.255.0
NETCARD1_GATEWAY=192.168.1.1
NETCARD1_BOARDCAST=192.168.1.255

function host_dep()
{
    sudo apt update
    sudo apt-get install qemu-user-static qemu-system-arm debootstrap multistrap -y
    sudo update-binfmts --install i386 /usr/bin/qemu-i386-static --magic '\x7fELF\x01\x01\x01\x03\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\x03\x00\x01\x00\x00\x00' --mask '\xff\xff\xff\xff\xff\xff\xff\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xf8\xff\xff\xff\xff\xff\xff\xff'
    sudo service binfmt-support start
    sudo dpkg --add-architecture i386 -y
    sudo apt update
    sudo apt-get install libc6:i386 libncurses5:i386 libstdc++6:i386 -y
}

function mount_point()
{
    print_info "mount starting"
    ${SUDO_CMD} mount -t proc /proc ${ROOTFS_NAME}/proc
    ${SUDO_CMD} mount -t sysfs /sys ${ROOTFS_NAME}/sys
    ${SUDO_CMD} mount -o bind /dev ${ROOTFS_NAME}/dev
    ${SUDO_CMD} mount -o bind /dev/pts ${ROOTFS_NAME}/dev/pts
    ${SUDO_CMD} mount -o bind /tmp ${ROOTFS_NAME}/tmp
    print_info "mount finished"
}

function umount_point()
{
    print_info "umount starting"
    ${SUDO_CMD} umount ${ROOTFS_NAME}/sys
    ${SUDO_CMD} umount ${ROOTFS_NAME}/proc   
    ${SUDO_CMD} umount ${ROOTFS_NAME}/dev/pts
    ${SUDO_CMD} umount ${ROOTFS_NAME}/dev
    ${SUDO_CMD} umount ${ROOTFS_NAME}/tmp
    print_info "umount finished"
}

function cache_clean()
{
    if [ -f "${ROOTFS_NAME}/usr/bin/qemu-arm-static" ]; then
        ${SUDO_CMD} rm -rf ${ROOTFS_NAME}/usr/bin/qemu-arm-static
    fi

    ${SUDO_CMD} rm -rf ${ROOTFS_NAME}/var/lib/lists/*
    ${SUDO_CMD} rm -rf ${ROOTFS_NAME}/dev/*
    ${SUDO_CMD} rm -rf ${ROOTFS_NAME}/var/log/*
    ${SUDO_CMD} rm -rf ${ROOTFS_NAME}/var/tmp/*
    ${SUDO_CMD} rm -rf ${ROOTFS_NAME}/var/cache/apt/archives/*.deb
    ${SUDO_CMD} rm -rf ${ROOTFS_NAME}/tmp/*
}

function debian()
{
    sudo service binfmt-support start

    print_info "开始构建Debian ${DEBIAN_NAME}的第一阶段"
    ${SUDO_CMD} debootstrap --arch=armhf --foreign --verbose ${DEBIAN_NAME} ${ROOTFS_NAME}/ ${SOFTWARE_SOURCE}
    if [ $? -ne 0 ]; then
        error_exit "构建第一阶段失败"
    fi
    print_info "完成构建Debian ${DEBIAN_NAME}的第一阶段"

    if [ -f "/usr/bin/qemu-arm-static" ]; then
        ${SUDO_CMD} cp /usr/bin/qemu-arm-static ${ROOTFS_NAME}/usr/bin
    fi

    print_info "开始构建Debian ${DEBIAN_NAME}的第二阶段"
    ${SUDO_CMD} DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS_NAME}/ debootstrap/debootstrap --second-stage
    if [ $? -ne 0 ]; then
        error_exit "构建第二阶段失败"
    fi
    print_info "完成构建Debian ${DEBIAN_NAME}的第二阶段"

cat > ${CUR_DIR}/operate.sh <<EOF
#/bin/sh

echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 114.114.114.114" >> /etc/resolv.conf

sed -i 's/#DNS=/DNS=8.8.8.8 114.114.114.114/' /etc/systemd/resolved.conf
sed -i 's/TimeoutStartSec=5min/TimeoutStartSec=3sec/' /lib/systemd/system/networking.service
sed -i 's/TimeoutStartSec=5min/TimeoutStartSec=3sec/' /etc/systemd/system/network-online.target.wants/networking.service

echo "deb ${SOFTWARE_SOURCE} ${DEBIAN_NAME} main contrib non-free" > /etc/apt/sources.list
echo "deb ${SOFTWARE_SOURCE} ${DEBIAN_NAME}-updates contrib non-free" >> /etc/apt/sources.list
echo "deb ${SOFTWARE_SOURCE} ${DEBIAN_NAME}-backports main contrib non-free" >> /etc/apt/sources.list
echo "deb-src ${SOFTWARE_SOURCE} ${DEBIAN_NAME} main contrib non-free" >> /etc/apt/sources.list 
echo "deb-src ${SOFTWARE_SOURCE} ${DEBIAN_NAME}-updates main contrib non-free" >> /etc/apt/sources.list
echo "deb-src ${SOFTWARE_SOURCE} ${DEBIAN_NAME}-backports main contrib non-free" >> /etc/apt/sources.list 

apt-get update

export TZ=Asia/Shanghai
export DEBIAN_FRONTEND=noninteractive
apt install tzdata -y

apt-get install apt-transport-https ca-certificates -y
apt-get install sudo vim language-pack-en-base gpiod i2c-tools -y
apt-get install net-tools wireless-tools ethtool ifupdown iputils-ping -y
apt-get install rsyslog htop samba samba-common nfs-common openssh-server ssh -y
apt-get install wpasupplicant lsof kmod dosfstools systemd -y
apt-get install ufw gcc g++ -y

echo "${HOSTNAME}" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts

ln -s /lib/systemd/system/getty@.service /etc/systemd/system/getty.target.wants/getty@ttymxc0.service

sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

if [ ! -d "/public" ]; then
    mkdir /public
    chmod 777 /public
fi

echo "[$HOSTNAME]" >> /etc/samba/smb.conf
echo "   comment = ${HOSTNAME} samba server" >> /etc/samba/smb.conf
echo "   path = /public" >> /etc/samba/smb.conf
echo "   browseable = yes" >> /etc/samba/smb.conf
echo "   guest ok = yes" >> /etc/samba/smb.conf
echo "   public = yes" >> /etc/samba/smb.conf
echo "   read only = no" >> /etc/samba/smb.conf
echo "   writeable = yes" >> /etc/samba/smb.conf
echo "   available = yes" >> /etc/samba/smb.conf
EOF
    if [ -f "${CUR_DIR}/operate.sh" ]; then
        ${SUDO_CMD} mv ${CUR_DIR}/operate.sh ${ROOTFS_NAME}
    fi

cat > ${CUR_DIR}/operate2.sh <<EOF
#!/bin/sh

echo "proc  /proc   proc    defaults    0   0" >> /etc/fstab
echo "sysfs /sys    sysfs   defaults    0   0" >> /etc/fstab
echo "tmpfs /tmp    tmpfs   defaults    0   0" >> /etc/fstab

echo "auto ${NETCARD0_NAME}" >> /etc/network/interfaces.d/${NETCARD0_NAME}
echo "iface ${NETCARD0_NAME} inet ${NETCARD0_MODE}" >> /etc/network/interfaces.d/${NETCARD0_NAME}
echo "address ${NETCARD0_IPADDR}" >> /etc/network/interfaces.d/${NETCARD0_NAME}
echo "netmask ${NETCARD0_NETMASK}" >> /etc/network/interfaces.d/${NETCARD0_NAME}
echo "gateway ${NETCARD0_GATEWAY}" >> /etc/network/interfaces.d/${NETCARD0_NAME}
echo "boardcast ${NETCARD0_BOARDCAST}" >> /etc/network/interfaces.d/${NETCARD0_NAME}

echo "auto ${NETCARD1_NAME}" >> /etc/network/interfaces.d/${NETCARD1_NAME}
echo "iface ${NETCARD1_NAME} inet ${NETCARD1_MODE}" >> /etc/network/interfaces.d/${NETCARD1_NAME}
echo "address ${NETCARD1_IPADDR}" >> /etc/network/interfaces.d/${NETCARD1_NAME}
echo "netmask ${NETCARD1_NETMASK}" >> /etc/network/interfaces.d/${NETCARD1_NAME}
echo "gateway ${NETCARD1_GATEWAY}" >> /etc/network/interfaces.d/${NETCARD1_NAME}
echo "boardcast ${NETCARD1_BOARDCAST}" >> /etc/network/interfaces.d/${NETCARD1_NAME}
EOF
    if [ -f "${CUR_DIR}/operate2.sh" ]; then
        ${SUDO_CMD} mv ${CUR_DIR}/operate2.sh ${ROOTFS_NAME}
    fi

cat > ${CUR_DIR}/operate3.sh <<EOF
#!/bin/sh

cd /etc
rm -rf localtime
ln -s ../usr/share/zoneinfo/${TIMEZONE} localtime
cd -
EOF
    if [ -f "${CUR_DIR}/operate3.sh" ]; then
        ${SUDO_CMD} mv ${CUR_DIR}/operate3.sh ${ROOTFS_NAME}
    fi

cat > ${CUR_DIR}/cardmnt.sh <<EOF
echo "mmcblk[1-9]p[0-9] 0:0 666 @/etc/hotplug/tfcard_insert" > /etc/mdev.conf
echo "mmcblk[1-9] 0:0 666 \$/etc/hotplug/tfcard_remove\n" >> /etc/mdev.conf

echo "sd[a-z][0-9] 0:0 666 @/etc/hotplug/udisk_insert" >> /etc/mdev.conf
echo "sd[a-z] 0:0 666 \$/etc/hotplug/udisk_remove" >> /etc/mdev.conf

if [ ! -d "/etc/hotplug" ]; then
    mkdir -p /etc/hotplug
fi

STR='MDEV'

echo '#!/bin/sh' > /etc/hotplug/tfcard_insert
echo "echo 'tfcard insertion detected' > /dev/console" >> /etc/hotplug/tfcard_insert
echo "if [ -e \"/dev/\\$\$STR\" ]; then" >> /etc/hotplug/tfcard_insert
echo "\tmount -o rw /dev/\\$\$STR /sdcard/" >> /etc/hotplug/tfcard_insert
echo "fi" >> /etc/hotplug/tfcard_insert
chmod 777 /etc/hotplug/tfcard_insert

echo '#!/bin/sh' > /etc/hotplug/tfcard_remove
echo "echo 'tfcard removal detected' > /dev/console" >> /etc/hotplug/tfcard_remove
echo "umount -l /sdcard/" >> /etc/hotplug/tfcard_remove
echo "rm -rf /sdcard/*" >> /etc/hotplug/tfcard_remove
chmod 777 /etc/hotplug/tfcard_remove

echo '#!/bin/sh' > /etc/hotplug/udisk_insert
echo "if [ -e \"/dev/\\$\$STR\" ]; then" >> /etc/hotplug/udisk_insert
echo "\tmount -o rw /dev/\\$\$STR /udisk/" >> /etc/hotplug/udisk_insert
echo "fi" >> /etc/hotplug/udisk_insert
chmod 777 /etc/hotplug/udisk_insert

echo '#!/bin/sh' > /etc/hotplug/udisk_remove
echo "echo 'udisk removal detected' > /dev/console" >> /etc/hotplug/udisk_remove
echo "umount -l /udisk/*" >> /etc/hotplug/udisk_remove
echo "rm -rf /udisk/*" >> /etc/hotplug/udisk_remove
chmod 777 /etc/hotplug/udisk_remove
EOF
    if [ -f "${CUR_DIR}/cardmnt.sh" ]; then
        ${SUDO_CMD} mv ${CUR_DIR}/cardmnt.sh ${ROOTFS_NAME}
    fi

cat > ${CUR_DIR}/all.sh <<EOF
#!/bin/sh

if [ -f "/operate.sh" ]; then
    chmod a+x /operate.sh
    /bin/sh /operate.sh
    rm -rf /operate.sh
fi

if [ -f "/operate2.sh" ]; then
    chmod a+x /operate2.sh
    /bin/sh /operate2.sh
    rm -rf /operate2.sh
fi

if [ -f "/operate3.sh" ]; then
    chmod a+x /operate3.sh
    /bin/sh /operate3.sh
    rm -rf /operate3.sh
fi

if [ ! -d "/mnt/sdcard" ]; then
    mkdir -p /mnt/sdcard
fi
ln -s /mnt/sdcard /sdcard

if [ ! -d "/media/usb0" ]; then
    mkdir -p /media/usb0
fi
ln -s /media/usb0 /udisk

if [ -f "/cardmnt.sh" ]; then
    chmod a+x /cardmnt.sh
    /bin/sh /cardmnt.sh
    rm -rf /cardmnt.sh
fi

cd /etc
rm -rf localtime
ln -s ../usr/share/zoneinfo/${TIMEZONE} localtime
cd -
EOF
    if [ -f "${CUR_DIR}/all.sh" ]; then
        ${SUDO_CMD} mv ${CUR_DIR}/all.sh ${ROOTFS_NAME}
    fi

    print_info "开始自动化设置参数 ......"

    sleep 3

    mount_point
cat << EOF | ${SUDO_CMD} LC_ALL=C chroot ${ROOTFS_NAME} /bin/sh
if [ -f "/all.sh" ]; then
    chmod a+x /all.sh
    /bin/sh /all.sh
    rm -rf /all.sh
fi
EOF
    umount_point
    cache_clean

    print_info "恭喜您，Debian ${DEBIAN_NAME}构建完成"

    sleep 3
}

function setup()
{
    if [ ! -f "/usr/bin/qemu-arm-static" ]; then
        error_exit "/usr/bin/qemu-arm-static不存在，请先安装"
    else
        ${SUDO_CMD} cp /usr/bin/qemu-arm-static ${ROOTFS_NAME}/usr/bin 
    fi

cat > ${CUR_DIR}/setup.sh <<EOF
#!/bin/sh
echo "添加新用户开始 ${NEW_USERNAME} ......"
useradd -s '/bin/bash' -m -G adm,sudo ${NEW_USERNAME}
echo "添加新用户${NEW_USERNAME}完成"

echo "开始给新用户${NEW_USERNAME}设置密码"
passwd ${NEW_USERNAME}
echo "新用户${NEW_USERNAME}密码设置完成"

echo "开始给root用户设置密码"
passwd root
echo "root用户密码设置完成"

ufw disable
echo "添加samba用户${SAMBA_USER}，要求您输入密码"
smbpasswd -a ${SAMBA_USER}
EOF
    if [ -f "${CUR_DIR}/setup.sh" ]; then
        ${SUDO_CMD} mv ${CUR_DIR}/setup.sh ${ROOTFS_NAME}
        ${SUDO_CMD} chmod a+x ${ROOTFS_NAME}/setup.sh
    fi

    print_info "切换到构建的debian根目录，切换后可以安装需要的软件以及继续其他操作，完成后，执行exit推出"
    mount_point
    ${SUDO_CMD} chroot ${ROOTFS_NAME}
    if [ -f "${ROOTFS_NAME}/setup.sh" ]; then
        ${SUDO_CMD} rm -rf ${ROOTFS_NAME}/setup.sh
    fi
    umount_point

    cache_clean

    print_info "恭喜您，用户自定义设置完成"

    sleep 3
}

function rootfs()
{
    if [ -d "${ROOTFS_NAME}" ]; then
        cache_clean

        cd ${ROOTFS_NAME}
        ${SUDO_CMD} tar -jcvf rootfs.tar.bz2 *
        ${SUDO_CMD} mv ${ROOTFS_NAME}/rootfs.tar.bz2 ${CUR_DIR}
        cd ${CUR_DIR}

        ${SUDO_CMD} du -h -d 0 ${ROOTFS_NAME}
        ${SUDO_CMD} ls -l -h ${CUR_DIR}/rootfs.tar.bz2
    fi
}

function clean()
{
    if [ -d "${ROOTFS_NAME}" ]; then
        ${SUDO_CMD} rm -rf ${ROOTFS_NAME}
    fi

    if [ -f "${CUR_DIR}/operate.sh" ]; then
        rm -rf ${CUR_DIR}/operate.sh
    fi

    if [ -f "${CUR_DIR}/operate2.sh" ]; then
        rm -rf ${CUR_DIR}/operate2.sh
    fi

    if [ -f "${CUR_DIR}/all.sh" ]; then
        rm -rf ${CUR_DIR}/all.sh
    fi

    if [ -f "${CUR_DIR}/rootfs.tar.bz2" ]; then
        ${SUDO_CMD} rm -rf ${CUR_DIR}/rootfs.tar.bz2
    fi
}

function all()
{
    clean

    print_debian_logo

    debian
    setup
    rootfs
}

function help()
{
    print_debian_logo
    echo "Usage: $0 [OPTION]"
    echo "[OPTION]"
    echo "===================================="
    echo "  0  clean    清理构建信息"
    echo "  1  host_dep 安装主机环境"
    echo "  2  debian   开始构建debian"
    echo "  3  rootfs   打包debian镜像"
    echo "  4  all      执行2-3的操作"
    echo "===================================="
}

if [ -z $1 ]; then
    help
else
    $1
fi
