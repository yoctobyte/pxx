# PXX ESP32-S3 Wi-Fi access point + web page

The board starts its own Wi-Fi network, and a **Pascal** HTTP server serves a
hello-world page on it. Join from a phone and open `http://192.168.4.1/`.

- network `PXX-ESP32S3`, password `pascal26` (WPA2; set `AP_PASSWORD := ''` in
  `main/main.pas` for an open network)
- the page shows uptime, the request number, free heap, and the visitor's IP
- each request is logged to the serial console, e.g.
  `PXX wifi-ap: 192.168.4.2 "GET / HTTP/1.1"`

```sh
. ~/esp/esp-idf/export.sh
tools/esp_flash.sh --project examples/esp32/wifi-ap-s3 --no-verify   # from the repo root
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

## Status, 2026-09-24

On silicon (ESP32-S3 rev v0.2): the AP comes up on channel 6, the DHCP server
starts on 192.168.4.1, and the server listens on port 80. That is all read off
the serial console. **A client loading the page has not been observed yet.**
The build host's Wi-Fi is off, and no phone had connected when this was
committed.

The image is 804 KB (1 MB app partition). `idf.py size-components` puts
the Pascal archive at 51.6 KB of code plus 7.2 KB of read-only data, about 7%.
The Wi-Fi stack (net80211, pp, phy, wpa_supplicant, mbedTLS) is about 340 KB of
code, and lwIP is 89 KB.
