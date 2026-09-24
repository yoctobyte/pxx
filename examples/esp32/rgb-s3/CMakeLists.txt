# ESP-IDF project whose app_main comes from a PXX-compiled Pascal object:
# a colour-fading demo for the ESP32-S3 devkit's onboard WS2812 RGB LED.
cmake_minimum_required(VERSION 3.16)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(pxx_rgb_s3)
