# Minimal ESP-IDF project whose app_main comes from a PXX-compiled Pascal object
# (main/main.o, built by build.sh before idf.py runs). Where net-c3 exercises
# the PAL socket surface, this one exercises the lwIP RESOLVER binding that
# dns_libc grows under -dPXX_DNS_LIBC on ESP (feature-dns-esp-backend).
cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(pxx_dns_c3)
