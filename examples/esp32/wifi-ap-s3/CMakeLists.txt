# ESP-IDF project whose app_main comes from a PXX-compiled Pascal object:
# a Wi-Fi access point serving a hello-world web page, on the ESP32-S3.
cmake_minimum_required(VERSION 3.16)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(pxx_wifi_ap_s3)
