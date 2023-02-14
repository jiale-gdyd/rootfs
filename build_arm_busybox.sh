#!/bin/bash

SUDO_CMD=

# arm linaro
CROSS_TOOLCHAIN_VENDOR=linaro

CROSS_TOOLCHAIN_YEAR=2022
CROSS_TOOLCHAIN_MONTH=08

CROSS_TOOLCHAIN_GCC_MAJOR=12
CROSS_TOOLCHAIN_GCC_MINOR=1
CROSS_TOOLCHAIN_GCC_PATCH=1

CROSS_TOOLCHAIN_PATH=
CROSS_TOOLCHAIN_PREFIX=
CROSS_TOOLCHAIN_SUBFIX=

if [ "$CROSS_TOOLCHAIN_VENDOR" = "arm" ]; then
    CROSS_TOOLCHAIN_PREFIX=arm-none-linux-gnueabihf
    CROSS_TOOLCHAIN_SUBFIX=/opt/toolchain/gcc-arm-${CROSS_TOOLCHAIN_GCC_MAJOR}.${CROSS_TOOLCHAIN_GCC_MINOR}-${CROSS_TOOLCHAIN_YEAR}.${CROSS_TOOLCHAIN_MONTH}-x86_64
    CROSS_TOOLCHAIN_PATH=${CROSS_TOOLCHAIN_SUBFIX}-${CROSS_TOOLCHAIN_PREFIX}
else
    CROSS_TOOLCHAIN_PREFIX=arm-linux-gnueabihf
    CROSS_TOOLCHAIN_SUBFIX=/opt/toolchain/gcc-linaro-${CROSS_TOOLCHAIN_GCC_MAJOR}.${CROSS_TOOLCHAIN_GCC_MINOR}.${CROSS_TOOLCHAIN_GCC_PATCH}-${CROSS_TOOLCHAIN_YEAR}.${CROSS_TOOLCHAIN_MONTH}-x86_64
    CROSS_TOOLCHAIN_PATH=${CROSS_TOOLCHAIN_SUBFIX}_${CROSS_TOOLCHAIN_PREFIX}
fi

HOSTNAME=imx6ull
HOME_PATH=root
NEW_USERNAME=aure
DEFAULT_GATEWAY=192.168.1.1

CUR_DIR=${PWD}
ROOTFS_NAME=${CUR_DIR}/rootfs

BUSYBOX_VERSION=1.36.0
BUSYBOX_SOURCE=busybox-${BUSYBOX_VERSION}
BUSYBOX_TARPKT_NAME=${BUSYBOX_SOURCE}.tar.bz2
BUSYBOX_TARPKT_URL=https://busybox.net/downloads/${BUSYBOX_TARPKT_NAME}

function patch()
{
    sed -i 's/CROSS_COMPILE ?=/CROSS_COMPILE ?= $(CONFIG_CROSS_COMPILE:"%s"=%)/' ${CUR_DIR}/${BUSYBOX_SOURCE}/Makefile 
    sed -i '/:= $(CFLAGS)/a\CFLAGS		+= -Wno-unused-result -Wno-format-truncation -Wno-return-local-addr -Wno-array-bounds -Wno-format-overflow -Wno-maybe-uninitialized' ${CUR_DIR}/${BUSYBOX_SOURCE}/Makefile
    sed -i '/:= $(CFLAGS_busybox)/a\CFLAGS_busybox		+= -Wno-unused-result' ${CUR_DIR}/${BUSYBOX_SOURCE}/Makefile

    sed -i '/if (c >= 0x7f)/{n;s/break;/break;*\//}' ${CUR_DIR}/${BUSYBOX_SOURCE}/libbb/printable_string.c
    sed -i 's/if (c >= 0x7f)/\/*if (c >= 0x7f)/' ${CUR_DIR}/${BUSYBOX_SOURCE}/libbb/printable_string.c
    sed -i "s/if (c < ' ' || c >= 0x7f)/if (c < ' ')/" ${CUR_DIR}/${BUSYBOX_SOURCE}/libbb/printable_string.c

    sed -i "s/*d++ = (c >= ' ' && c < 0x7f) ? c : '?';/*d++ = (c >= ' ') ? c : '?';/" ${CUR_DIR}/${BUSYBOX_SOURCE}/libbb/unicode.c
    sed -i "s/if (c < ' ' || c >= 0x7f)/if (c < ' ')/" ${CUR_DIR}/${BUSYBOX_SOURCE}/libbb/unicode.c

    sed -i '/Simplified modutils/{n;s#y#n#;}' ${CUR_DIR}/${BUSYBOX_SOURCE}/modutils/Config.src
    sed -i '/vi-style line editing commands/{n;s#n#y#;}' ${CUR_DIR}/${BUSYBOX_SOURCE}/libbb/Config.src
    sed -i '/Check $LC_ALL, $LC_CTYPE and $LANG environment variables/{n;s#n#y#;}' ${CUR_DIR}/${BUSYBOX_SOURCE}/libbb/Config.src
}

function busybox()
{
    if [ ! -f "${CUR_DIR}/${BUSYBOX_TARPKT_NAME}" ]; then
        echo "开始下载${BUSYBOX_TARPKT_NAME}"
        wget ${BUSYBOX_TARPKT_URL}
        if [ $? -ne 0 ]; then
            echo "下载${BUSYBOX_TARPKT_NAME}失败"
            exit 127
        fi
    fi

    REMOTE_BUSYBOX_FILESIZE=`curl -sI ${BUSYBOX_TARPKT_URL} | grep -i content-length | awk '{print $2}'`
    filesize=`ls -l ${CUR_DIR}/${BUSYBOX_TARPKT_NAME} | awk '{print $5}'`
    if [ ! -f "${CUR_DIR}/${BUSYBOX_TARPKT_NAME}" ] || [ $filesize -ne $REMOTE_BUSYBOX_FILESIZE ]; then
        if [ ! -f "${CUR_DIR}/${BUSYBOX_TARPKT_NAME}" ]; then
            echo "${CUR_DIR}/${BUSYBOX_TARPKT_NAME}不存在，可能未下载成功"
        else
            echo "下载的${CUR_DIR}/${BUSYBOX_TARPKT_NAME}文件大小不对，期望大小: $REMOTE_BUSYBOX_FILESIZE字节，实际大小: $filesize字节"
        fi

        exit 127
    else
        echo "下载下来的${BUSYBOX_TARPKT_NAME}大小: $filesize字节, 远程中大小: $REMOTE_BUSYBOX_FILESIZE字节"
    fi

    echo "开始解压缩${BUSYBOX_TARPKT_NAME}"
    tar -jxvf ${CUR_DIR}/${BUSYBOX_TARPKT_NAME}
    if [ $? -ne 0 ]; then
        echo "解压缩${BUSYBOX_TARPKT_NAME}失败"
        exit 127
    fi
    echo "解压缩${BUSYBOX_TARPKT_NAME}完成"

    echo "开始给${BUSYBOX_SOURCE}添加补丁"
    patch
    echo "向${BUSYBOX_SOURCE}添加补丁完成"

    echo "开始构建${BUSYBOX_SOURCE}"
    cd ${CUR_DIR}/${BUSYBOX_SOURCE}
    
    export ARCH=arm
    export CROSS_COMPILE=${CROSS_TOOLCHAIN_PATH}/bin/${CROSS_TOOLCHAIN_PREFIX}-
    
    make menuconfig
    if [ $? -ne 0 ]; then
        echo "make menuconfig失败"
        exit 127
    fi
    
    make
    if [ $? -ne 0 ]; then
        echo "构建${BUSYBOX_SOURCE}失败"
        ${SUDO_CMD} rm -rf ${CUR_DIR}/${BUSYBOX_SOURCE}
        exit 127
    fi
    
    if [ ! -d "${ROOTFS_NAME}" ]; then
        mkdir -p ${ROOTFS_NAME}
    fi
    
    make install CONFIG_PREFIX=${ROOTFS_NAME}
    if [ $? -ne 0 ]; then
        echo "安装${BUSYBOX_SOURCE}失败"
        ${SUDO_CMD} rm -rf ${BUSYBOX_SOURCE}
        exit 127
    fi
    
    cd ${CUR_DIR}
    
    echo "构建${BUSYBOX_SOURCE}完成"
    if [ -d "${CUR_DIR}/${BUSYBOX_SOURCE}" ]; then
        ${SUDO_CMD} rm -rf ${CUR_DIR}/${BUSYBOX_SOURCE}
    fi
}

function add_files()
{
    if [ ! -d "${ROOTFS_NAME}/lib" ]; then
        mkdir -p ${ROOTFS_NAME}/lib
    fi

    if [ ! -d "${ROOTFS_NAME}/usr/lib" ]; then
        mkdir -p ${ROOTFS_NAME}/usr/lib
    fi

    if [ ! -d "${ROOTFS_NAME}/dev" ]; then
        mkdir -p ${ROOTFS_NAME}/dev
    fi

    if [ ! -d "${ROOTFS_NAME}/proc" ]; then
        mkdir -p ${ROOTFS_NAME}/proc
    fi

    if [ ! -d "${ROOTFS_NAME}/mnt" ]; then
        mkdir -p ${ROOTFS_NAME}/mnt
    fi

    if [ ! -d "${ROOTFS_NAME}/sys" ]; then
        mkdir -p ${ROOTFS_NAME}/sys
    fi

    if [ ! -d "${ROOTFS_NAME}/tmp" ]; then
        mkdir -p ${ROOTFS_NAME}/tmp
        chmod 666 ${ROOTFS_NAME}/tmp
    fi

    if [ ! -d "${ROOTFS_NAME}/root" ]; then
        mkdir -p ${ROOTFS_NAME}/root
    fi

    if [ ! -d "${ROOTFS_NAME}/etc" ]; then
        mkdir -p ${ROOTFS_NAME}/etc
    fi

    if [ ! -d "${ROOTFS_NAME}/etc/init.d" ]; then
        mkdir -p ${ROOTFS_NAME}/etc/init.d
    fi

    if [ ! -d "${ROOTFS_NAME}/etc/hotplug" ]; then
        mkdir -p ${ROOTFS_NAME}/etc/hotplug
    fi

    cd ${ROOTFS_NAME}
    ln -s bin/busybox init
    cd ${CUR_DIR}

    cp ${CROSS_TOOLCHAIN_PATH}/${CROSS_TOOLCHAIN_PREFIX}/libc/lib/*.a ${ROOTFS_NAME}/lib -d
    cp ${CROSS_TOOLCHAIN_PATH}/${CROSS_TOOLCHAIN_PREFIX}/libc/lib/*.so* ${ROOTFS_NAME}/lib -d

    rm -rf ${ROOTFS_NAME}/lib/ld-linux-arm*
    cp ${CROSS_TOOLCHAIN_PATH}/${CROSS_TOOLCHAIN_PREFIX}/libc/lib/ld-linux-arm* ${ROOTFS_NAME}/lib

    cp ${CROSS_TOOLCHAIN_PATH}/${CROSS_TOOLCHAIN_PREFIX}/lib/*.a ${ROOTFS_NAME}/lib -d
    cp ${CROSS_TOOLCHAIN_PATH}/${CROSS_TOOLCHAIN_PREFIX}/lib/*.so* ${ROOTFS_NAME}/lib -d

    cp ${CROSS_TOOLCHAIN_PATH}/${CROSS_TOOLCHAIN_PREFIX}/libc/usr/lib/*.a ${ROOTFS_NAME}/usr/lib -d
    cp ${CROSS_TOOLCHAIN_PATH}/${CROSS_TOOLCHAIN_PREFIX}/libc/usr/lib/*.so* ${ROOTFS_NAME}/usr/lib -d

cat > ${ROOTFS_NAME}/etc/init.d/rcS <<EOF
#!/bin/sh

PATH=/sbin:/bin:/usr/bin:/usr/sbin:\$PATH
LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/lib:/usr/lib
export PATH LD_LIBRARY_PATH

/bin/hostname -F /etc/hostname

mount -a
mkdir /dev/pts
mount -t devpts devpts /dev/pts

echo /sbin/mdev > /proc/sys/kernel/hotplug
mdev -s
EOF
    if [ -f "${ROOTFS_NAME}/etc/init.d/rcS" ]; then
        chmod 777 ${ROOTFS_NAME}/etc/init.d/rcS
    fi

cat > ${ROOTFS_NAME}/etc/fstab <<EOF
#<device> <mount point> <type> <options> <dump> <fsck order>
proc        /proc       proc    defaults    0   0
tmpfs       /tmp        tmpfs   defaults    0   0
sysfs       /sys        sysfs   defaults    0   0
EOF

cat > ${ROOTFS_NAME}/etc/inittab <<EOF
# /etc/inittab

::sysinit:/etc/init.d/rcS
::respawn:-bin/sh
::askfirst:-/bin/sh
tty1::askfirst:-/bin/sh
::restart:/sbin/init
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
::shutdown:/sbin/swapoff -a
EOF

cat > ${ROOTFS_NAME}/etc/resolv.conf <<EOF
nameserver ${DEFAULT_GATEWAY}
nameserver 8.8.8.8
nameserver 114.114.114.114
EOF

cat > ${ROOTFS_NAME}/etc/hostname <<EOF
${HOSTNAME}
EOF

cat > ${ROOTFS_NAME}/etc/profile <<EOF
export HOSTNAME=`/bin/hostname`
export HOME=${HOME_PATH}
export USER=${NEW_USERNAME}
export PS1="[\h@\u \w]\# "
EOF

    if [ ! -d "${ROOTFS_NAME}/mnt/sdcard" ]; then
        mkdir -p ${ROOTFS_NAME}/mnt/sdcard
    fi
    cd ${ROOTFS_NAME}
    ln -s mnt/sdcard sdcard
    cd ${CUR_DIR}

    if [ ! -d "${ROOTFS_NAME}/media/usb0" ]; then
        mkdir -p ${ROOTFS_NAME}/media/usb0
    fi
    cd ${ROOTFS_NAME}
    ln -s media/usb0 udisk
    cd ${CUR_DIR}

cat > ${ROOTFS_NAME}/etc/mdev.conf <<EOF
mmcblk[1-9]p[0-9] 0:0 666 @/etc/hotplug/tfcard_insert
mmcblk[1-9] 0:0 666 \$/etc/hotplug/tfcard_remove

sd[a-z][0-9] 0:0 666 @/etc/hotplug/udisk_insert
sd[a-z] 0:0 666 \$/etc/hotplug/udisk_remove
EOF

cat > ${ROOTFS_NAME}/etc/hotplug/tfcard_insert <<EOF
#!/bin/sh

echo "tfcard insertion detected" > /dev/console
if [ -e "/dev/\$MDEV" ]; then
    mount -o rw /dev/\$MDEV /sdcard/
fi
EOF
    if [ -f "${ROOTFS_NAME}/etc/hotplug/tfcard_insert" ]; then
        chmod 777 ${ROOTFS_NAME}/etc/hotplug/tfcard_insert
    fi

cat > ${ROOTFS_NAME}/etc/hotplug/tfcard_remove <<EOF
#!/bin/sh

# sync

echo "tfcard remove detected" > /dev/console
umount -l /sdcard/
rm -rf /sdcard/*
EOF
    if [ -f "${ROOTFS_NAME}/etc/hotplug/tfcard_remove" ]; then
        chmod 777 ${ROOTFS_NAME}/etc/hotplug/tfcard_remove
    fi

cat > ${ROOTFS_NAME}/etc/hotplug/udisk_insert <<EOF
#!/bin/sh

echo "udisk insertion detected" > /dev/console
if [ -e "/dev/\$MDEV" ]; then
    mount -o rw /dev/\$MDEV /udisk/
fi
EOF
    if [ -f "${ROOTFS_NAME}/etc/hotplug/udisk_insert" ]; then
        chmod 777 ${ROOTFS_NAME}/etc/hotplug/udisk_insert
    fi

cat > ${ROOTFS_NAME}/etc/hotplug/udisk_remove <<EOF
#!/bin/sh

# sync

echo "udisk remove detected" > /dev/console
umount -l /udisk/
rm -rf /udisk/*
EOF
    if [ -f "${ROOTFS_NAME}/etc/hotplug/udisk_remove" ]; then
        chmod 777 ${ROOTFS_NAME}/etc/hotplug/udisk_remove
    fi 
}

function clean()
{
    if [ -d "${ROOTFS_NAME}" ]; then
        ${SUDO_CMD} rm -rf ${ROOTFS_NAME}
    fi

    if [ -d "${CUR_DIR}/${BUSYBOX_SOURCE}" ]; then
        ${SUDO_CMD} rm -rf ${CUR_DIR}/${BUSYBOX_SOURCE}
    fi

    if [ -f "${CUR_DIR}/${BUSYBOX_TARPKT_NAME}" ]; then
        rm -rf ${CUR_DIR}/${BUSYBOX_TARPKT_NAME}
    fi

    if [ -f "${CUR_DIR}/rootfs.tar.bz2" ]; then
        rm -rf ${CUR_DIR}/rootfs.tar.bz2
    fi
}

function rootfs()
{
    if [ -d "${ROOTFS_NAME}" ]; then
        du -h -d 0 ${ROOTFS_NAME}
        cd ${ROOTFS_NAME}

        tar -jcvf rootfs.tar.bz2 *
        mv rootfs.tar.bz2 ${CUR_DIR}
        cd ${CUR_DIR}

        ls -l -h ${CUR_DIR}/rootfs.tar.bz2
    fi
}

function all()
{
    clean
    busybox
    add_files
    rootfs
}

function help()
{
    echo "Usage: $0 [OPTION]"
    echo "[OPTION]:"
    echo "========================================"
    echo "  0  clean        清理构建缓存信息"
    echo "  1  busybox      开始构建busybox"
    echo "  2  add_files    向构建的rootfs添加文件"
    echo "  3  rootfs       打包构建完毕的rootfs"
    echo "  4  all          执行上述1-3的操作"
    echo "========================================"
}

if [ -z $1 ]; then
    help
else
    $1
fi
