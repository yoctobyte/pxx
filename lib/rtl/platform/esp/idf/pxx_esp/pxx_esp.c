// SPDX-License-Identifier: Zlib
// The C half of lib/rtl/platform/esp/mimic_network.pas and mimic_esp32.pas.
//
// C for one reason, the one examples/esp32/wifi-ap-s3/main/wifi_ap.c gives:
// the IDF calls below take configs built by IDF's own macros
// (WIFI_INIT_CONFIG_DEFAULT, TEMPERATURE_SENSOR_CONFIG_DEFAULT), which copy
// function tables by value and fold in sdkconfig- and chip-derived constants
// -- the temperature sensor's default clock is a different enum on every
// chip. A Pascal copy of either would drift silently with each IDF or
// sdkconfig change. Everything else stays Pascal.
//
// An IDF component: a project adds lib/rtl/platform/esp/idf to
// EXTRA_COMPONENT_DIRS and pxx_esp to its REQUIRES
// (examples/esp32/nilpy-station-s3 is the worked example).
#include <string.h>
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "nvs_flash.h"
#include "soc/soc_caps.h"
#if SOC_TEMP_SENSOR_SUPPORTED
#include "driver/temperature_sensor.h"
#endif

static const char *TAG = "pxx-net";
static esp_netif_t *s_ap_netif;
static int s_stack_up;
static int s_ap_up;

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

// NVS, netif, the default event loop and the Wi-Fi driver: once per boot.
static esp_err_t stack_up(void)
{
    if (s_stack_up) return ESP_OK;
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        err = nvs_flash_init();
    }
    if (err != ESP_OK) return err;
    if ((err = esp_netif_init()) != ESP_OK) return err;
    err = esp_event_loop_create_default();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) return err;   // already made
    s_ap_netif = esp_netif_create_default_wifi_ap();
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    if ((err = esp_wifi_init(&cfg)) != ESP_OK) return err;
    esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, on_wifi_event, NULL, NULL);
    s_stack_up = 1;
    return ESP_OK;
}

// Start the soft AP (restarting it if it is up). An empty password makes an
// open network, anything else WPA2-PSK. Returns 0 or the first esp_err_t.
int pxx_wifi_ap_start(const char *ssid, const char *password, int channel)
{
    esp_err_t err = stack_up();
    if (err != ESP_OK) return err;
    if (s_ap_up) esp_wifi_stop();
    wifi_config_t ap = { 0 };
    strncpy((char *)ap.ap.ssid, ssid, sizeof ap.ap.ssid);
    ap.ap.ssid_len = strlen(ssid) > sizeof ap.ap.ssid ? sizeof ap.ap.ssid : strlen(ssid);
    strncpy((char *)ap.ap.password, password, sizeof ap.ap.password);
    ap.ap.channel = channel;
    ap.ap.max_connection = 4;
    ap.ap.authmode = strlen(password) ? WIFI_AUTH_WPA2_PSK : WIFI_AUTH_OPEN;
    ap.ap.pmf_cfg.required = false;
    if ((err = esp_wifi_set_mode(WIFI_MODE_AP)) != ESP_OK) return err;
    if ((err = esp_wifi_set_config(WIFI_IF_AP, &ap)) != ESP_OK) return err;
    if ((err = esp_wifi_start()) != ESP_OK) return err;
    s_ap_up = 1;
    return ESP_OK;
}

int pxx_wifi_ap_stop(void)
{
    if (!s_ap_up) return ESP_OK;
    s_ap_up = 0;
    return esp_wifi_stop();
}

int pxx_wifi_ap_active(void)
{
    return s_ap_up;
}

// The AP interface's address, netmask and gateway, host byte order.
int pxx_wifi_ap_ip(unsigned *ip, unsigned *mask, unsigned *gw)
{
    esp_netif_ip_info_t info;
    *ip = *mask = *gw = 0;
    if (!s_ap_netif) return ESP_ERR_INVALID_STATE;
    esp_err_t err = esp_netif_get_ip_info(s_ap_netif, &info);
    if (err != ESP_OK) return err;
    *ip = ntohl(info.ip.addr);
    *mask = ntohl(info.netmask.addr);
    *gw = ntohl(info.gw.addr);
    return ESP_OK;
}

// How many stations are associated with the AP right now; -1 if it is down.
int pxx_wifi_ap_stations(void)
{
    wifi_sta_list_t list;
    if (!s_ap_up) return -1;
    if (esp_wifi_ap_get_sta_list(&list) != ESP_OK) return -1;
    return list.num;
}

// The chip's own temperature sensor, installed on first use over IDF's
// default range (-10..80 C). ESP_ERR_NOT_SUPPORTED where the chip has none.
int pxx_mcu_temperature(float *celsius)
{
#if SOC_TEMP_SENSOR_SUPPORTED
    static temperature_sensor_handle_t h;
    esp_err_t err;
    *celsius = 0;
    if (!h) {
        temperature_sensor_config_t cfg = TEMPERATURE_SENSOR_CONFIG_DEFAULT(-10, 80);
        if ((err = temperature_sensor_install(&cfg, &h)) != ESP_OK) { h = NULL; return err; }
        if ((err = temperature_sensor_enable(h)) != ESP_OK) return err;
    }
    return temperature_sensor_get_celsius(h, celsius);
#else
    *celsius = 0;
    return ESP_ERR_NOT_SUPPORTED;
#endif
}
