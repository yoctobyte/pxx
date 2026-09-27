# The component itself has no C sources; app_main comes from the PXX-built
# archive produced by ../build.sh.
# esp_timer / lwip / esp_netif are REQUIREd not because this hello uses them,
# but because this project doubles as the harness tools/esp_flash.sh links an
# arbitrary .pas into, and a program calling the timer or socket APIs must
# resolve them. Without the dependency the component links before those
# archives and the references come out undefined.
# ESP_REQUIRES: extra components from espide's Settings > Libraries, which
# writes espide.cfg beside this project and passes it in the environment.
# Empty for a plain command-line build. separate_arguments, because $ENV{}
# is one string and REQUIRES wants a list.
set(PXX_EXTRA_REQUIRES "")
if(NOT "$ENV{ESP_REQUIRES}" STREQUAL "")
  separate_arguments(PXX_EXTRA_REQUIRES NATIVE_COMMAND "$ENV{ESP_REQUIRES}")
endif()

idf_component_register(REQUIRES esp_timer lwip esp_netif ${PXX_EXTRA_REQUIRES})

add_prebuilt_library(pxx_app "${CMAKE_CURRENT_LIST_DIR}/libpxx_app.a"
                     REQUIRES esp_timer lwip esp_netif)
target_link_libraries(${COMPONENT_LIB} INTERFACE pxx_app)

# Nothing in this component references app_main, so force the linker to keep
# the archive member that defines it.
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u app_main")
