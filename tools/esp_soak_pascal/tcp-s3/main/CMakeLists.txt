# The component itself has no C sources; app_main comes from the PXX-built
# Pascal object, wrapped into a static archive. The prebuilt lib's own REQUIRES
# wires lwip + esp_netif so its undefined lwip_*/esp_netif_init refs resolve in
# the right link order (a plain component REQUIRES leaves the prebuilt archive
# outside the component link group).
idf_component_register(REQUIRES esp_netif lwip)

add_prebuilt_library(pxx_app "${CMAKE_CURRENT_LIST_DIR}/libpxx_app.a"
  REQUIRES esp_netif lwip)
target_link_libraries(${COMPONENT_LIB} INTERFACE pxx_app)
# Nothing in this component references app_main, so force the linker to keep
# pulling it from the archive (ESP-IDF's startup task calls it).
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u app_main")
