# No C sources: app_main comes from the PXX-built archive made by ../build.sh.
# esp_driver_rmt is REQUIRED because the Pascal program drives the WS2812
# through the RMT peripheral.
idf_component_register(REQUIRES esp_driver_rmt)

# A NON-GLOBAL imported target, not add_prebuilt_library (which is GLOBAL):
# IDF's tools/cmake/ldgen.cmake passes only in-scope targets to ldgen, so a
# recompile relinks in ~2 s instead of also regenerating sections.ld (~18 s of
# pyparsing over IDF's own fragments). No linker fragment names this archive,
# so the generated script is byte-identical either way. This leans on that
# ldgen.cmake behaviour (see its IDF-12049 note); if IDF starts passing
# out-of-scope libraries to ldgen, the cost comes back and nothing breaks.
add_library(pxx_app STATIC IMPORTED)
set_target_properties(pxx_app PROPERTIES
  IMPORTED_LOCATION "${CMAKE_CURRENT_LIST_DIR}/libpxx_app.a"
  INTERFACE_LINK_LIBRARIES idf::esp_driver_rmt)
target_link_libraries(${COMPONENT_LIB} INTERFACE pxx_app)

# Nothing in this component references app_main, so force the linker to keep
# the archive member that defines it.
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u app_main")
