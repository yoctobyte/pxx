# Minimal ESP-IDF project whose app_main comes from a PXX-compiled NilPy
# program (main/main.npy -> main/main.o, built by build.sh before idf.py runs).
cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(pxx_nilpy_c3)
