#!/bin/bash
echo "Would you mind picking an Device variant?"
select choice in sc06d 
do
case "$choice" in
	"sc06d")
                TARGET_DEVICE=SC06D
                KERNEL_CMDLINE="androidboot.hardware=qcom user_debug=31 zcache androidboot.bootdevice=msm_sdcc.1"
                KERNEL_BASEADDRESS=0x80200000
                KERNEL_RAMDISK_OFFSET=0x01500000
                KERNEL_PAGESIZE=2048
                IMG_MAX_SIZE=10485760
		break;;

esac
done

# common config
KERNEL_DIR=$PWD
IMAGE_NAME=recovery
BUILD_MOD=KBC
RAMDISK_SRC_DIR=release-tools/$TARGET_DEVICE/recovery_ramdisk
RAMDISK_TMP_DIR=/tmp/recovery_ramdisk

BIN_DIR=out/$TARGET_DEVICE/bin
OBJ_DIR=out/$TARGET_DEVICE/obj
mkdir -p $BIN_DIR
mkdir -p $OBJ_DIR

RECOVERY_VERSION=recovery_version
if [ -f $RAMDISK_SRC_DIR/recovery_version ]; then
    RECOVERY_VERSION=$RAMDISK_SRC_DIR/recovery_version
fi
. $RECOVERY_VERSION

# function

copy_ramdisk()
{
    echo copy $RAMDISK_SRC_DIR to $(dirname $RAMDISK_TMP_DIR)

    if [ -d $RAMDISK_TMP_DIR ]; then
        rm -rf $RAMDISK_TMP_DIR
    fi
    cp -a $RAMDISK_SRC_DIR $(dirname $RAMDISK_TMP_DIR)
    rm -rf $RAMDISK_TMP_DIR/.git
    find $RAMDISK_TMP_DIR -name .gitkeep | xargs rm --force
    find $RAMDISK_TMP_DIR -name .gitignore | xargs rm --force
    if [ -f $RAMDISK_TMP_DIR/recovery_version ]; then
        rm -f $RAMDISK_TMP_DIR/recovery_version
    fi
}

make_boot_image()
{
    echo "=== make_boot_image ==="
    ./release-tools/mkbootfs ${RAMDISK_TMP_DIR} > ${BIN_DIR}/ramdisk-${IMAGE_NAME}.cpio
    ./release-tools/minigzip < ${BIN_DIR}/ramdisk-${IMAGE_NAME}.cpio > ${BIN_DIR}/ramdisk-${IMAGE_NAME}.img
#    lzma < ${BIN_DIR}/ramdisk-${IMAGE_NAME}.cpio > ${BIN_DIR}/ramdisk-${IMAGE_NAME}.img
    ./release-tools/mkbootimg --cmdline "${KERNEL_CMDLINE}" --base ${KERNEL_BASEADDRESS} --pagesize ${KERNEL_PAGESIZE} --ramdisk_offset ${KERNEL_RAMDISK_OFFSET} --kernel ${BIN_DIR}/kernel --ramdisk ${BIN_DIR}/ramdisk-${IMAGE_NAME}.img --output ${BIN_DIR}/${IMAGE_NAME}.img
    echo "  $BIN_DIR/$IMAGE_NAME.img"
    rm $BIN_DIR/ramdisk-$IMAGE_NAME.img
    rm $BIN_DIR/ramdisk-$IMAGE_NAME.cpio
    rm $BIN_DIR/kernel
}

make_recovery_image()
{
    echo "=== make_recovery_image ==="
    ./release-tools/mkbootfs ${RAMDISK_TMP_DIR} > ${BIN_DIR}/ramdisk-${IMAGE_NAME}.cpio
    ./release-tools/minigzip < ${BIN_DIR}/ramdisk-${IMAGE_NAME}.cpio > ${BIN_DIR}/ramdisk-${IMAGE_NAME}.img
#    lzma < ${BIN_DIR}/ramdisk-${IMAGE_NAME}.cpio > ${BIN_DIR}/ramdisk-${IMAGE_NAME}.img
    ./release-tools/mkbootimg --cmdline "${KERNEL_CMDLINE} androidboot.selinux=permissive" --base ${KERNEL_BASEADDRESS} --pagesize ${KERNEL_PAGESIZE} --ramdisk_offset ${KERNEL_RAMDISK_OFFSET} --kernel ${BIN_DIR}/kernel --ramdisk ${BIN_DIR}/ramdisk-${IMAGE_NAME}.img --output ${BIN_DIR}/${IMAGE_NAME}.img
    echo "  $BIN_DIR/$IMAGE_NAME.img"
    rm $BIN_DIR/ramdisk-$IMAGE_NAME.img
    rm $BIN_DIR/ramdisk-$IMAGE_NAME.cpio
    rm $BIN_DIR/kernel
}

make_odin3_image()
{
    echo "=== make_odin3_image ==="
    tar cf $BUILD_LOCALVERSION-$IMAGE_NAME-odin.tar $IMAGE_NAME.img
    md5sum -t $BUILD_LOCALVERSION-$IMAGE_NAME-odin.tar >> $BUILD_LOCALVERSION-$IMAGE_NAME-odin.tar
    mv $BUILD_LOCALVERSION-$IMAGE_NAME-odin.tar $BUILD_LOCALVERSION-$IMAGE_NAME-odin.tar.md5
    echo "  $BIN_DIR/$BUILD_LOCALVERSION-$IMAGE_NAME-odin.tar.md5"
}

make_cwm_image()
{
    echo "=== make_cwm_image ==="
    if [ -d tmp ]; then
        rm -rf tmp
    fi
    mkdir -p ./tmp/META-INF/com/google/android
    cp $IMAGE_NAME.img ./tmp/
    cp $KERNEL_DIR/release-tools/update-binary ./tmp/META-INF/com/google/android/
    sed -e "s/@VERSION/$BUILD_LOCALVERSION/g" $KERNEL_DIR/release-tools/$TARGET_DEVICE/updater-script-$IMAGE_NAME.sed > ./tmp/META-INF/com/google/android/updater-script
    cd tmp && zip -rq ../cwm.zip ./* && cd ../
    SIGNAPK_DIR=$KERNEL_DIR/release-tools/signapk
    java -jar $SIGNAPK_DIR/signapk.jar -w $SIGNAPK_DIR/testkey.x509.pem $SIGNAPK_DIR/testkey.pk8 cwm.zip $BUILD_LOCALVERSION-$IMAGE_NAME-signed.zip
    rm cwm.zip
    rm -rf tmp
    echo "  $BIN_DIR/$BUILD_LOCALVERSION-$IMAGE_NAME-signed.zip"
}



echo BUILD_RECOVERYVERSION $BUILD_RECOVERYVERSION

# set build env
BUILD_LOCALVERSION=$BUILD_RECOVERYVERSION

echo ""
echo "====================================================================="
echo "    BUILD START (RECOVERY VERSION $BUILD_LOCALVERSION)"
echo "====================================================================="

# copy RAMDISK
echo ""
echo "=====> COPY RAMDISK"
copy_ramdisk

echo ""
echo "=====> CREATE RELEASE IMAGE"
# clean release dir
if [ `find $BIN_DIR -type f | wc -l` -gt 0 ]; then
  rm -rf $BIN_DIR/*
fi
mkdir -p $BIN_DIR

# copy zImage -> kernel
#REBUILD_IMAGE=./release-tools/$TARGET_DEVICE/stock-img/recovery.img-kernel.gz
PREBUILD_IMAGE=./release-tools/$TARGET_DEVICE/prebuild-img/zImage
echo "use image : ${PREBUILD_IMAGE}"
cp ${PREBUILD_IMAGE} $BIN_DIR/kernel

# create recovery image
make_recovery_image

#check image size
img_size=`wc -c $BIN_DIR/$IMAGE_NAME.img | awk '{print $1}'`
if [ $img_size -gt $IMG_MAX_SIZE ]; then
    echo "FATAL: $IMAGE_NAME image size over. image size = $img_size > $IMG_MAX_SIZE byte"
    rm $BIN_DIR/$IMAGE_NAME.img
    exit -1
fi

cd $BIN_DIR

# create odin image
make_odin3_image

# create cwm image
make_cwm_image

cd $KERNEL_DIR

echo ""
echo "====================================================================="
echo "    BUILD COMPLETED"
echo "====================================================================="
exit 0
