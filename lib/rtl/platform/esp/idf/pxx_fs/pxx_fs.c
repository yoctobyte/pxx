// SPDX-License-Identifier: Zlib
// The filesystem a NilPy program sees on an ESP32: FAT on flash, with wear
// levelling, in the partition table's `storage` FAT partition, mounted at the
// IDF prefix /fs. compiler/builtin/pypal.pas maps Python's "/" onto /fs, so a
// program written for MicroPython -- open("/config.json"), os.listdir("/") --
// runs unchanged, and the prefix never reaches Python code.
//
// OPT-IN, PER PROJECT: add pxx_fs to main's REQUIRES and a `storage` row to
// partitions.csv (examples/esp32/fs-c3 has the row and the sdkconfig this
// reuses). pypal calls pxx_fs_mount through a WEAK reference, once, on the
// first path the program names, so it runs in a task and not at boot; a
// project without this component links with that reference nil and has no
// filesystem at all (every path answers ENOENT). A weak reference does not
// pull an archive member in, which is why CMakeLists.txt forces it with -u.
//
// A partition that will not mount is FORMATTED, as MicroPython does on first
// boot: a fresh board has an erased partition and a program expects to write.
#include "esp_log.h"
#include "esp_partition.h"
#include "esp_vfs_fat.h"
#include "wear_levelling.h"

static const char *TAG = "pxx-fs";
static int s_state;             // 0 not tried, 1 mounted, -1 no filesystem

int pxx_fs_mount(void)
{
    if (s_state != 0)
        return s_state > 0 ? 0 : -1;
    s_state = -1;
    if (!esp_partition_find_first(ESP_PARTITION_TYPE_DATA,
                                  ESP_PARTITION_SUBTYPE_DATA_FAT, "storage")) {
        ESP_LOGW(TAG, "no `storage` FAT partition: no filesystem");
        return -1;
    }
    esp_vfs_fat_mount_config_t cfg = {
        .format_if_mount_failed = true,
        .max_files = 8,
        .allocation_unit_size = 0,
    };
    wl_handle_t wl;
    esp_err_t e = esp_vfs_fat_spiflash_mount_rw_wl("/fs", "storage", &cfg, &wl);
    if (e != ESP_OK) {
        ESP_LOGE(TAG, "mount failed: %s", esp_err_to_name(e));
        return -1;
    }
    s_state = 1;
    return 0;
}

// open()'s flags, from LINUX numbering (what pypal and Python's os module
// speak) to THIS libc's. In C, and here, so that the numbers come from the
// libc the project is actually built with rather than from a table: IDF 6
// builds with picolibc (O_CREAT 0x40, O_TRUNC 0x200, O_APPEND 0x400), and a
// table copied from newlib's headers (0x200, 0x400, 0x8) made "w" APPEND and
// "a" on a missing file fail ENOENT, on silicon, with no diagnostic.
// pypal calls this through the same WEAK reference as pxx_fs_mount; without
// this component there is no filesystem to open anything on.
#include <fcntl.h>

int pxx_fs_oflags(int linux_flags)
{
    int f = linux_flags & 3;            // O_RDONLY/O_WRONLY/O_RDWR: 0/1/2 in every libc here
    if (linux_flags & 0100)  f |= O_CREAT;
    if (linux_flags & 0200)  f |= O_EXCL;
    if (linux_flags & 01000) f |= O_TRUNC;
    if (linux_flags & 02000) f |= O_APPEND;
    return f;
}
