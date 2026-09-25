# SPDX-License-Identifier: 0BSD
# QEMU-only: the OpenCores Ethernet MAC Espressif's QEMU emulates for
# `-nic user,model=open_eth`. Staged into a project by tools/esp_qemu_urequests.sh;
# never linked into an image meant for silicon (the driver says it is not
# supported on a real chip).
idf_component_register(SRCS "qemueth.c"
                       REQUIRES esp_eth esp_netif esp_event)
