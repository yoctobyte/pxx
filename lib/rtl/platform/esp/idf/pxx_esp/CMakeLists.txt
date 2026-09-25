# SPDX-License-Identifier: Zlib
# The C half of mimic_network.pas / mimic_esp32.pas; pxx_esp.c says why it is C.
# A project uses it with, in its top-level CMakeLists.txt,
#   set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_LIST_DIR}/../../../lib/rtl/platform/esp/idf")
# and pxx_esp in main's REQUIRES.
idf_component_register(SRCS "pxx_esp.c"
                       REQUIRES esp_wifi esp_netif esp_event nvs_flash esp_driver_tsens)
# Pull esp_netif_init in even when the program never touches `network`:
# platform_backend's PalBackendSocket starts lwIP's TCP/IP task through a WEAK
# reference to it (a socket on 127.0.0.1 needs the task, not the radio), and a
# weak undefined symbol does not make the linker take a member out of an
# archive. Without this, a NilPy program that only serves loopback HTTP asserts
# in lwip_socket and reboots (measured under the S3's QEMU, 2026-09-25).
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u esp_netif_init")
