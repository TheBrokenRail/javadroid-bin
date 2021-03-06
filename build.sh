#!/bin/bash

set -e

if [ ${ARCH} = "arm" ]; then
  ANDROID_ARCH="arm-linux-androideabi"
fi
if [ ${ARCH} = "x86" ]; then
  ANDROID_ARCH="i686-linux-android"
fi

git config --global user.email $(git log --pretty=format:"%ae" -n1)
git config --global user.name "$(git log --pretty=format:"%an" -n1)"
SHA=$(git rev-parse --verify HEAD)

# Download NDK
echo 'Downloading NDK...'
NDK_VER='android-ndk-r13b'
curl --retry 5 -L -o ndk.zip "https://dl.google.com/android/repository/${NDK_VER}-linux-x86_64.zip"
unzip ndk.zip > /dev/null
NDK_HOME=$(pwd)/${NDK_VER}

# Build Toolchain
echo 'Building Toolchain...'
${NDK_HOME}/build/tools/make_standalone_toolchain.py \
  --arch=${ARCH} \
  --api=21 \
  --install-dir=${NDK_HOME}/generated-toolchains/android-${ARCH}-toolchain
ANDROID_DEVKIT="${NDK_HOME}/generated-toolchains/android-${ARCH}-toolchain"

# Prepare Enviorment
SYSROOT=${ANDROID_DEVKIT}/sysroot
PATH=${ANDROID_DEVKIT}//bin:$PATH

# Build libffi for ARM
if [ ${ARCH} = "arm" ]; then
  echo 'Building libffi...'
  curl --retry 5 -L -o libffi.tar.gz "https://sourceware.org/pub/libffi/libffi-3.2.1.tar.gz"
  tar -xvf libffi.tar.gz > /dev/null
  cd libffi-3.2.1

  bash configure \
    --host=${ANDROID_ARCH} \
    --prefix=$(pwd)/${ARCH}-unknown-linux-androideabi \
    --with-sysroot=${SYSROOT}
  make clean
  make
  make install
  ln -s ${ARCH}-unknown-linux-androideabi build_android-${ARCH}
  
  cd ../
fi

# Build libfreetype
echo 'Building FreeType...'
curl --retry 5 -L -o freetype.tar.gz "https://download.savannah.gnu.org/releases/freetype/freetype-2.6.2.tar.gz"
tar -xvf freetype.tar.gz > /dev/null
cd freetype-2.6.2

bash configure --host=${ANDROID_ARCH} \
  --prefix=$(pwd)/build_android-${ARCH} \
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
ABI=""
JVM_VARIANT="client"
if [ ${ARCH} = "arm" ]; then
  JVM_VARIANT="zero"
  LIBFFI_DIR=$(pwd)/../libffi-3.2.1/build_android-${ARCH}
  EXTRA_ARM_1="--with-libffi-include=${LIBFFI_DIR}/include"
  EXTRA_ARM_2="--with-libffi-lib=${LIBFFI_DIR}/lib"
  ABI="--with-abi-profile=arm-vfp-sflt"
fi
FREETYPE_DIR=$(pwd)/../freetype-2.6.2/build_android-${ARCH}
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
  ${ABI} \
  --with-extra-cflags="-fPIE -B${ANDROID_DEVKIT}/libexec/gcc/${ANDROID_ARCH}/4.8" \
  --with-extra-ldflags="-pie" \
  --with-cups-include=${CUPS} \
  --with-sysroot=${SYSROOT}

cd build/android-*
while sleep 5m; do echo "Command Still Running..."; done &
make images
kill %1

# Deploy to GitHub
mkdir github

cd images
for FILE in *; do
  tar -zcf ../github/${FILE}.tar.gz ${FILE}
  split -d -b 100M ../github/${FILE}.tar.gz "../github/${FILE}.tar.gz."
  rm ../github/${FILE}.tar.gz
done
cd ../

cd github
git init
git add .
git commit --quiet -m "Deploy to Github Pages: ${SHA}"
git push --force "https://${GITHUB_TOKEN}@github.com/TheBrokenRail/javadroid-bin.git" master:${ARCH}
cd ../
