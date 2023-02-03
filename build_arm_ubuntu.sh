#!/bin/bash

# WSL第一次打开终端，需要先执行sudo service binfmt-support start

SUDO_CMD=sudo
CUR_DIR=${PWD}

SOFTWARE_SOURCE=http://mirrors.ustc.edu.cn

# bionic focal jammy kinetic trusty xenial
UBUNTU_NAME=jammy
UBUNTU_VERSION=22.04.1
UBUNTU_TARPKT_NAME=ubuntu-base-${UBUNTU_VERSION}-base-armhf.tar.gz
UBUNTU_BASE_URL=${SOFTWARE_SOURCE}/ubuntu-cdimage/ubuntu-base/releases/${UBUNTU_NAME}/release/${UBUNTU_TARPKT_NAME}
REMOTE_UBUNTU_BASE_FILESIZE=`curl -sI ${UBUNTU_BASE_URL} | grep -i content-length | awk '{print $2}'`

HOSTNAME=imx6ull
SAMBA_USER=root
NEW_USERNAME=${UBUNTU_NAME}
ROOTFS_NAME=${CUR_DIR}/rootfs

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
    echo "mount starting"
    ${SUDO_CMD} mount -t proc /proc ${ROOTFS_NAME}/proc
    ${SUDO_CMD} mount -t sysfs /sysfs ${ROOTFS_NAME}/sys
    ${SUDO_CMD} mount -o bind /dev ${ROOTFS_NAME}/dev
    ${SUDO_CMD} mount -o bind /dev/pts ${ROOTFS_NAME}/dev/pts
    ${SUDO_CMD} mount -o bind /tmp ${ROOTFS_NAME}/tmp
    echo "mount finished"
}

function umount_point()
{
    echo "umount starting"
    ${SUDO_CMD} umount ${ROOTFS_NAME}/proc   
    ${SUDO_CMD} umount ${ROOTFS_NAME}/sys
    ${SUDO_CMD} umount ${ROOTFS_NAME}/dev/pts
    ${SUDO_CMD} umount ${ROOTFS_NAME}/dev
    ${SUDO_CMD} umount ${ROOTFS_NAME}/tmp
    echo "umount finished"
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

function ubuntu()
{
    if [ -d "${ROOTFS_NAME}" ]; then
        rm -rf ${ROOTFS_NAME}
    fi

    mkdir -p ${ROOTFS_NAME}

    if [ ! -f "${UBUNTU_TARPKT_NAME}" ]; then
        echo "开始下载${UBUNTU_TARPKT_NAME}"
        wget ${UBUNTU_BASE_URL}
        if [ $? -ne 0 ]; then
            echo "下载${UBUNTU_TARPKT_NAME}失败"
            exit 127
        fi
        echo "下载${UBUNTU_TARPKT_NAME}完成"
    fi

    filesize=`ls -l ${CUR_DIR}/${UBUNTU_TARPKT_NAME} | awk '{print $5}'`
    if [ ! -f "${CUR_DIR}/${UBUNTU_TARPKT_NAME}" ] || [ $filesize -ne $REMOTE_UBUNTU_BASE_FILESIZE ]; then
        if [ ! -f "${CUR_DIR}/${UBUNTU_TARPKT_NAME}" ]; then
            echo "${CUR_DIR}/${UBUNTU_TARPKT_NAME}不存在，可能未下载成功"
        else
            echo "下载下来的${UBUNTU_TARPKT_NAME}大小不合法，期望大小: $REMOTE_UBUNTU_BASE_FILESIZE字节，实际大小: $filesize字节"
        fi

        exit 127
    else
        echo "下载下来的${UBUNTU_TARPKT_NAME}大小: $filesize字节, 期望大小: $REMOTE_UBUNTU_BASE_FILESIZE字节"
    fi

    echo "开始解压缩${UBUNTU_TARPKT_NAME}到${ROOTFS_NAME}"
    tar -xvf ${UBUNTU_TARPKT_NAME} -C ${ROOTFS_NAME}
    if [ $? -ne 0 ]; then
        echo "解压缩${UBUNTU_TARPKT_NAME}失败"
        exit 127
    fi
    echo "解压缩${UBUNTU_TARPKT_NAME}到${ROOTFS_NAME}完成"

    if [ ! -f "/usr/bin/qemu-arm-static" ]; then
        echo "/usr/bin/qemu-arm-static不存在，请先安装"
        exit 127
    else
        ${SUDO_CMD} cp /usr/bin/qemu-arm-static ${ROOTFS_NAME}/usr/bin 
    fi

    # ${SUDO_CMD} cp -rf /etc/resolv.conf ${ROOTFS_NAME}/etc/
    ${SUDO_CMD} echo "nameserver 8.8.8.8" > ${ROOTFS_NAME}/etc/resolv.conf
    ${SUDO_CMD} echo "nameserver 114.114.114.114" >> ${ROOTFS_NAME}/etc/resolv.conf

cat > ${CUR_DIR}/operate.sh <<EOF
#!/bin/sh
mv /etc/apt/sources.list /etc/apt/sources_back.list
echo "deb ${SOFTWARE_SOURCE}/ubuntu-ports/ ${UBUNTU_NAME} main multiverse restricted universe" > /etc/apt/sources.list
echo "deb ${SOFTWARE_SOURCE}/ubuntu-ports/ ${UBUNTU_NAME}-backports main multiverse restricted universe" >> /etc/apt/sources.list
echo "deb ${SOFTWARE_SOURCE}/ubuntu-ports/ ${UBUNTU_NAME}-proposed main multiverse restricted universe" >> /etc/apt/sources.list
echo "deb ${SOFTWARE_SOURCE}/ubuntu-ports/ ${UBUNTU_NAME}-security main multiverse restricted universe" >> /etc/apt/sources.list
echo "deb ${SOFTWARE_SOURCE}/ubuntu-ports/ ${UBUNTU_NAME}-updates main multiverse restricted universe" >> /etc/apt/sources.list
echo "deb-src ${SOFTWARE_SOURCE}/ubuntu-ports/ ${UBUNTU_NAME} main multiverse restricted universe" >> /etc/apt/sources.list
echo "deb-src ${SOFTWARE_SOURCE}/ubuntu-ports/ ${UBUNTU_NAME}-backports main multiverse restricted universe" >> /etc/apt/sources.list
echo "deb-src ${SOFTWARE_SOURCE}/ubuntu-ports/ ${UBUNTU_NAME}-proposed main multiverse restricted universe" >> /etc/apt/sources.list
echo "deb-src ${SOFTWARE_SOURCE}/ubuntu-ports/ ${UBUNTU_NAME}-security main multiverse restricted universe" >> /etc/apt/sources.list
echo "deb-src ${SOFTWARE_SOURCE}/ubuntu-ports/ ${UBUNTU_NAME}-updates main multiverse restricted universe" >> /etc/apt/sources.list

chmod 777 /tmp/
apt update

apt install apt-transport-https ca-certificates -y
apt install sudo vim kmod lsof -y
apt install net-tools ethtool ifupdown -y
apt install language-pack-en-base rsyslog -y
apt install nfs-common samba samba-common openssh-server -y
apt install ufw htop iputils-ping network-manager -y
apt install dosfstools systemd ntp rfkill wpasupplicant -y
apt install gcc g++ -y
# apt install xubuntu-desktop -y

echo "${HOSTNAME}" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts

sed -i 's/#DNS=/DNS=8.8.8.8 114.114.114.114/' /etc/systemd/resolved.conf
sed -i 's/TimeoutStartSec=5min/TimeoutStartSec=3sec/' /lib/systemd/system/networking.service
sed -i 's/TimeoutStartSec=5min/TimeoutStartSec=3sec/' /etc/systemd/system/network-online.target.wants/networking.service

ln -s /lib/systemd/system/getty@.service /etc/systemd/system/getty.target.wants/getty@ttymxc0.service

# sed -i '/# the entered username./{n;s/-\/sbin\/agetty/-\/sbin\/agetty -a root/;}' /etc/systemd/system/getty.target.wants/getty@tty1.service

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
EOF
    if [ -f "${CUR_DIR}/all.sh" ]; then
        ${SUDO_CMD} mv ${CUR_DIR}/all.sh ${ROOTFS_NAME}
    fi

    echo "开始自动化设置参数 ......"
	
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

    echo "恭喜您，Ubuntu ${UBUNTU_NAME}构建完成"

    sleep 3
}

function setup()
{
    if [ ! -f "/usr/bin/qemu-arm-static" ]; then
        echo "/usr/bin/qemu-arm-static不存在，请先安装"
        exit 127
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

    echo "切换到构建的ubuntu根目录，切换后可以安装需要的软件以及继续其他操作，完成后，执行exit推出"
    mount_point
    ${SUDO_CMD} chroot ${ROOTFS_NAME}
    umount_point

    cache_clean

    echo "恭喜您，用户自定义设置完成"

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

    if [ -f "${CUR_DIR}/all.sh" ]; then
        rm -rf ${CUR_DIR}/all.sh
    fi

    if [ -f "${CUR_DIR}/rootfs.tar.bz2" ]; then
        ${SUDO_CMD} rm -rf ${CUR_DIR}/rootfs.tar.bz2
    fi

    if [ -f "${CUR_DIR}/${UBUNTU_TARPKT_NAME}" ]; then
        rm -rf  ${CUR_DIR}/${UBUNTU_TARPKT_NAME}
    fi
}

function all()
{
    clean
    ubuntu
    setup
    rootfs
}

function help()
{
    echo "Usage: $0 [OPTION]"
    echo "[OPTION]:"
    echo "==============================="
    echo "  0  clean    清理构建信息"
    echo "  1  host_dep 安装主机环境"
    echo "  2  ubuntu   开始构建ubuntu"
    echo "  3  rootfs   打包ubuntu镜像"
    echo "  4  all      执行2-3的操作"
    echo "==============================="
}

if [ -z $1 ]; then
    help
else
    $1
fi
