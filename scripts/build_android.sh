#!/usr/bin/env sh

set -ex

name=leaf
package=leaf-ffi
manifest=android/Cargo.toml
mode=--release
targets=

if [ ! -z "$2" ]; then
	targets="$2"
else
	targets="aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android"
fi

for target in $targets; do
	rustup target add $target
done

if [ "$1" = "debug" ]; then
	mode=
fi

BASE=`dirname "$0"`
HOST_OS=`uname -s | tr "[:upper:]" "[:lower:]"`

# HOST_ARCH=`uname -m | tr "[:upper:]" "[:lower:]"`
HOST_ARCH=x86_64

export PATH="$NDK_HOME/toolchains/llvm/prebuilt/$HOST_OS-$HOST_ARCH/bin/":$PATH

android_tools="$NDK_HOME/toolchains/llvm/prebuilt/$HOST_OS-$HOST_ARCH/bin"
api=21

# Set RUSTFLAGS for 16KB page size support
export RUSTFLAGS="${RUSTFLAGS} -C link-arg=-Wl,-z,common-page-size=0x4000 -C link-arg=-Wl,-z,max-page-size=0x4000"

# See also: https://github.com/briansmith/ring/blob/main/mk/cargo.sh

for target in $targets; do
	case $target in
		'armv7-linux-androideabi')
			export CC_armv7_linux_androideabi="$android_tools/armv7a-linux-androideabi${api}-clang"
			export AR_armv7_linux_androideabi="$android_tools/llvm-ar"
			export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$android_tools/armv7a-linux-androideabi${api}-clang"
			;;
		'x86_64-linux-android')
			export CC_x86_64_linux_android="$android_tools/${target}${api}-clang"
			export AR_x86_64_linux_android="$android_tools/llvm-ar"
			export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$android_tools/${target}${api}-clang"
			;;
		'aarch64-linux-android')
			export CC_aarch64_linux_android="$android_tools/${target}${api}-clang"
			export AR_aarch64_linux_android="$android_tools/llvm-ar"
			export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$android_tools/${target}${api}-clang"
			;;
		'i686-linux-android')
			export CC_i686_linux_android="$android_tools/${target}${api}-clang"
			export AR_i686_linux_android="$android_tools/llvm-ar"
			export CARGO_TARGET_I686_LINUX_ANDROID_LINKER="$android_tools/${target}${api}-clang"
			;;
		*)
			echo "Unknown target $target"
			;;
	esac
	cargo build -p $package --target $target $mode
done

android_libs=$BASE/../target/leaf-android-libs

mkdir -p $android_libs
for target in $targets; do
	mv $BASE/../target/$target/release/libleaf.so $android_libs/libleaf-$target.so
done

# Post-processing for 16KB page size support
echo "Applying 16KB page size alignment fixes..."
for so_file in $android_libs/libleaf-*.so; do
	if [ -f "$so_file" ]; then
		echo "Processing $so_file"
		# Use patchelf to set page size (if available)
		if command -v patchelf >/dev/null 2>&1; then
			patchelf --set-page-size 0x4000 "$so_file" || echo "patchelf failed for $so_file"
		fi
		# Display segment information (for debugging)
		readelf -l "$so_file" | grep -E "(LOAD|TLS)" || true
	fi
done

cbindgen \
	--config $BASE/../$package/cbindgen.toml \
	$BASE/../$package/src/lib.rs > $android_libs/$name.h