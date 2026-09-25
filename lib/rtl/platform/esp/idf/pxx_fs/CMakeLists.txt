# SPDX-License-Identifier: Zlib
# FAT-on-flash for NilPy's open()/os on an ESP; pxx_fs.c says how it is found.
# A project uses it with lib/rtl/platform/esp/idf in EXTRA_COMPONENT_DIRS,
# pxx_fs in main's REQUIRES, and a `storage, data, fat` partition.
idf_component_register(SRCS "pxx_fs.c"
                       REQUIRES fatfs wear_levelling esp_partition)
# pypal's reference is WEAK, and a weak reference does not pull an archive
# member into the link -- so keep it explicitly.
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u pxx_fs_mount")
