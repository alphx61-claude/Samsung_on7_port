#!/bin/sh
# Build the msm8916 mainline kernel with the On7 display patches applied.
#
# This is for quickly checking that the patches build and that the device tree
# compiles. To build something you can actually flash, use pmbootstrap instead
# (see docs/INSTALL.md).
#
# Usage: scripts/build-kernel.sh [workdir]
set -eu

REPO_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORK_DIR=${1:-$REPO_DIR/build}
KERNEL_TAG=v6.12.1-msm8916
KERNEL_URL=https://github.com/msm8916-mainline/linux.git
SRC_DIR=$WORK_DIR/linux

: "${JOBS:=$(nproc)}"
export ARCH=arm64

# pmaports builds this kernel with LLVM=1, so do the same here.
MAKE_ARGS="LLVM=1"

for tool in git make dtc clang ld.lld llvm-objcopy; do
	command -v "$tool" >/dev/null || {
		echo "error: $tool not found in PATH" >&2
		echo "hint: apt install git make device-tree-compiler clang lld llvm" >&2
		exit 1
	}
done

mkdir -p "$WORK_DIR"

if [ ! -d "$SRC_DIR" ]; then
	echo ">> Cloning $KERNEL_TAG"
	git clone --depth 1 --branch "$KERNEL_TAG" "$KERNEL_URL" "$SRC_DIR"
fi

cd "$SRC_DIR"

if ! git rev-parse --verify -q on7-display >/dev/null; then
	echo ">> Applying patches"
	git checkout -q -b on7-display
	git am "$REPO_DIR"/kernel/patches/*.patch
else
	echo ">> Patches already applied, reusing branch on7-display"
	git checkout -q on7-display
fi

echo ">> Configuring"
if [ ! -f "$WORK_DIR/config-postmarketos-qcom-msm8916.aarch64" ]; then
	curl -fsSL -o "$WORK_DIR/config-postmarketos-qcom-msm8916.aarch64" \
		"https://gitlab.postmarketos.org/postmarketOS/pmaports/-/raw/main/device/testing/linux-postmarketos-qcom-msm8916/config-postmarketos-qcom-msm8916.aarch64"
fi
cp "$WORK_DIR/config-postmarketos-qcom-msm8916.aarch64" .config
cat "$REPO_DIR/pmaports/linux-postmarketos-qcom-msm8916/on7-display.config" >> .config
make $MAKE_ARGS olddefconfig

echo ">> Building (-j$JOBS)"
make $MAKE_ARGS "-j$JOBS" Image.gz modules dtbs

echo
echo "Built:"
echo "  $SRC_DIR/arch/arm64/boot/Image.gz"
echo "  $SRC_DIR/arch/arm64/boot/dts/qcom/msm8916-samsung-on7.dtb"
find "$SRC_DIR/drivers/gpu/drm/panel" "$SRC_DIR/drivers/video/backlight" \
	-name 'panel-samsung-s6d7aa0x62*.ko' \
	-o -name 'panel-samsung-ili9881c*.ko' \
	-o -name 'ti-lmu-backlight.ko' | sed 's/^/  /'
