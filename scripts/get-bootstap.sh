#!/bin/sh
# Fetches the pinned LLVM-IR bootstrap into boot/
set -eu
REV=$(cat BOOTSTRAP_REV)
BOOT_URL=https://github.com/zakwilson/nucleus-boot.git

if [ -d boot ]; then
    echo "boot/ already exists; remove it to refresh" >&2; exit 0
fi

git clone --no-checkout --depth 1 --branch "$REV" "$BOOT_URL" boot-tmp
git -C boot-tmp checkout
mv boot-tmp/boot boot
rm -rf boot-tmp
