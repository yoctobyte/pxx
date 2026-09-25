# SPDX-License-Identifier: Zlib
# The C half of mimic_network.pas / mimic_esp32.pas; pxx_esp.c says why it is C.
# A project uses it with, in its top-level CMakeLists.txt,
#   set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_LIST_DIR}/../../../lib/rtl/platform/esp/idf")
# and pxx_esp in main's REQUIRES.
idf_component_register(SRCS "pxx_esp.c"
                       REQUIRES esp_wifi esp_netif esp_event nvs_flash esp_driver_tsens)
