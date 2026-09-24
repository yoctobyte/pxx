// SPDX-License-Identifier: 0BSD
// Wi-Fi softAP bring-up, the ONE part of this demo that is C.
//
// Why a shim: esp_wifi_init() takes WIFI_INIT_CONFIG_DEFAULT(), a macro that
// copies a crypto function table by value and folds in ~20 sdkconfig-derived
// constants, and IDF says to always build the config through that macro.
// Re-spelling it in Pascal would be a copy that drifts silently with every
// sdkconfig or IDF change. Everything after the AP is up -- sockets, HTTP,
// the page -- is Pascal (main.pas), on pxx's own PAL socket layer.
#include <string.h>
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "nvs_flash.h"

static const char *TAG = "pxx-ap";

static void on_wifi_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (id == WIFI_EVENT_AP_STACONNECTED) {
        wifi_event_ap_staconnected_t *e = data;
        ESP_LOGI(TAG, "station " MACSTR " joined, aid=%d", MAC2STR(e->mac), e->aid);
    } else if (id == WIFI_EVENT_AP_STADISCONNECTED) {
        wifi_event_ap_stadisconnected_t *e = data;
        ESP_LOGI(TAG, "station " MACSTR " left, aid=%d", MAC2STR(e->mac), e->aid);
    }
}

// Returns 0 on success, else the first failing esp_err_t.
int pxx_wifi_start_ap(const char *ssid, const char *password, int channel)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        err = nvs_flash_init();
    }
    if (err != ESP_OK) return err;
    if ((err = esp_netif_init()) != ESP_OK) return err;
    if ((err = esp_event_loop_create_default()) != ESP_OK) return err;
    esp_netif_create_default_wifi_ap();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    if ((err = esp_wifi_init(&cfg)) != ESP_OK) return err;
    esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, on_wifi_event, NULL, NULL);

    wifi_config_t ap = { 0 };
    strncpy((char *)ap.ap.ssid, ssid, sizeof ap.ap.ssid);
    ap.ap.ssid_len = strlen(ssid);
    strncpy((char *)ap.ap.password, password, sizeof ap.ap.password);
    ap.ap.channel = channel;
    ap.ap.max_connection = 4;
    ap.ap.authmode = strlen(password) ? WIFI_AUTH_WPA2_PSK : WIFI_AUTH_OPEN;
    ap.ap.pmf_cfg.required = false;

    if ((err = esp_wifi_set_mode(WIFI_MODE_AP)) != ESP_OK) return err;
    if ((err = esp_wifi_set_config(WIFI_IF_AP, &ap)) != ESP_OK) return err;
    return esp_wifi_start();
}
