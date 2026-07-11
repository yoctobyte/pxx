# The component itself has no C sources; app_main comes from the PXX-built
# Pascal object, wrapped into a static archive by build.sh (CMake's prebuilt
# library support wants an archive, not a bare .o).
idf_component_register(REQUIRES esp_timer)

# The Pascal object calls esp_timer_* directly; REQUIRES makes the prebuilt
# archive depend on the esp_timer component so link order resolves it.
add_prebuilt_library(pxx_app "${CMAKE_CURRENT_LIST_DIR}/libpxx_app.a"
                     REQUIRES esp_timer)
target_link_libraries(${COMPONENT_LIB} INTERFACE pxx_app)
# Nothing in this component references app_main, so force the linker to keep
# pulling it from the archive (ESP-IDF's startup task calls it).
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u app_main")
