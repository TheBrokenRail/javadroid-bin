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
NDK_VER='android-ndk-r13b'
curl -L -o ndk.zip "https://dl.google.com/android/repository/${NDK_VER}-linux-x86_64.zip"
unzip ndk.zip > /dev/null
NDK_HOME=$(pwd)/${NDK_VER}

# Build Toolchain
${NDK_HOME}/build/tools/make-standalone-toolchain.sh \
  --arch=${TOOLCHAIN_ARCH} \
  --platform=android-19 \
  --install-dir=${NDK_HOME}/generated-toolchains/android-${TOOLCHAIN_ARCH}-toolchain
ANDROID_DEVKIT="${NDK_HOME}/generated-toolchains/android-${TOOLCHAIN_ARCH}-toolchain"

# Create Devkit File
echo 'DEVKIT_NAME="Android"' > ${ANDROID_DEVKIT}/devkit.info
echo 'DEVKIT_TOOLCHAIN_PATH="$DEVKIT_ROOT/'"${ANDROID_ARCH}"'/bin"' >> ${ANDROID_DEVKIT}/devkit.info
echo 'DEVKIT_SYSROOT="$DEVKIT_ROOT/sysroot"' >> ${ANDROID_DEVKIT}/devkit.info
PATH=${ANDROID_DEVKIT}//bin:$PATH

# Build libffi for ARM
if [ ${ANDROID_ARCH} = "arm-linux-androideabi" ]; then
  curl -L -o libffi.tar.gz "https://sourceware.org/pub/libffi/libffi-3.2.1.tar.gz"
  tar -xvf libffi.tar.gz > /dev/null
  cd libffi-3.2.1

  bash configure --host=arm-linux-androideabi --prefix=$(pwd)/arm-unknown-linux-androideabi
  make clean
  make
  make install
  ln -s arm-unknown-linux-androideabi build_android-arm
  
  cd ../
fi

# Build libfreetype
curl -L -o freetype.tar.gz "https://download.savannah.gnu.org/releases/freetype/freetype-2.6.2.tar.gz"
tar -xvf freetype.tar.gz > /dev/null
cd freetype-2.6.2

bash configure --host=${ANDROID_ARCH} \
  --prefix=$(pwd)/build_android-${LIB_ARCH} \
  --without-zlib \
  --with-png=no \
  --with-harfbuzz=no
make clean
make
make install

cd ../

# Download CUPS
curl -L -o cups.tar.gz "https://github.com/apple/cups/releases/download/v2.2.8/cups-2.2.8-source.tar.gz"
tar -xvf cups.tar.gz > /dev/null

# Build JDK
hg clone http://hg.openjdk.java.net/mobile/jdk9 jdk
cd jdk
sh get_source.sh

EXTRA_ARM_1=""
EXTRA_ARM_2=""
JVM_VARIANT="client"
if [ ${ANDROID_ARCH} = "arm-linux-androideabi" ]; then
  JVM_VARIANT="zero"
  LIBFFI_DIR=$(pwd)/../libffi-3.2.1/build_android-arm
  EXTRA_ARM_1="--with-libffi-include=${LIBFFI_DIR}/include"
  EXTRA_ARM_2="--with-libffi-lib=${LIBFFI_DIR}/lib"
fi
FREETYPE_DIR=$(pwd)/../freetype-2.6.2/build_android-${LIB_ARCH}
CUPS=$(pwd)/../cups-2.2.8

bash configure --help
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
  --with-extra-cflags="-fPIE -B${ANDROID_DEVKIT}/libexec/gcc/${ANDROID_ARCH}/4.8" \
  --with-extra-ldflags="-pie" \
  --with-cups-include=${CUPS}

cd build/android-${TOOLCHAIN_ARCH}-normal-${JVM_VARIANT}-release
make images
ls
