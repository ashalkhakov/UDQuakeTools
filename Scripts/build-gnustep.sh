#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

export CC=clang
export CXX=clang++

WORKSPACE_DIR=$(pwd)
LOCAL_PREFIX="${WORKSPACE_DIR}/gnustep-prefix"
mkdir -p "${LOCAL_PREFIX}"

rm -rf /tmp/gnustep-build
mkdir -p /tmp/gnustep-build
cd /tmp/gnustep-build

echo "=== Building libobjc2 ==="
git clone --depth 1 --recursive https://github.com/gnustep/libobjc2.git
cd libobjc2
cmake -B Build -DCMAKE_BUILD_TYPE=Release \
-DCMAKE_INSTALL_PREFIX="${LOCAL_PREFIX}" \
-DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++
cmake --build Build -j$(nproc)
cmake --install Build
cd ..

echo "=== Building gnustep-make ==="
git clone --depth 1 https://github.com/gnustep/tools-make.git
cd tools-make

# Force the cohesive native layout
# Explicitly feed the compiler the local search paths so it detects libobjc2
./configure --prefix="${LOCAL_PREFIX}" \
--with-layout=gnustep \
--with-library-combo=ng-gnu-gnu \
--enable-objc-arc \
CPPFLAGS="-I${LOCAL_PREFIX}/include" \
LDFLAGS="-L${LOCAL_PREFIX}/lib -Wl,-rpath,${LOCAL_PREFIX}/lib" \
CC=clang CXX=clang++
make -j$(nproc)
make install
cd ..

. "${LOCAL_PREFIX}/System/Library/Makefiles/GNUstep.sh"

export LD_LIBRARY_PATH="${LOCAL_PREFIX}/lib:${LD_LIBRARY_PATH}"
export C_INCLUDE_PATH="${LOCAL_PREFIX}/include:${C_INCLUDE_PATH}"
export CPLUS_INCLUDE_PATH="${LOCAL_PREFIX}/include:${CPLUS_INCLUDE_PATH}"

echo "=== Building gnustep-base ==="
git clone --depth 1 https://github.com/gnustep/libs-base.git
cd libs-base
./configure --prefix="${LOCAL_PREFIX}" \
--with-config-file="${LOCAL_PREFIX}/etc/GNUstep.conf" \
--with-default-config=standalone.conf
make -j$(nproc)
make install
cd ..

echo "=== Building gnustep-gui ==="
git clone --depth 1 https://github.com/gnustep/libs-gui.git
cd libs-gui
./configure --prefix="${LOCAL_PREFIX}"
make -j$(nproc)
make install
cd ..

echo "=== Building gnustep-back ==="
git clone --depth 1 https://github.com/gnustep/libs-back.git
cd libs-back
# Force the modern Cairo graphics backend so Fontconfig is actually used
./configure --prefix="${LOCAL_PREFIX}" --enable-graphics=cairo
make -j$(nproc)
make install
cd ..

echo "=== Building tools-xctest ==="
git clone --depth 1 https://github.com/gnustep/tools-xctest.git
cd tools-xctest
make -j$(nproc)
make install
cd ..

echo "=== Building libdispatch (runtime dependency for Eau) ==="
git clone --depth 1 https://github.com/apple/swift-corelibs-libdispatch.git libdispatch
cd libdispatch
cmake -B Build -DCMAKE_BUILD_TYPE=Release \
-DCMAKE_INSTALL_PREFIX="${LOCAL_PREFIX}"
cmake --build Build -j$(nproc)
cmake --install Build
cd ..

echo "=== Building Eau Theme ==="
# Clone the theme from Gershwin / GNUstep ports
git clone --depth 1 https://github.com/gershwin-desktop/gershwin-eau-theme.git Eau
cd Eau
# source the environment to let gnustep-make install it inside the local prefix
. "${LOCAL_PREFIX}/System/Library/Makefiles/GNUstep.sh"
# FIX: Force the linker to bind dispatch and BlocksRuntime to the theme
make ADDITIONAL_LDFLAGS="-ldispatch -lBlocksRuntime" -j$(nproc)
make install
cd ..

echo "=== GNUstep Local Stack Compilation Complete ==="