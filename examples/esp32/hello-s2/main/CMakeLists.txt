# The component itself has no C sources; app_main comes from the PXX-built
# archive produced by ../build.sh.
# esp_timer / lwip / esp_netif are REQUIREd not because this hello uses them,
# but because this project doubles as tools/esp_run.sh's harness: it links an
# arbitrary .pas, and a program calling the timer or socket APIs must resolve
# them. Without the dependency the component links before those archives and
# the references come out undefined.
idf_component_register(REQUIRES esp_timer lwip esp_netif)

add_prebuilt_library(pxx_app "${CMAKE_CURRENT_LIST_DIR}/libpxx_app.a"
                     REQUIRES esp_timer lwip esp_netif)
target_link_libraries(${COMPONENT_LIB} INTERFACE pxx_app)

# Nothing in this component references app_main, so force the linker to keep
# the archive member that defines it.
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u app_main")
