/* __attribute__((section)) in a freestanding ESP object (Gibux's ESP32-S3
   port): .iram1* functions go to .iram1.text with their literals; a global of
   any section name gets an ELF section of that name. Checked by
   tools/check_esp_section_attr.py (link + read back), not run.
   feature-c-section-attribute-on-esp */
typedef struct {
    unsigned magic, secure_version, reserv1[2];
    char version[32], project_name[32], time[16], date[16], idf_ver[32];
    unsigned char app_elf_sha256[32];
    unsigned reserv2[20];
} app_desc_t;

/* the IDF app descriptor: unreferenced, first in DROM, must survive */
__attribute__((section(".rodata_desc"), used))
const app_desc_t esp_app_desc = { 0xABCD5432, 3, {0, 0}, "gibux-0.1", "gibux" };

static __attribute__((section(".rodata_desc"), used)) const unsigned desc_tail = 0x11223344;

int counter = 3;
__attribute__((section(".dram1.flags"))) int flags = 0x55;
__attribute__((section(".noinit.keep"))) int keep;

/* IDF spells it IRAM_ATTR = section(".iram1" "." "N") */
__attribute__((section(".iram1" "." "7"))) static int cache_init(int x) { return x * 2 + 0x12345; }

/* a flash routine BETWEEN the two iram ones: .iram1.text packs them, so a
   direct call computed from their Code[] distance would miss */
int flash_mid(int x) { return x - 1; }

__attribute__((section(".iram1.text"))) int xtensa_start(int x)
{
    counter += cache_init(x);
    flags++;
    keep = 1;
    return counter + 0x7654321;
}

int later(int x) { return xtensa_start(x) + flash_mid(x); }
