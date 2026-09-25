# SPDX-License-Identifier: 0BSD
# No C sources: app_main comes from the PXX-built object, wrapped into a static
# archive by build.sh. esp_driver_spi is what lib/rtl/platform/esp/espspi.pas
# calls into.
idf_component_register(REQUIRES esp_timer esp_driver_spi)

add_prebuilt_library(pxx_app "${CMAKE_CURRENT_LIST_DIR}/libpxx_app.a"
                     REQUIRES esp_timer esp_driver_spi)
target_link_libraries(${COMPONENT_LIB} INTERFACE pxx_app)
# Nothing in this component references app_main, so force the linker to keep
# pulling it from the archive (ESP-IDF's startup task calls it).
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u app_main")
