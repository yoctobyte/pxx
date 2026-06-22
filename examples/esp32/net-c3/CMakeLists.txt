# Minimal ESP-IDF project whose app_main comes from a PXX-compiled Pascal
# object (main/main.o, built by build.sh before idf.py runs). Unlike hello-c3
# this app exercises the lwIP socket stack over the 127.0.0.1 loop interface.
cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(pxx_net_c3)
