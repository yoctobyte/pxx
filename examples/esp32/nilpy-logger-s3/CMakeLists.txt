# ESP-IDF project whose app_main comes from a PXX-compiled NilPy program
# (main/main.npy -> main/main.o, built by build.sh before idf.py runs).
# lib/rtl/platform/esp/idf holds pxx_esp, the C half of `import network` and
# `import esp32` (pxx_esp.c says why that part is C).
cmake_minimum_required(VERSION 3.16)
set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_LIST_DIR}/../../../lib/rtl/platform/esp/idf")
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(pxx_nilpy_logger_s3)
