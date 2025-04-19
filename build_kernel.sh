#!/bin/bash

# GitHub repo and devices
DEVICES=("beyond0lte" "beyond1lte" "beyond2lte" "beyondx" "d1" "d1x" "d2s" "d2x" "f62")

# Paths
KERNEL_DIR="$(pwd)"
OUT_BASE="$KERNEL_DIR/out"
BOOTIMAGE_BASE="/home/jay/bootimages"
FREERUNNER_OUTPUT="$BOOTIMAGE_BASE/freerunnerkernel"
TEMP_DIR="$FREERUNNER_OUTPUT/temp"

# Toolchain setup
export PATH="/home/jay/toolchains/clang-21/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64

if command -v ccache &>/dev/null; then
    export CC="ccache clang"
    export CXX="ccache clang++"
    echo "🚀 Using ccache to speed up builds"
else
    export CC="clang"
    export CXX="clang++"
fi

mkdir -p "$FREERUNNER_OUTPUT" "$TEMP_DIR"

# Loop through devices
for DEVICE in "${DEVICES[@]}"; do
    echo -e "\n🔧 Building for: $DEVICE"
    
    DEFCONFIG="exynos9820-${DEVICE}_defconfig"
    DEFCONFIG_PATH="arch/arm64/configs/$DEFCONFIG"

    if [ ! -f "$DEFCONFIG_PATH" ]; then
        echo "❌ Missing defconfig for $DEVICE, skipping..."
        continue
    fi

    # Extract kernel version
    RAW_VERSION=$(grep CONFIG_LOCALVERSION "$DEFCONFIG_PATH" | cut -d'"' -f2)
    KERNEL_VERSION=$(echo "$RAW_VERSION" | grep -oP 'v[0-9]+(\.[0-9]+)*')
    echo "🔍 Detected kernel version: $KERNEL_VERSION"

    OUT_DIR="${OUT_BASE}/${DEVICE}"
    BOOTIMAGE_DIR="${BOOTIMAGE_BASE}/${DEVICE}"
    IMAGE_PATH="$OUT_DIR/arch/arm64/boot/Image"
    DEST_IMAGE_PATH="${BOOTIMAGE_DIR}/Image"

    echo -e "\n⚙️  Building kernel for $DEVICE with ZyC Clang..."
    mkdir -p "$OUT_DIR"
    make -C "$KERNEL_DIR" O="$OUT_DIR" clean
    make -C "$KERNEL_DIR" O="$OUT_DIR" "$DEFCONFIG" LLVM=1

    BUILD_START=$(date +%s)
    make -C "$KERNEL_DIR" O="$OUT_DIR" -j$(nproc) LLVM=1 -O
    BUILD_END=$(date +%s)
    DURATION=$((BUILD_END - BUILD_START))

    echo "✅ Build completed for $DEVICE in $(printf "%02d:%02d" $((DURATION/60)) $((DURATION%60)))"

    # Post-build
    if [ ! -f "$IMAGE_PATH" ]; then
        echo "❌ Image not found for $DEVICE, skipping post-build steps..."
        continue
    fi

    echo "📦 Copying Image to $BOOTIMAGE_DIR"
    cp "$IMAGE_PATH" "$DEST_IMAGE_PATH"

    cd "$BOOTIMAGE_DIR" || { echo "❌ Failed to enter $BOOTIMAGE_DIR"; continue; }

    ./magiskboot unpack boot.img
    rm -f kernel
    mv Image kernel

    REPACKED_NAME="FrEeRuNnErKeRnEl-${DEVICE}-${KERNEL_VERSION}.img"
    ./magiskboot repack boot.img "$REPACKED_NAME"

    if [ -f "$REPACKED_NAME" ]; then
        echo "📤 Moving repacked image to $FREERUNNER_OUTPUT"
        mv "$REPACKED_NAME" "$FREERUNNER_OUTPUT/"

        echo "📤 Preparing Odin tar.md5"
        cp "$FREERUNNER_OUTPUT/$REPACKED_NAME" "$TEMP_DIR/boot.img"
        cd "$TEMP_DIR"
        tar -H ustar -c boot.img > "FrEeRuNnErKeRnEl-${DEVICE}-${KERNEL_VERSION}.tar"
        md5sum -t "FrEeRuNnErKeRnEl-${DEVICE}-${KERNEL_VERSION}.tar" | cut -d ' ' -f1 >> "FrEeRuNnErKeRnEl-${DEVICE}-${KERNEL_VERSION}.tar"
        mv "FrEeRuNnErKeRnEl-${DEVICE}-${KERNEL_VERSION}.tar" "$FREERUNNER_OUTPUT/FrEeRuNnErKeRnEl-${DEVICE}-${KERNEL_VERSION}.tar.md5"
        rm -f boot.img
        cd "$KERNEL_DIR"
    else
        echo "❌ Failed to repack for $DEVICE"
    fi
done

# All builds are done, now prompt for release
echo -e "\n📦 All device builds complete."

read -p "📝 Do you want to create a GitHub release for FrEeRuNnErKeRnEl-$KERNEL_VERSION? (yes/no): " RELEASE_ANSWER

if [[ "$RELEASE_ANSWER" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "🌐 Logging in to GitHub CLI..."
    gh auth login

    RELEASE_TAG="$KERNEL_VERSION"
    RELEASE_TITLE="FrEeRuNnErKeRnEl-$KERNEL_VERSION"

    echo "🚀 Creating GitHub release $RELEASE_TITLE with tag $RELEASE_TAG"
    gh release create "$RELEASE_TAG" "$FREERUNNER_OUTPUT"/*."img" "$FREERUNNER_OUTPUT"/*.tar.md5 \
        --title "$RELEASE_TITLE" \
        --repo "LeDrew2017/FreeRunnerKernel" \
        --draft

    echo "🚀 Release $RELEASE_TITLE created."
else
    echo "🚫 Release skipped."
fi

# Cleanup - remove all files in bootimage directories except magiskboot
echo -e "\n🧹 Cleaning up unnecessary files in $BOOTIMAGE_BASE"
find "$BOOTIMAGE_BASE" -type f ! -name 'magiskboot' -exec rm -f {} \;
echo "🧹 Cleanup completed!"

