# The component itself has no C sources; app_main comes from the PXX-built
# archive produced by ../build.sh.
idf_component_register()

add_prebuilt_library(pxx_app "${CMAKE_CURRENT_LIST_DIR}/libpxx_app.a")
target_link_libraries(${COMPONENT_LIB} INTERFACE pxx_app)

# Nothing in this component references app_main, so force the linker to keep
# the archive member that defines it.
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u app_main")
