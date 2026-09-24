# SPDX-License-Identifier: 0BSD
# No C sources: app_main comes from the PXX-built object, wrapped into a static
# archive by build.sh. nvs_flash is what lib/rtl/platform/esp/espnvs.pas calls.
idf_component_register(REQUIRES esp_timer nvs_flash)

add_prebuilt_library(pxx_app "${CMAKE_CURRENT_LIST_DIR}/libpxx_app.a"
                     REQUIRES esp_timer nvs_flash)
target_link_libraries(${COMPONENT_LIB} INTERFACE pxx_app)
# Nothing in this component references app_main, so force the linker to keep
# pulling it from the archive (ESP-IDF's startup task calls it).
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u app_main")
