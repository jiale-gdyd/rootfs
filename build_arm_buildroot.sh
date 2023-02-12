#!/bin/bash

# 在使用WSL时，如果出现PATH有非法字符等，线切换至root用户，再执行脚本
# sudo apt-get install dosfstools dump parted kpartx

SUDO_CMD=sudo

CROSS_TOOLCHAIN_GCC_MAJOR=10
CROSS_TOOLCHAIN_GCC_MINOR=3
CROSS_TOOLCHAIN_PREFIX=arm-none-linux-gnueabihf
CROSS_TOOLCHAIN_SUBFIX=/opt/toolchain/gcc-arm-${CROSS_TOOLCHAIN_GCC_MAJOR}.${CROSS_TOOLCHAIN_GCC_MINOR}-2021.07-x86_64
CROSS_TOOLCHAIN_PATH=${CROSS_TOOLCHAIN_SUBFIX}-${CROSS_TOOLCHAIN_PREFIX}

CUR_DIR=${PWD}
ROOTFS_NAME=${CUR_DIR}/rootfs

BUILDROOT_VERSION=2022.11.1
BUILDROOT_SOURCE=buildroot-${BUILDROOT_VERSION}
BUILDROOT_TARPKT_NAME=${BUILDROOT_SOURCE}.tar.xz
BUILDROOT_TARPKT_URL=https://buildroot.org/downloads/${BUILDROOT_TARPKT_NAME}

BOARD_CONFIG_FILE=freescale_imx6ullevk_defconfig

HOSTNAME=imx6ull
ROOT_LOGIN_PASSWD=root
LOGIN_BANNER="Welcome to aure imx6ull board !"

function get_toolchain_kernel_header()
{
    version_file=${CROSS_TOOLCHAIN_PATH}/${CROSS_TOOLCHAIN_PREFIX}/libc/usr/include/linux/version.h
    code=`awk '/LINUX_VERSION_CODE/ {print $3}' ${version_file}`
    m=$(($code>>16 &255))
    n=$(($code>>8 &255))
    p=$(($code&255))

    version="$m.$n.x"

    find="false"
    return_str="BR2_TOOLCHAIN_EXTERNAL_HEADERS_REALLY_OLD"

    for ((i=3;i<=6;i++)) do
        for ((j=0;j<=20;j++)) do
            if [ "${version}" = "${i}.${j}.x" ]; then
                return_str="BR2_TOOLCHAIN_EXTERNAL_HEADERS_${i}_${j}"
                find="true"
                break
            fi
        done

        if [ "${find}" = "true" ]; then
            break
        fi
    done

    echo "$return_str"
}

function get_toolchain_gcc_version()
{
    gcc_major=$CROSS_TOOLCHAIN_GCC_MAJOR
    gcc_minor=$CROSS_TOOLCHAIN_GCC_MINOR

    find_gcc_version="false"
    gcc_return_str="BR2_TOOLCHAIN_EXTERNAL_GCC_OLD"

    if [ $gcc_major -ge 4 ] && [ $gcc_minor -ge 3 ]; then
        for ((i=4;i<=20;i++)) do
            if [ $i -lt 5 ]; then
                for ((j=3;j<=9;j++)) do
                    local1_version="$gcc_major.$gcc_minor.x"
                    if [ "$local1_version" = "${i}.${j}.x" ]; then
                        gcc_return_str="BR2_TOOLCHAIN_EXTERNAL_GCC_${i}_${j}"
                        find_gcc_version="true"
                        break
                    fi
                done

                if [ "$find_gcc_version" = "true" ]; then
                    break
                fi
            else
                local2_version="$gcc_major.x"
                if [ "$local2_version" = "${i}.x" ]; then
                    gcc_return_str="BR2_TOOLCHAIN_EXTERNAL_GCC_${i}"
                    break
                fi
            fi
        done
    fi

    echo $gcc_return_str
}

function patch()
{
    # 修改buildroot镜像源
    sed -i 's/default "https:\/\/cdn.kernel.org\/pub"/default "https:\/\/mirror.bjtu.edu.cn\/kernel"/' ${CUR_DIR}/${BUILDROOT_SOURCE}/Config.in
    sed -i 's/default "http:\/\/ftpmirror.gnu.org"/default "http:\/\/mirror.nju.edu.cn\/gnu"/' ${CUR_DIR}/${BUILDROOT_SOURCE}/Config.in
    sed -i 's/default "http:\/\/rocks.moonscript.org"/default "https:\/\/luarocks.cn"/' ${CUR_DIR}/${BUILDROOT_SOURCE}/Config.in
    sed -i 's/default "https:\/\/cpan.metacpan.org"/default "http:\/\/mirror.nju.edu.cn\/CPAN"/' ${CUR_DIR}/${BUILDROOT_SOURCE}/Config.in

    # 不开启kernel和uboot编译
    sed -i 's/BR2_LINUX_KERNEL=y/# BR2_LINUX_KERNEL is not set/' ${CUR_DIR}/${BUILDROOT_SOURCE}/configs/${BOARD_CONFIG_FILE}
    sed -i 's/BR2_TARGET_UBOOT=y/# BR2_TARGET_UBOOT is not set/' ${CUR_DIR}/${BUILDROOT_SOURCE}/configs/${BOARD_CONFIG_FILE}
    sed -i 's/BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_5_10=y/# BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_5_10 is not set/' ${CUR_DIR}/${BUILDROOT_SOURCE}/configs/${BOARD_CONFIG_FILE}
    sed -i 's/BR2_ROOTFS_POST_IMAGE_SCRIPT="board\/freescale\/common\/imx\/post-image.sh"/# BR2_ROOTFS_POST_IMAGE_SCRIPT is not set/' ${CUR_DIR}/${BUILDROOT_SOURCE}/configs/${BOARD_CONFIG_FILE}

    # 默认使用自定义工具链
    sed -i '/Toolchain type/a\    default BR2_TOOLCHAIN_EXTERNAL' ${CUR_DIR}/${BUILDROOT_SOURCE}/toolchain/Config.in
    sed -i '/prompt "Toolchain"/a\  default BR2_TOOLCHAIN_EXTERNAL_CUSTOM' ${CUR_DIR}/${BUILDROOT_SOURCE}/toolchain/toolchain-external/Config.in

    # 工具链路径以及前缀
    sed -i "/string \"Toolchain path\"/{n;s#default \"\"#default \"${CROSS_TOOLCHAIN_PATH}\"#;}" ${CUR_DIR}/${BUILDROOT_SOURCE}/toolchain/toolchain-external/Config.in
    sed -i "/string \"Toolchain prefix\"/{n;s#default \"\$(ARCH)-linux\"#default \"${CROSS_TOOLCHAIN_PREFIX}\"#;}" ${CUR_DIR}/${BUILDROOT_SOURCE}/toolchain/toolchain-external/toolchain-external-custom/Config.in.options

    # 工具链GCC版本
    TOOLCHAIN_GCC_VERSION=`get_toolchain_gcc_version`
    sed -i "/bool \"External toolchain gcc version\"/a\   default ${TOOLCHAIN_GCC_VERSION}" ${CUR_DIR}/${BUILDROOT_SOURCE}/toolchain/toolchain-external/toolchain-external-custom/Config.in.options

    # 编译自定义交叉编译工具链内核版本
    KERNEL_VERSION=`get_toolchain_kernel_header`
    echo "kernel version: $KERNEL_VERSION"
    sed -i "s/default BR2_TOOLCHAIN_EXTERNAL_HEADERS_REALLY_OLD/default ${KERNEL_VERSION}/" ${CUR_DIR}/${BUILDROOT_SOURCE}/toolchain/toolchain-external/toolchain-external-custom/Config.in.options

    # 工具链C库位glibc
    sed -i 's/default BR2_TOOLCHAIN_EXTERNAL_CUSTOM_UCLIBC/default BR2_TOOLCHAIN_EXTERNAL_CUSTOM_GLIBC/' ${CUR_DIR}/${BUILDROOT_SOURCE}/toolchain/toolchain-external/toolchain-external-custom/Config.in.options

    # 工具链支持C++
    sed -i '/Toolchain has C++ support?/a\  default y' ${CUR_DIR}/${BUILDROOT_SOURCE}/toolchain/toolchain-external/toolchain-external-custom/Config.in.options

    # 交叉工具链不支持RPC
    sed -i '/bool "Toolchain has RPC support?"/{n;s#y#n#;}' ${CUR_DIR}/${BUILDROOT_SOURCE}/toolchain/toolchain-external/toolchain-external-custom/Config.in.options

    # 设置板卡系统主机名称
    sed -i "s/default \"buildroot\"/default \"${HOSTNAME}\"/" ${CUR_DIR}/${BUILDROOT_SOURCE}/system/Config.in
    
    # 设置系统登录欢迎语
    sed -i "s/default \"Welcome to Buildroot\"/default \"${LOGIN_BANNER}\"/" ${CUR_DIR}/${BUILDROOT_SOURCE}/system/Config.in

    # 设置root登录密码
    sed -i "/string \"Root password\"/{n;s#default \"\"#default \"${ROOT_LOGIN_PASSWD}\"#;}" ${CUR_DIR}/${BUILDROOT_SOURCE}/system/Config.in

    # 设置ext镜像参数
    # sed -i "/string \"additional mke2fs options\"/{n;s#default \"-O ^64bit\"#default \"-t ext4 -F -O ^metadata_csum,^64bit\"#;}" ${CUR_DIR}/${BUILDROOT_SOURCE}/fs/ext2/Config.in
    # echo "BR2_TARGET_ROOTFS_EXT2_SIZE=\"2048M\"" >> ${CUR_DIR}/${BUILDROOT_SOURCE}/configs/${BOARD_CONFIG_FILE}

    # 下载第三方库设置

    # 开启kmod
    sed -i '/bool "kmod"/a\    default y' ${CUR_DIR}/${BUILDROOT_SOURCE}/package/kmod/Config.in
}

function buildroot()
{
    if [ ! -f "${CUR_DIR}/${BUILDROOT_TARPKT_NAME}" ]; then
        echo "开始下载${BUILDROOT_TARPKT_NAME}"
        wget ${BUILDROOT_TARPKT_URL}
        if [ $? -ne 0 ]; then
            echo "下载${BUILDROOT_TARPKT_NAME}失败"
            exit 127
        fi
    fi

    REMOTE_BUILDROOT_FILESIZE=`curl -sI ${BUILDROOT_TARPKT_URL} | grep -i content-length | awk '{print $2}'`
    if [ ! -f "${CUR_DIR}/${BUILDROOT_TARPKT_NAME}" ] || [ $filesize -ne $REMOTE_BUILDROOT_FILESIZE ]; then
        if [ ! -f "${CUR_DIR}/${BUILDROOT_TARPKT_NAME}" ]; then
            echo "${CUR_DIR}/${BUILDROOT_TARPKT_NAME}不存在，可能未下载成功"
        else
            echo "下载的${CUR_DIR}/${BUILDROOT_TARPKT_NAME}文件大小不对，期望大小: $REMOTE_BUILDROOT_FILESIZE字节，实际大小: $filesize字节"
        fi

        exit 127
    else
        echo "下载的${BUILDROOT_TARPKT_NAME}大小: $filesize字节，远程中的大小: $REMOTE_BUILDROOT_FILESIZE字节"
    fi

    echo "开始解压缩${CUR_DIR}/${BUILDROOT_TARPKT_NAME}"
    tar -xvf ${CUR_DIR}/${BUILDROOT_TARPKT_NAME}
    if [ $? -ne 0 ]; then
        echo "解压缩${CUR_DIR}/${BUILDROOT_TARPKT_NAME}失败"
        exit 127
    fi
    echo "解压缩${CUR_DIR}/${BUILDROOT_TARPKT_NAME}完成"

    echo "开始向${CUR_DIR}/${BUILDROOT_SOURCE}中添加补丁"
    patch
    echo "向${CUR_DIR}/${BUILDROOT_SOURCE}中添加补丁完成"

    echo "开始构建${BUILDROOT_SOURCE}"
    cd ${CUR_DIR}/${BUILDROOT_SOURCE}

    make ${BOARD_CONFIG_FILE}
    make menuconfig
    if [ $? -ne 0 ]; then
        echo "make menuconfig失败"
        exit 127
    fi

    make busybox-menuconfig
    if [ $? -ne 0 ]; then
        echo "make busybox-menuconfig失败"
        exit 127
    fi

    ${SUDO_CMD} make
    if [ $? -ne 0 ]; then
        echo "构建${CUR_DIR}/${BUILDROOT_SOURCE}失败"
        ${SUDO_CMD} rm -rf ${CUR_DIR}/${BUILDROOT_SOURCE}
        exit 127
    fi

    if [ ! -d "${ROOTFS_NAME}" ]; then
        mkdir -p ${ROOTFS_NAME}
    fi


    cd ${CUR_DIR}
    echo "构建${CUR_DIR}/${BUILDROOT_SOURCE}完成"
}

function add_files()
{
    if [ ! -d "${ROOTFS_NAME}/etc/hotplug" ]; then
        ${SUDO_CMD} mkdir -p ${ROOTFS_NAME}/etc/hotplug
    fi

    if [ ! -d "${ROOTFS_NAME}/mnt/sdcard" ]; then
        mkdir -p ${ROOTFS_NAME}/mnt/sdcard
    fi

    cd ${ROOTFS_NAME}
    ln -s mnt/sdcard sdcard
    cd -

    if [ ! -d "${ROOTFS_NAME}/media/usb0" ]; then
        mkdir -p ${ROOTFS_NAME}/media/usb0
    fi

    cd ${ROOTFS_NAME}
    ln -s media/usb0 udisk
    cd -

cat > ${ROOTFS_NAME}/etc/mdev.conf <<EOF
mmcblk[1-9]p[0-9] 0:0 666 @/etc/hotplug/tfcard_insert
mmcblk[1-9] 0:0 666 \$/etc/hotplug/tfcard_remove

sd[a-z][0-9] 0:0 666 @/etc/hotplug/udisk_insert
sd[a-z] 0:0 666 \$/etc/hotplug/udisk_remove
EOF

cat > ${ROOTFS_NAME}/etc/hotplug/tfcard_insert <<EOF
#!/bin/sh

echo "tfcard insert detected" > /dev/console
if [ -e "/dev/\$MDEV" ]; then
    mount -o rw /dev/\$MDEV /sdcard/
fi
EOF
    if [ -f "${ROOTFS_NAME}/etc/hotplug/tfcard_insert" ]; then
        chmod 777 ${ROOTFS_NAME}/etc/hotplug/tfcard_insert
    fi

cat > ${ROOTFS_NAME}/etc/hotplug/tfcard_remove <<EOF
#!bin/sh

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

echo "udisk insert detected" > /dev/console
if [ -e "/dev/\$MDEV" ]; then
    mount -o rw /dev/\$MDEV /udisk/
fi
EOF
    if [ -f "${ROOTFS_NAME}/etc/hotplug/udisk_insert" ]; then
        chmod 777 ${ROOTFS_NAME}/etc/hotplug/udisk_insert
    fi

cat > ${ROOTFS_NAME}/etc/hotplug/udisk_remove <<EOF
#!bin/sh

# sync

echo "udisk remove detected" > /dev/console
umount -l /udisk/
rm -rf /udisk/*
EOF
    if [ -f "${ROOTFS_NAME}/etc/hotplug/udisk_remove" ]; then
        chmod 777 ${ROOTFS_NAME}/etc/hotplug/udisk_remove
    fi
}

function rootfs()
{
    if [ -d "${ROOTFS_NAME}" ]; then
        if [ -f "${CUR_DIR}/${BUILDROOT_SOURCE}/output/images/rootfs.tar" ]; then
            # dd if=/dev/zero of=rootfs.img bs=1M count=2048 && sync
            # mkfs.ext4 -O ^metadata_csum rootfs.img

            # ${SUDO_CMD} mount -t ext4 rootfs.img ${ROOTFS_NAME}/
            tar -xvf ${CUR_DIR}/${BUILDROOT_SOURCE}/output/images/rootfs.tar -C ${ROOTFS_NAME}
            add_files

            # ${SUDO_CMD} umount ${ROOTFS_NAME}/

            # ${SUDO_CMD} e2fsck -p -f rootfs.img
            # ${SUDO_CMD} resize2fs -M rootfs.img

            du -h -d 0 ${ROOTFS_NAME}
            cd ${ROOTFS_NAME}

            tar -jcvf rootfs.tar.bz2 *
            mv rootfs.tar.bz2 ${CUR_DIR}
            cd ${CUR_DIR}

            ls -l -h ${CUR_DIR}/rootfs.tar.bz2
        fi
    fi

    if [ -d "${CUR_DIR}/${BUILDROOT_SOURCE}" ]; then
        ${SUDO_CMD} rm -rf ${CUR_DIR}/${BUILDROOT_SOURCE}
    fi
}

function clean()
{
    if [ -d "${ROOTFS_NAME}" ]; then
        ${SUDO_CMD} rm -rf ${ROOTFS_NAME}
    fi

    if [ -d "${CUR_DIR}/${BUILDROOT_SOURCE}" ]; then
        ${SUDO_CMD} rm -rf ${CUR_DIR}/${BUILDROOT_SOURCE}
    fi

    if [ -f "${CUR_DIR}/${BUILDROOT_TARPKT_NAME}" ]; then
        rm -rf ${CUR_DIR}/${BUILDROOT_TARPKT_NAME}
    fi

    if [ -f "${CUR_DIR}/rootfs.tar.bz2" ]; then
        rm -rf ${CUR_DIR}/rootfs.tar.bz2
    fi

    if [ -f "${CUR_DIR}/rootfs.img" ]; then
        rm -rf ${CUR_DIR}/rootfs.img
    fi
}

function all()
{
    clean
    buildroot
    rootfs
}

function help()
{
    echo "Usage: $0 [OPTION]"
    echo "[OPTION]:"
    echo "====================================="
    echo "  0  clean     清理工程构建信息"
    echo "  1  buildroot 开始构建buildrot"
    echo "  2  rootfs    打包构建的rootfs镜像"
    echo "  3  all       顺序执行上述1-2的操作"
    echo "====================================="
}

if [ -z $1 ]; then
    help
else
    $1
fi
