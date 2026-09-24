# wifi_ap.c is the Wi-Fi bring-up shim (see its header); app_main comes from
# the PXX-built archive made by ../build.sh.
idf_component_register(SRCS "wifi_ap.c"
                       REQUIRES esp_wifi esp_netif esp_event nvs_flash lwip esp_timer)

# A NON-GLOBAL imported target, not add_prebuilt_library (which is GLOBAL):
# IDF's tools/cmake/ldgen.cmake passes only in-scope targets to ldgen, so a
# recompile relinks in ~2 s instead of also regenerating sections.ld (~18 s).
# See examples/esp32/rgb-s3 for the measurement. Its interface libraries come
# after it on the link line: this component (for pxx_wifi_start_ap) and the
# IDF components the PAL socket layer and the program call into.
add_library(pxx_app STATIC IMPORTED)
set_target_properties(pxx_app PROPERTIES
  IMPORTED_LOCATION "${CMAKE_CURRENT_LIST_DIR}/libpxx_app.a"
  INTERFACE_LINK_LIBRARIES "${COMPONENT_LIB};idf::lwip;idf::esp_timer;idf::esp_system")
target_link_libraries(${COMPONENT_LIB} INTERFACE pxx_app)

# Nothing in this component references app_main, so force the linker to keep
# the archive member that defines it.
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u app_main")
