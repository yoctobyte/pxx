# No C sources of its own: app_main comes from the PXX-built object, wrapped
# into a static archive by build.sh. lwip/esp_netif/esp_timer are the NilPy
# runtime's (as in hello-c3); esp_adc and esp_driver_gpio are espadc's;
# pxx_esp is `import network` and `import esp32`; pxx_fs is the filesystem
# open() and os see.
idf_component_register(REQUIRES esp_timer esp_driver_gpio esp_adc lwip esp_netif pxx_esp pxx_fs)

add_prebuilt_library(pxx_app "${CMAKE_CURRENT_LIST_DIR}/libpxx_app.a"
                     REQUIRES esp_timer esp_driver_gpio esp_adc lwip esp_netif pxx_esp pxx_fs)
target_link_libraries(${COMPONENT_LIB} INTERFACE pxx_app)
# Nothing in this component references app_main, so force the linker to keep
# pulling it from the archive (ESP-IDF's startup task calls it).
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u app_main")
