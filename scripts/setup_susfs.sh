#!/bin/bash
set -e

SUSFS_VERSION="v1.5.1"

echo "==> 1. Klonowanie ReSukiSU bezpośrednio do drzewa kernela..."
rm -rf KernelSU drivers/kernelsu
git clone https://github.com/ReSukiSU/ReSukiSU.git KernelSU --depth=1

echo "==> 2. Klonowanie SusFS z GitHub Mirror..."
rm -rf susfs_src
# Pobieramy bezpośrednio jako repozytorium z GitHuba - to zawsze działa w Actions
git clone https://github.com/Geon-Mo/susfs4ksu.git -b gki-android12-5.4-susfs-${SUSFS_VERSION} susfs_src --depth=1

echo "==> 3. Kopiowanie plików źródłowych SusFS..."
cp susfs_src/kernel/include/linux/susfs.h include/linux/
cp susfs_src/kernel/fs/susfs.c fs/

echo "==> 4. Patchowanie ReSukiSU pod SusFS..."
patch -p1 < susfs_src/KernelSU/10_add_susfs_in_ksu.patch

echo "==> 5. Ręczne wstrzykiwanie SusFS do rdzenia kernela Samsunga (Sed)..."
if ! grep -q "obj-y += susfs.o" fs/Makefile; then
    echo "obj-y += susfs.o" >> fs/Makefile
fi

sed -i '/int do_sys_open(int dfd, const char __user \*filename, int flags, umode_t mode)/{:a;n;/^}/{i\\t#ifdef CONFIG_SUSFS\n\t\tif (current->susfs_task_state & 1) {\n\t\t\tint out_fd = susfs_open_block_by_processname(dfd, filename, flags, mode);\n\t\t\tif (out_fd < 0) return out_fd;\n\t\t}\n\t#endif\n;b};ba}' fs/open.c

sed -i '/int vfs_statx(int dfd, const char __user \*filename, int flags,/ {n;n;i\\t#ifdef CONFIG_SUSFS\n\t\tif (current->susfs_task_state & 1) {\n\t\t\tint error = susfs_stat_block_by_processname(dfd, filename, flags, stat);\n\t\t\tif (error < 0) return error;\n\t\t}\n\t#endif\n}' fs/stat.c

sed -i '/int\s*make_it_fail;/i \\t#ifdef CONFIG_SUSFS\n\tunsigned long susfs_task_state;\n\t#endif' include/linux/sched.h

echo "==> 6. Integracja hooka KSU w głównym Makefile..."
if ! grep -q "obj-y += KernelSU/" Makefile; then
    echo "obj-y += KernelSU/" >> Makefile
fi

echo "==> 7. Sprzątanie plików tymczasowych..."
rm -rf susfs_src
echo "==> Proces integracji ReSukiSU + SusFS zakończony powodzeniem!"
