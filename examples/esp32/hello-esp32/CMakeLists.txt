# Minimal ESP-IDF project whose app_main comes from a PXX-compiled Pascal
# object archived into the main component. Classic ESP32 (Xtensa LX6).
cmake_minimum_required(VERSION 3.16)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(pxx_hello_esp32)
