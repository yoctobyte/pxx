# PXX ESP32-C3 Wi-Fi access point + web page

The board starts its own Wi-Fi network, and a **Pascal** HTTP server serves a
hello-world page on it. Join from a phone and open `http://192.168.4.1/`.

- network `PXX-ESP32C3`, password `pascal26` (WPA2; set `AP_PASSWORD := ''` in
  `main/main.pas` for an open network)
- the page shows uptime, the request number, free heap, and the visitor's IP
- each request is logged to the serial console, e.g.
  `PXX wifi-ap: 192.168.4.2 "GET / HTTP/1.1"`

```sh
. ~/esp/esp-idf/export.sh
tools/esp_flash.sh --project examples/esp32/wifi-ap-c3 --no-verify   # from the repo root
```

## What is Pascal and what is C

`main/main.pas` holds the TCP listener, request parsing, the page and the
logging. It uses pxx's own PAL socket layer (`lib/rtl/platform.pas`, whose ESP
backend is lwIP): `PalSocket`, `PalListen`, `PalAcceptIpv4`, `PalRecv` and
`PalSend`.

`main/wifi_ap.c` is about 40 lines and does only the Wi-Fi bring-up.
`esp_wifi_init()` has to be given `WIFI_INIT_CONFIG_DEFAULT()`, a macro that
copies a crypto function table by value and fills in about 20 sdkconfig-derived
fields. A Pascal copy of it would silently drift out of step with IDF.

## Status, 2026-09-28

The same program as `wifi-ap-s3`, built for the C3's riscv32; only the chip
names and the SSID differ. On an ESP32-C3 board (rev v0.4), with the compiler
built from tree `cdd6fd3c1f` (sha256 `139494b2b863`), the AP came up on
channel 6 and the server listened on port 80. An ESP32-S3 then joined
`PXX-ESP32C3` and loaded the page five times, running
`test/esp_board_s3_visits_wifi_ap_c3.npy`, a Nil Python client. It got HTTP
200 and the C3's title every time, and the C3's console logged the five
`GET /` requests from 192.168.4.2.

The image is 892,800 bytes, in the stock 1 MB app partition.

## QEMU

This example needs a board: an ESP32-C3 board, and a phone or laptop to join its Wi-Fi network. Espressif's QEMU has no Wi-Fi, and `build.sh` has no QEMU mode.
