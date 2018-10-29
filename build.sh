#!/bin/bash

set -e

# TOOLCHAIN_ARCH = ["arm", "x86"]
# ANDROID_ARCH = ["arm-linux-androideabi", "i686-linux-android"]
# LIB_ARCH = ["arm", "i686"]
if [ ${ARCH} = "arm" ]; then
  TOOLCHAIN_ARCH="arm"
  ANDROID_ARCH="arm-linux-androideabi"
  LIB_ARCH="arm"
fi
if [ ${ARCH} = "x86" ]; then
  TOOLCHAIN_ARCH="x86"
  ANDROID_ARCH="i686-linux-android"
  LIB_ARCH="i686"
fi

# Download NDK
echo 'Downloading NDK...'
NDK_VER='android-ndk-r13b'
curl --retry 5 -L -o ndk.zip "https://dl.google.com/android/repository/${NDK_VER}-linux-x86_64.zip"
unzip ndk.zip > /dev/null
NDK_HOME=$(pwd)/${NDK_VER}

# Build Toolchain
echo 'Building Toolchain...'
${NDK_HOME}/build/tools/make_standalone_toolchain.py \
  --arch=${TOOLCHAIN_ARCH} \
  --api=21 \
  --install-dir=${NDK_HOME}/generated-toolchains/android-${TOOLCHAIN_ARCH}-toolchain
ANDROID_DEVKIT="${NDK_HOME}/generated-toolchains/android-${TOOLCHAIN_ARCH}-toolchain"

# Prepare Enviorment
SYSROOT=${ANDROID_DEVKIT}/sysroot
PATH=${ANDROID_DEVKIT}//bin:$PATH

# Build libffi for ARM
if [ ${ANDROID_ARCH} = "arm-linux-androideabi" ]; then
  echo 'Building libffi...'
  curl --retry 5 -L -o libffi.tar.gz "https://sourceware.org/pub/libffi/libffi-3.2.1.tar.gz"
  tar -xvf libffi.tar.gz > /dev/null
  cd libffi-3.2.1

  bash configure \
    --host=arm-linux-androideabi \
    --prefix=$(pwd)/arm-unknown-linux-androideabi \
    --with-sysroot=${SYSROOT}
  make clean
  make
  make install
  ln -s arm-unknown-linux-androideabi build_android-arm
  
  cd ../
fi

# Build libfreetype
echo 'Building FreeType...'
curl --retry 5 -L -o freetype.tar.gz "https://download.savannah.gnu.org/releases/freetype/freetype-2.6.2.tar.gz"
tar -xvf freetype.tar.gz > /dev/null
cd freetype-2.6.2

bash configure --host=${ANDROID_ARCH} \
  --prefix=$(pwd)/build_android-${LIB_ARCH} \
  --without-zlib \
  --with-png=no \
  --with-harfbuzz=no \
  --with-sysroot=${SYSROOT}
make clean
make
make install

cd ../

# Download CUPS
echo 'Downloading CUPS...'
curl --retry 5 -L -o cups.tar.gz "https://github.com/apple/cups/releases/download/v2.2.8/cups-2.2.8-source.tar.gz"
tar -xvf cups.tar.gz > /dev/null

# Build JDK
echo 'Building JDK...'
hg clone http://hg.openjdk.java.net/mobile/jdk9 jdk
cd jdk
sh get_source.sh

EXTRA_ARM_1=""
EXTRA_ARM_2=""
EXTRA_ARM_3=""
JVM_VARIANT="client"
if [ ${ANDROID_ARCH} = "arm-linux-androideabi" ]; then
  JVM_VARIANT="zero"
  LIBFFI_DIR=$(pwd)/../libffi-3.2.1/build_android-arm
  EXTRA_ARM_1="--with-libffi-include=${LIBFFI_DIR}/include"
  EXTRA_ARM_2="--with-libffi-lib=${LIBFFI_DIR}/lib"
  EXTRA_ARM_3="--with-abi-profile=arm-vfp-sflt"
fi
FREETYPE_DIR=$(pwd)/../freetype-2.6.2/build_android-${LIB_ARCH}
CUPS=$(pwd)/../cups-2.2.8

bash configure \
  --enable-option-checking=fatal \
  --openjdk-target=${ANDROID_ARCH} \
  --disable-warnings-as-errors \
  --enable-headless-only \
  --with-jdk-variant=normal \
  --with-jvm-variants=${JVM_VARIANT} \
  --with-debug-level=release \
  --with-freetype-lib=${FREETYPE_DIR}/lib \
  --with-freetype-include=${FREETYPE_DIR}/include/freetype2 \
  ${EXTRA_ARM_1} \
  ${EXTRA_ARM_2} \
  ${EXTRA_ARM_3} \
  --with-extra-cflags="-fPIE -B${ANDROID_DEVKIT}/libexec/gcc/${ANDROID_ARCH}/4.8" \
  --with-extra-ldflags="-pie" \
  --with-cups-include=${CUPS} \
  --with-sysroot=${SYSROOT}

cd build/android-${TOOLCHAIN_ARCH}-normal-${JVM_VARIANT}-release
travis_wait make jre-image
ls
