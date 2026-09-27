# SPDX-License-Identifier: Zlib
# The C half of mimic_ssl.pas; pxx_tls.c says why it is C. A project uses it
# with, in its top-level CMakeLists.txt,
#   set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_LIST_DIR}/../../../lib/rtl/platform/esp/idf")
# and pxx_tls in main's REQUIRES. Nothing is pulled into an image that does
# not import ssl: the archive's object is only linked when a symbol in it is
# referenced.
idf_component_register(SRCS "pxx_tls.c"
                       REQUIRES mbedtls lwip)
