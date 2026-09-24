# No C sources: app_main comes from the PXX-built archive made by ../build.sh.
# esp_driver_rmt is REQUIRED because the Pascal program drives the WS2812
# through the RMT peripheral.
idf_component_register(REQUIRES esp_driver_rmt)

add_prebuilt_library(pxx_app "${CMAKE_CURRENT_LIST_DIR}/libpxx_app.a"
                     REQUIRES esp_driver_rmt)
target_link_libraries(${COMPONENT_LIB} INTERFACE pxx_app)

# Nothing in this component references app_main, so force the linker to keep
# the archive member that defines it.
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u app_main")
