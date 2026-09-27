# Minimal ESP-IDF project whose app_main comes from a PXX-compiled NilPy
# program (main/main.npy -> main/main.o, built by build.sh before idf.py runs).
cmake_minimum_required(VERSION 3.16)
# pxx_tls is the C half of `import ssl` (lib/rtl/platform/esp/mimic_ssl.pas),
# which urequests' https:// and umqtt's ssl= reach. Its object is only linked
# into an image that imports ssl.
set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_LIST_DIR}/../../../lib/rtl/platform/esp/idf/pxx_tls")
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(pxx_nilpy_hw_s3)
