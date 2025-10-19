#!/bin/bash

set -e

DEVICES=("beyond0lte" "beyond1lte" "beyond2lte" "beyondx" "d1" "d1x" "d2s" "d2x" "f62")
KERNEL_DIR="$(pwd)"
OUT_BASE="$KERNEL_DIR/out"
AK3_DIR="$KERNEL_DIR/AnyKernel"
AK3_REPO="https://github.com/LeDrew2017/Anykernel.git"
TOOLCHAIN_DIR="/home/jay/toolchains/clang-21"
GITHUB_REPO="git@github.com:LeDrew2017/FreeRunnerKernel.git"

export PATH="$TOOLCHAIN_DIR/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER="Jay"
export KBUILD_BUILD_HOST="CachyOS"

if command -v ccache &> /dev/null; then
    export CC="ccache clang"
    export CXX="ccache clang++"
    echo "🚀 Using ccache to speed up compilation."
else
    export CC="clang"
    export CXX="clang++"
fi

CONFIG_FRAGMENTS=()

perform_clean() {
    echo "🧹 Cleaning all output directories..."
    rm -rf "$OUT_BASE"
    echo "✅ Clean complete."
}

apply_kpm_patch() {
    local image_to_patch="$1"

    echo "DEBUG: CONFIG_FRAGMENTS = ${CONFIG_FRAGMENTS[*]}"

    if [[ "${CONFIG_FRAGMENTS[*]}" != *"sukisu.config"* ]]; then
        echo "INFO: Skipping KPM patch (sukisu not selected)"
        return 0
    fi

    echo -e "\n📝 Applying KPM patch..."

    local KPM_URL="https://raw.githubusercontent.com/ShirkNeko/SukiSU_patch/refs/heads/main/kpm/patch_linux"
    local MAGISKBOOT="$KERNEL_DIR/magiskboot/magiskboot"
    local WORK_DIR="$KERNEL_DIR/kpm_work"

    if [[ ! -f "$MAGISKBOOT" ]] || [[ ! -x "$MAGISKBOOT" ]]; then
        echo "❌ ERROR: magiskboot not found or not executable at $MAGISKBOOT"
        return 1
    fi

    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    if ! curl -LSs "$KPM_URL" -o patch; then
        echo "❌ ERROR: Failed to download KPM patch script"
        cd "$KERNEL_DIR"
        rm -rf "$WORK_DIR"
        return 1
    fi
    chmod +x patch

    if [[ ! -f "$image_to_patch" ]]; then
        echo "❌ ERROR: Kernel image not found at $image_to_patch"
        cd "$KERNEL_DIR"
        rm -rf "$WORK_DIR"
        return 1
    fi

    cp "$image_to_patch" .
    local img_file=$(basename "$image_to_patch")

    if [[ "$img_file" == *"Image.gz-dtb" ]]; then
        echo "INFO: Extracting kernel from Image.gz-dtb..."
        if ! "$MAGISKBOOT" split "$img_file" || [[ ! -f kernel ]]; then
            echo "❌ ERROR: Failed to split $img_file"
            cd "$KERNEL_DIR"
            rm -rf "$WORK_DIR"
            return 1
        fi
        cp kernel Image
    elif [[ "$img_file" == *"Image.gz" ]]; then
        echo "INFO: Decompressing Image.gz..."
        if ! "$MAGISKBOOT" decompress "$img_file" Image 2>/dev/null && ! gunzip -c "$img_file" > Image 2>/dev/null; then
            echo "❌ ERROR: Failed to decompress $img_file"
            cd "$KERNEL_DIR"
            rm -rf "$WORK_DIR"
            return 1
        fi
    elif [[ "$img_file" == *"Image" ]]; then
        cp "$img_file" Image
    else
        echo "❌ ERROR: Unsupported kernel image format: $img_file"
        cd "$KERNEL_DIR"
        rm -rf "$WORK_DIR"
        return 1
    fi

    if [[ ! -f Image ]]; then
        echo "❌ ERROR: Image file not found after extraction"
        cd "$KERNEL_DIR"
        rm -rf "$WORK_DIR"
        return 1
    fi

    echo "INFO: Patching kernel..."
    if ./patch 2>&1; then
        if [[ -f oImage ]]; then
            mv oImage Image
        fi
    else
        echo "❌ ERROR: KPM patch script failed"
        cd "$KERNEL_DIR"
        rm -rf "$WORK_DIR"
        return 1
    fi

    echo "INFO: Repacking kernel image..."
    if [[ "$img_file" == *"Image.gz-dtb" ]]; then
        if ! "$MAGISKBOOT" compress=gzip Image kernel_new && ! gzip -c Image > kernel_new; then
            echo "❌ ERROR: Failed to compress patched Image"
            cd "$KERNEL_DIR"
            rm -rf "$WORK_DIR"
            return 1
        fi

        if [[ ! -f kernel_dtb ]]; then
            echo "❌ ERROR: kernel_dtb not found, cannot recreate Image.gz-dtb"
            cd "$KERNEL_DIR"
            rm -rf "$WORK_DIR"
            return 1
        fi

        cat kernel_new kernel_dtb > Image.gz-dtb
        cp Image.gz-dtb "$image_to_patch"
    elif [[ "$img_file" == *"Image.gz" ]]; then
        if ! gzip -c Image > Image.gz; then
            echo "❌ ERROR: Failed to compress patched Image"
            cd "$KERNEL_DIR"
            rm -rf "$WORK_DIR"
            return 1
        fi
        cp Image.gz "$image_to_patch"
    else
        cp Image "$image_to_patch"
    fi

    echo "✅ INFO: KPM patching completed successfully"
    cd "$KERNEL_DIR"
    rm -rf "$WORK_DIR"
    return 0
}

build_device() {
    local device="$1"
    local kernel_version="$2"
    local defconfig="exynos9820-${device}_defconfig"
    local out_dir="${OUT_BASE}/${device}"
    local image_path="$out_dir/arch/arm64/boot/Image"

    echo -e "\n🔧 Starting build for: $device"

    make -C "$KERNEL_DIR" O="$out_dir" "$defconfig" LLVM=1

    if [ ${#CONFIG_FRAGMENTS[@]} -gt 0 ]; then
        echo "📝 Merging config fragments: ${CONFIG_FRAGMENTS[*]}"
        "$KERNEL_DIR/scripts/kconfig/merge_config.sh" -O "$out_dir" \
            "$out_dir/.config" "${CONFIG_FRAGMENTS[@]}"
        make -C "$KERNEL_DIR" O="$out_dir" olddefconfig LLVM=1
    fi

    local build_start
    build_start=$(date +%s)
    make -C "$KERNEL_DIR" O="$out_dir" -j"$(nproc)" LLVM=1
    local build_end
    build_end=$(date +%s)
    local duration=$((build_end - build_start))

    if [ ! -f "$image_path" ]; then
        echo "❌ Build FAILED for $device after $(printf "%02d:%02d" $((duration/60)) $((duration%60)))"
        return 1
    fi
    echo "✅ Build completed for $device in $(printf "%02d:%02d" $((duration/60)) $((duration%60)))"

    if ! apply_kpm_patch "$image_path"; then
        echo "❌ ERROR: KPM patching failed for $device"
        return 1
    fi

    echo "🧹 Cleaning up old kernel image from AnyKernel directory (if any)..."
    rm -f "${AK3_DIR}/Image"

    echo "📦 Copying new kernel Image to AnyKernel directory..."
    cp "$image_path" "$AK3_DIR/Image"

    pushd "$AK3_DIR" > /dev/null

    local config_suffix=""
    if [ ${#CONFIG_FRAGMENTS[@]} -gt 0 ]; then
        for fragment in "${CONFIG_FRAGMENTS[@]}"; do
            local frag_name=$(basename "$fragment" .config)
            config_suffix="${config_suffix}-${frag_name}"
        done
    fi

    local zip_name="FrEeRuNnErKeRnEl-${device}-${kernel_version}${config_suffix}-Anykernel3.zip"
    echo "📦 Creating AnyKernel zip: $zip_name..."
    zip -r9 "$zip_name" * -x .git\* README.md\*

    if [ -f "$zip_name" ]; then
        mv "$zip_name" "$RELEASE_DIR/"
        echo "✅ Packaged $zip_name successfully."
        rm -f Image
    else
        echo "❌ Failed to create AnyKernel zip for $device."
    fi

    popd > /dev/null
}

create_github_release() {
    if [ -z "$RELEASE_TAG_VERSION" ]; then
        echo "⚠️ Kernel version for release tag not set. Skipping release."
        return
    fi

    if ! ls "$RELEASE_DIR"/*.zip &> /dev/null; then
        echo "⚠️ No .zip files found in the releases folder. Skipping release."
        return
    fi

    echo -e "\n--- GitHub Release ---"
    read -p "Do you want to create a GitHub release with tag '$RELEASE_TAG_VERSION'? (y/N): " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        echo "Skipping GitHub release."
        exit 0
    fi

    read -p "Enter Release Title: " release_title

    local temp_notes_file
    temp_notes_file=$(mktemp)
    echo "Press Enter to open your default editor (${EDITOR:-nano}) to write the release notes."
    read -r

    ${EDITOR:-nano} "$temp_notes_file"

    if [ ! -s "$temp_notes_file" ]; then
        echo "❌ Release notes are empty. Aborting release."
        rm "$temp_notes_file"
        exit 1
    fi

    echo "🚀 Creating release and uploading artifacts..."
    gh release create "$RELEASE_TAG_VERSION" "$RELEASE_DIR"/*.zip \
        -R "$GITHUB_REPO" \
        --title "$release_title" \
        --notes-file "$temp_notes_file"

    echo "✅ GitHub release created successfully."
    rm "$temp_notes_file"
}

if [[ "$1" == "--clean" ]]; then
    perform_clean
    exit 0
fi

if ! command -v git &> /dev/null || ! command -v zip &> /dev/null; then
    echo "❌ Git or zip is not installed. Please install them to continue."
    exit 1
fi
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed. Please install it to create releases."
    exit 1
fi

if [ ! -d "$AK3_DIR" ]; then
    echo "AnyKernel directory not found. Cloning from repository..."
    git clone "$AK3_REPO" "$AK3_DIR"
fi

echo -e "\n--- Config Fragment Selection ---"
echo "Available config fragments:"
echo "  1) None (default build)"
echo "  2) KernelSU (ksu.config)"
echo "  3) Sukisu (sukisu.config)"
echo "  4) Both KernelSU + Sukisu"
read -p "Select config option (1-4) [default: 1]: " config_choice

case "$config_choice" in
    2)
        CONFIG_FRAGMENTS+=("$KERNEL_DIR/arch/arm64/configs/ksu.config")
        echo "✓ Selected: KernelSU"
        ;;
    3)
        CONFIG_FRAGMENTS+=("$KERNEL_DIR/arch/arm64/configs/sukisu.config")
        echo "✓ Selected: Sukisu"
        ;;
    4)
        CONFIG_FRAGMENTS+=("$KERNEL_DIR/arch/arm64/configs/ksu.config")
        CONFIG_FRAGMENTS+=("$KERNEL_DIR/arch/arm64/configs/sukisu.config")
        echo "✓ Selected: KernelSU + Sukisu"
        ;;
    1|"")
        echo "✓ Selected: Default build (no fragments)"
        ;;
    *)
        echo "❌ Invalid selection. Using default build."
        ;;
esac

for fragment in "${CONFIG_FRAGMENTS[@]}"; do
    if [ ! -f "$fragment" ]; then
        echo "❌ Config fragment not found: $fragment"
        exit 1
    fi
done

RELEASE_DIR="$KERNEL_DIR/releases"
mkdir -p "$RELEASE_DIR"
RELEASE_TAG_VERSION=""

echo -e "\nPlease select a device to build:"
for i in "${!DEVICES[@]}"; do
    printf "  %2d) %s\n" "$((i+1))" "${DEVICES[i]}"
done
all_option_num=$(( ${#DEVICES[@]} + 1 ))
printf "  %2d) %s\n" "$all_option_num" "Build All Devices"

read -p "Enter number (1-$all_option_num): " selection

if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$all_option_num" ]; then
    echo "❌ Invalid selection. Please enter a number between 1 and $all_option_num."
    exit 1
fi

if [ "$selection" -eq "$all_option_num" ]; then
    echo -e "\n👍 You selected: Build All Devices. The releases folder will NOT be cleaned."

    first_device=true
    for device in "${DEVICES[@]}"; do
        echo "=================================================="
        echo "Processing: $device"
        DEFCONFIG_PATH="arch/arm64/configs/exynos9820-${device}_defconfig"
        if [ ! -f "$DEFCONFIG_PATH" ]; then
            echo "⚠️ Defconfig for $device not found. Skipping."
            continue
        fi
        RAW_VERSION=$(grep 'CONFIG_LOCALVERSION=' "$DEFCONFIG_PATH" | cut -d'"' -f2)
        KERNEL_VERSION=$(echo "$RAW_VERSION" | grep -oP 'v[0-9]+(\.[0-9]+)*')

        if [ -z "$KERNEL_VERSION" ]; then
            echo "⚠️ Could not extract kernel version for $device. Skipping."
            continue
        fi
        echo "🔖 Detected kernel version for $device: $KERNEL_VERSION"

        if [ "$first_device" = true ]; then
            RELEASE_TAG_VERSION="$KERNEL_VERSION"
            first_device=false
        fi

        build_device "$device" "$KERNEL_VERSION"
    done
    echo -e "\n🎉 All builds are complete."

    create_github_release

else
    echo "🧹 Cleaning releases folder for single device build..."
    rm -f "$RELEASE_DIR"/*
    SELECTED_DEVICE="${DEVICES[((selection-1))]}"
    echo -e "\n👍 You selected: $SELECTED_DEVICE"

    DEFCONFIG_PATH="arch/arm64/configs/exynos9820-${SELECTED_DEVICE}_defconfig"
    if [ ! -f "$DEFCONFIG_PATH" ]; then
        echo "❌ Defconfig for selected device ($SELECTED_DEVICE) not found at '$DEFCONFIG_PATH'."
        exit 1
    fi
    RAW_VERSION=$(grep 'CONFIG_LOCALVERSION=' "$DEFCONFIG_PATH" | cut -d'"' -f2)
    KERNEL_VERSION=$(echo "$RAW_VERSION" | grep -oP 'v[0-9]+(\.[0-9]+)*')

    if [ -z "$KERNEL_VERSION" ]; then
        echo "❌ Could not extract kernel version from '$DEFCONFIG_PATH'."
        exit 1
    fi
    echo "🔖 Detected kernel version for this build: $KERNEL_VERSION"
    RELEASE_TAG_VERSION="$KERNEL_VERSION"

    build_device "$SELECTED_DEVICE" "$KERNEL_VERSION"
    echo -e "\n🎉 Build for $SELECTED_DEVICE is complete."
fi
