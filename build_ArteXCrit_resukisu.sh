#!/usr/bin/env bash
set -euo pipefail

KDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$KDIR"

DEFCONFIG="marble_defconfig"
OUT_DIR="$KDIR/out"

# ReSukiSU
RESUKISU_DIR="$KDIR/KernelSU"
RESUKISU_REF="f4c4923e1884050b072be8cefe876746c07f0e8c"

# SUSFS
SUSFS_DIR="$KDIR/susfs4ksu"
SUSFS_BRANCH="gki-android12-5.10"

# Toolchain
CLANG_PATH="$HOME/build_toolchain/llvm-23.1.0-x86_64/bin"

export PATH="$CLANG_PATH:$PATH"

export ARCH=arm64
export SUBARCH=arm64
export LLVM=1
export LLVM_IAS=1

export LOCALVERSION="-ArteXCrit"

echo "=========================================="
echo " ArteXCrit Kernel - ReSukiSU + SUSFS"
echo "=========================================="
echo "Kernel : $KDIR"
echo "Output : $OUT_DIR"
echo "Defconfig : $DEFCONFIG"
echo

# --------------------------------------------------
# 1. Clean build tree
# --------------------------------------------------

echo "[1/7] Cleaning build tree..."

make mrproper

# --------------------------------------------------
# 2. Get ReSukiSU
# --------------------------------------------------

echo "[2/7] Setting up ReSukiSU..."

if [ ! -d "$RESUKISU_DIR/.git" ]; then
    git clone https://github.com/ReSukiSU/ReSukiSU "$RESUKISU_DIR"
fi

cd "$RESUKISU_DIR"

git fetch --all --tags
git reset --hard "$RESUKISU_REF"

cd "$KDIR"

# ReSukiSU official setup script
curl -LSs \
    "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" \
    | bash

# --------------------------------------------------
# 3. Get SUSFS
# --------------------------------------------------

echo "[3/7] Setting up SUSFS..."

if [ ! -d "$SUSFS_DIR/.git" ]; then
    git clone \
        --branch "$SUSFS_BRANCH" \
        --depth 1 \
        https://gitlab.com/simonpunk/susfs4ksu.git \
        "$SUSFS_DIR"
else
    cd "$SUSFS_DIR"

    git fetch origin "$SUSFS_BRANCH"

    git checkout "$SUSFS_BRANCH"

    git reset --hard "origin/$SUSFS_BRANCH"

    cd "$KDIR"
fi

# --------------------------------------------------
# 4. Apply SUSFS kernel-side files
# --------------------------------------------------

echo "[4/7] Applying SUSFS kernel patches..."

cp -f "$SUSFS_DIR/kernel_patches/fs/"* \
    "$KDIR/fs/"

cp -f "$SUSFS_DIR/kernel_patches/include/linux/"* \
    "$KDIR/include/linux/"

SUSFS_PATCH="$SUSFS_DIR/kernel_patches/50_add_susfs_in_gki-android12-5.10.patch"

if [ ! -f "$SUSFS_PATCH" ]; then
    echo "ERROR: SUSFS patch not found:"
    echo "$SUSFS_PATCH"
    exit 1
fi

echo "Checking SUSFS patch..."

git apply --check "$SUSFS_PATCH"

echo "Applying SUSFS patch..."

git apply "$SUSFS_PATCH"

# --------------------------------------------------
# 5. Generate kernel config
# --------------------------------------------------

echo "[5/7] Generating kernel config..."

make O="$OUT_DIR" "$DEFCONFIG"

# ReSukiSU + SUSFS
"$KDIR/scripts/config" \
    --file "$OUT_DIR/.config" \
    -e KSU \
    -d KSU_TRACEPOINT_HOOK \
    -d KSU_MANUAL_HOOK \
    -e KSU_SUSFS

# Resolve dependencies
make O="$OUT_DIR" olddefconfig

echo
echo "KernelSU configuration:"
echo

grep -E \
    '^(CONFIG_KSU=|CONFIG_KSU_SUSFS=|CONFIG_KSU_MANUAL_HOOK=|CONFIG_KSU_TRACEPOINT_HOOK=)' \
    "$OUT_DIR/.config" || true

# --------------------------------------------------
# 6. Build kernel
# --------------------------------------------------

echo
echo "[6/7] Building kernel..."
echo

make \
    O="$OUT_DIR" \
    LLVM=1 \
    LLVM_IAS=1 \
    ARCH=arm64 \
    -j"$(nproc)" \
    KCFLAGS="-O3" \
    KBUILD_LDFLAGS="-O3 --lto-O3"

# --------------------------------------------------
# 7. Check output
# --------------------------------------------------

echo
echo "[7/7] Checking output..."
echo

IMAGE="$OUT_DIR/arch/arm64/boot/Image"

if [ ! -f "$IMAGE" ]; then
    echo "ERROR: Kernel Image was not generated!"
    exit 1
fi

echo "=========================================="
echo " BUILD SUCCESS"
echo "=========================================="
echo
echo "Image:"
echo "$IMAGE"
echo
ls -lh "$IMAGE"
echo
