# No C sources: app_main comes from the PXX-built object, wrapped into a static
# archive by build.sh. The NilPy runtime is linked whole (its socket, file and
# timer surface included), so it needs lwip and esp_timer whatever the program
# does -- same REQUIRES as hello-c3, for the same reason. esp_driver_gpio is
# this demo's own: lib/rtl/platform/esp/espgpio.pas calls into it. esp_driver_spi
# is for the board tests that borrow this project through PXX_MAIN
# (test/esp_board_spi_surface.npy); an archive the program does not call adds
# nothing to the image (measured 2026-09-25: the default nilpy-hw-s3 image is
# 0x132ed0 bytes with it and without it, after a reconfigure and relink).
idf_component_register(REQUIRES esp_timer esp_driver_gpio esp_driver_spi esp_driver_i2c esp_driver_rmt lwip esp_netif)

add_prebuilt_library(pxx_app "${CMAKE_CURRENT_LIST_DIR}/libpxx_app.a"
                     REQUIRES esp_timer esp_driver_gpio esp_driver_spi esp_driver_i2c esp_driver_rmt lwip esp_netif)
target_link_libraries(${COMPONENT_LIB} INTERFACE pxx_app)
# Nothing in this component references app_main, so force the linker to keep
# pulling it from the archive (ESP-IDF's startup task calls it).
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u app_main")
