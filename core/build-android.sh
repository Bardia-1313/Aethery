#!/bin/bash
set -e

ABI=$1
if [ "$ABI" == "-Abi" ]; then
    ABI=$2
fi

API=24

case "$ABI" in
    "arm64-v8a")
        TARGET_TRIPLE="aarch64-linux-android"
        CLANG_PREFIX="aarch64-linux-android"
        INCLUDE_ARCH="aarch64-linux-android"
        ;;
    "armeabi-v7a")
        TARGET_TRIPLE="armv7-linux-androideabi"
        CLANG_PREFIX="armv7a-linux-androideabi"
        INCLUDE_ARCH="arm-linux-androideabi"
        ;;
    *)
        echo "Usage: $0 -Abi [arm64-v8a|armeabi-v7a]"
        exit 1
        ;;
esac

# Check Rust target
if ! rustup target list --installed | grep -q "$TARGET_TRIPLE"; then
    echo "Error: Rust target $TARGET_TRIPLE is not installed."
    echo "Please run: rustup target add $TARGET_TRIPLE"
    exit 1
fi

# Locate SDK
SDK=$ANDROID_HOME
if [ -z "$SDK" ]; then SDK=$ANDROID_SDK_ROOT; fi
if [ -z "$SDK" ]; then SDK="$HOME/Android/Sdk"; fi

# Locate NDK
NDK_VERSION="26.3.11579264"
NDK="$SDK/ndk/$NDK_VERSION"
if [ ! -d "$NDK" ]; then
    NDK=$(ls -d $SDK/ndk/* 2>/dev/null | head -n 1)
fi

if [ -z "$NDK" ] || [ ! -d "$NDK" ]; then
    echo "Android NDK not found in $SDK/ndk"
    exit 1
fi

# Build environment
export ANDROID_NDK_HOME="$NDK"
export ANDROID_NDK_ROOT="$NDK"
BIN_DIR="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
if [ ! -d "$BIN_DIR" ]; then
    # Fallback for macOS
    BIN_DIR="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin"
fi

RUST_ENV_SUFFIX=$(echo $TARGET_TRIPLE | tr '[:lower:]' '[:upper:]' | tr '-' '_')
RUST_TARGET_SUFFIX=$(echo $TARGET_TRIPLE | tr '-' '_')

export "CARGO_TARGET_${RUST_ENV_SUFFIX}_LINKER"="$BIN_DIR/${CLANG_PREFIX}${API}-clang"
export "CARGO_TARGET_${RUST_ENV_SUFFIX}_AR"="$BIN_DIR/llvm-ar"
export "AR_${RUST_TARGET_SUFFIX}"="$BIN_DIR/llvm-ar"
export "CC_${RUST_TARGET_SUFFIX}"="$BIN_DIR/${CLANG_PREFIX}${API}-clang"
export "CXX_${RUST_TARGET_SUFFIX}"="$BIN_DIR/${CLANG_PREFIX}${API}-clang++"
export "CFLAGS_${RUST_TARGET_SUFFIX}"="--target=${CLANG_PREFIX}${API}"
export "CXXFLAGS_${RUST_TARGET_SUFFIX}"="--target=${CLANG_PREFIX}${API}"

SYSROOT="$NDK/toolchains/llvm/prebuilt/$(uname -s | tr '[:upper:]' '[:lower:]')-x86_64/sysroot"
export "BINDGEN_EXTRA_CLANG_ARGS_${RUST_TARGET_SUFFIX}"="--target=${CLANG_PREFIX}${API} --sysroot=$SYSROOT -I$SYSROOT/usr/include/$INCLUDE_ARCH"

export RUSTFLAGS="-C link-arg=-Wl,-soname,libaether.so -C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384"

cd "$(dirname "$0")/aether"
cargo build --release --lib --target "$TARGET_TRIPLE"

# Stage outputs
ROOT="$(cd .. && pwd)"
LIBRARY="$ROOT/core/aether/target/$TARGET_TRIPLE/release/libaether.so"

mkdir -p "$ROOT/core/android-libs/$ABI"
cp "$LIBRARY" "$ROOT/core/android-libs/$ABI/libaether.so"

mkdir -p "$ROOT/app/src/main/jniLibs/$ABI"
cp "$LIBRARY" "$ROOT/app/src/main/jniLibs/$ABI/libaether.so"
