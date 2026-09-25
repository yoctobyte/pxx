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
#include <stdlib.h>
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
static esp_netif_t *s_sta_netif;
static int s_stack_up;
static int s_started;          // esp_wifi_start() has run and not been stopped
static int s_mode;             // WIFI_MODE_* bits we asked for: STA 1, AP 2

// Station state, kept exactly as MicroPython's ports/esp32/network_wlan.c
// keeps it, because WLAN.status() is defined by it: the last disconnect
// reason is REMEMBERED while the driver retries, so a program polling
// `while sta.status() == network.STAT_CONNECTING` stops at NO_AP_FOUND (201)
// for an SSID that does not exist instead of spinning forever.
static volatile int s_sta_connected;
static volatile int s_sta_disconn_reason;
static volatile int s_sta_connect_requested;
static volatile int s_sta_reconnects;
static int s_conf_sta_reconnects;      // 0 = retry forever (MicroPython's default)
#define PXX_STAT_IDLE       1000
#define PXX_STAT_CONNECTING 1001
#define PXX_STAT_GOT_IP     1010

static wifi_ap_record_t *s_scan;
static int s_scan_count;

static void on_wifi_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        s_sta_connected = 1;
        s_sta_disconn_reason = 0;
        ESP_LOGI(TAG, "station got an address");
        return;
    }
    if (base != WIFI_EVENT) return;
    if (id == WIFI_EVENT_AP_STACONNECTED) {
        wifi_event_ap_staconnected_t *e = data;
        ESP_LOGI(TAG, "station " MACSTR " joined, aid=%d", MAC2STR(e->mac), e->aid);
    } else if (id == WIFI_EVENT_AP_STADISCONNECTED) {
        wifi_event_ap_stadisconnected_t *e = data;
        ESP_LOGI(TAG, "station " MACSTR " left, aid=%d", MAC2STR(e->mac), e->aid);
    } else if (id == WIFI_EVENT_STA_START) {
        s_sta_reconnects = 0;
    } else if (id == WIFI_EVENT_STA_DISCONNECTED) {
        wifi_event_sta_disconnected_t *e = data;
        s_sta_disconn_reason = e->reason;
        s_sta_connected = 0;
        if (s_sta_connect_requested) {
            if (s_conf_sta_reconnects && ++s_sta_reconnects >= s_conf_sta_reconnects)
                return;
            esp_wifi_connect();
        }
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
    s_sta_netif = esp_netif_create_default_wifi_sta();
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    if ((err = esp_wifi_init(&cfg)) != ESP_OK) return err;
    // Nothing is persisted to NVS: a program's credentials live in the program.
    esp_wifi_set_storage(WIFI_STORAGE_RAM);
    esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, on_wifi_event, NULL, NULL);
    esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP, on_wifi_event, NULL, NULL);
    s_stack_up = 1;
    return ESP_OK;
}

// Move to the mode bits `mode`, starting or stopping the driver as needed --
// MicroPython's active() arithmetic. `ap` (may be NULL) is applied between
// set_mode and start, so an AP never comes up with the driver's default open
// "ESP_xxxx" network first.
static esp_err_t set_mode(int mode, wifi_config_t *ap)
{
    esp_err_t err = stack_up();
    if (err != ESP_OK) return err;
    if (mode == 0) {
        s_mode = 0;
        if (s_started) { s_started = 0; return esp_wifi_stop(); }
        return ESP_OK;
    }
    if ((err = esp_wifi_set_mode((wifi_mode_t)mode)) != ESP_OK) return err;
    if (ap && (err = esp_wifi_set_config(WIFI_IF_AP, ap)) != ESP_OK) return err;
    if (!s_started) {
        if ((err = esp_wifi_start()) != ESP_OK) return err;
        s_started = 1;
    }
    s_mode = mode;
    return ESP_OK;
}

// Start the soft AP (reconfiguring it if it is up). An empty password makes an
// open network, anything else WPA2-PSK. Returns 0 or the first esp_err_t.
int pxx_wifi_ap_start(const char *ssid, const char *password, int channel)
{
    wifi_config_t ap = { 0 };
    strncpy((char *)ap.ap.ssid, ssid, sizeof ap.ap.ssid);
    ap.ap.ssid_len = strlen(ssid) > sizeof ap.ap.ssid ? sizeof ap.ap.ssid : strlen(ssid);
    strncpy((char *)ap.ap.password, password, sizeof ap.ap.password);
    ap.ap.channel = channel;
    ap.ap.max_connection = 4;
    ap.ap.authmode = strlen(password) ? WIFI_AUTH_WPA2_PSK : WIFI_AUTH_OPEN;
    ap.ap.pmf_cfg.required = false;
    return set_mode(s_mode | WIFI_MODE_AP, &ap);
}

int pxx_wifi_ap_stop(void)
{
    if (!(s_mode & WIFI_MODE_AP)) return ESP_OK;
    return set_mode(s_mode & ~WIFI_MODE_AP, NULL);
}

int pxx_wifi_ap_active(void)
{
    return s_started && (s_mode & WIFI_MODE_AP);
}

static int netif_ip(esp_netif_t *n, unsigned *ip, unsigned *mask, unsigned *gw)
{
    esp_netif_ip_info_t info;
    *ip = *mask = *gw = 0;
    if (!n) return ESP_ERR_INVALID_STATE;
    esp_err_t err = esp_netif_get_ip_info(n, &info);
    if (err != ESP_OK) return err;
    *ip = ntohl(info.ip.addr);
    *mask = ntohl(info.netmask.addr);
    *gw = ntohl(info.gw.addr);
    return ESP_OK;
}

// The AP interface's address, netmask and gateway, host byte order.
int pxx_wifi_ap_ip(unsigned *ip, unsigned *mask, unsigned *gw)
{
    return netif_ip(s_ap_netif, ip, mask, gw);
}

// How many stations are associated with the AP right now; -1 if it is down.
int pxx_wifi_ap_stations(void)
{
    wifi_sta_list_t list;
    if (!pxx_wifi_ap_active()) return -1;
    if (esp_wifi_ap_get_sta_list(&list) != ESP_OK) return -1;
    return list.num;
}

// ---- station ---------------------------------------------------------------

int pxx_wifi_sta_start(void)
{
    return set_mode(s_mode | WIFI_MODE_STA, NULL);
}

int pxx_wifi_sta_stop(void)
{
    if (!(s_mode & WIFI_MODE_STA)) return ESP_OK;
    s_sta_connect_requested = 0;
    s_sta_connected = 0;
    return set_mode(s_mode & ~WIFI_MODE_STA, NULL);
}

int pxx_wifi_sta_active(void)
{
    return s_started && (s_mode & WIFI_MODE_STA);
}

// connect(ssid, key): non-blocking, as in MicroPython -- the answer arrives
// through status() / isconnected(). An empty ssid reuses the last config.
int pxx_wifi_sta_connect(const char *ssid, const char *password)
{
    esp_err_t err;
    if (!pxx_wifi_sta_active()) return ESP_ERR_WIFI_NOT_STARTED;
    if (ssid[0]) {
        wifi_config_t sta = { 0 };
        strncpy((char *)sta.sta.ssid, ssid, sizeof sta.sta.ssid);
        strncpy((char *)sta.sta.password, password, sizeof sta.sta.password);
        if ((err = esp_wifi_set_config(WIFI_IF_STA, &sta)) != ESP_OK) return err;
    }
    s_sta_reconnects = 0;
    s_sta_disconn_reason = 0;
    if ((err = esp_wifi_connect()) != ESP_OK) return err;
    s_sta_connect_requested = 1;
    return ESP_OK;
}

int pxx_wifi_sta_disconnect(void)
{
    s_sta_connect_requested = 0;
    if (!pxx_wifi_sta_active()) return ESP_OK;
    return esp_wifi_disconnect();
}

int pxx_wifi_sta_isconnected(void)
{
    return s_sta_connected;
}

// WLAN(STA_IF).status(), MicroPython's decision ladder line for line.
int pxx_wifi_sta_status(void)
{
    int r = s_sta_disconn_reason;
    if (s_sta_connected) return PXX_STAT_GOT_IP;
    if (r == WIFI_REASON_NO_AP_FOUND
        || r == WIFI_REASON_NO_AP_FOUND_IN_RSSI_THRESHOLD
        || r == WIFI_REASON_NO_AP_FOUND_IN_AUTHMODE_THRESHOLD
        || r == WIFI_REASON_NO_AP_FOUND_W_COMPATIBLE_SECURITY) return r;
    if (r == WIFI_REASON_AUTH_FAIL || r == WIFI_REASON_CONNECTION_FAIL) return WIFI_REASON_AUTH_FAIL;
    if (r == WIFI_REASON_ASSOC_LEAVE) return PXX_STAT_IDLE;
    if (s_sta_connect_requested
        && (s_conf_sta_reconnects == 0 || s_sta_reconnects < s_conf_sta_reconnects))
        return PXX_STAT_CONNECTING;
    if (r == 0) return PXX_STAT_IDLE;
    return r;
}

// config(reconnects=n): -1 retries forever, n tries n+1 times (MicroPython).
void pxx_wifi_sta_set_reconnects(int n)
{
    s_conf_sta_reconnects = (n == -1) ? 0 : n + 1;
}

int pxx_wifi_sta_ip(unsigned *ip, unsigned *mask, unsigned *gw, unsigned *dns)
{
    esp_netif_dns_info_t d;
    *dns = 0;
    int err = netif_ip(s_sta_netif, ip, mask, gw);
    if (err == ESP_OK && esp_netif_get_dns_info(s_sta_netif, ESP_NETIF_DNS_MAIN, &d) == ESP_OK)
        *dns = ntohl(d.ip.u_addr.ip4.addr);
    return err;
}

int pxx_wifi_sta_rssi(int *rssi)
{
    wifi_ap_record_t info;
    esp_err_t err = esp_wifi_sta_get_ap_info(&info);
    *rssi = err == ESP_OK ? info.rssi : 0;
    return err;
}

// A blocking scan (hidden networks included, as MicroPython asks for); the
// records stay here until the next scan and are read by index. Returns the
// count, or -esp_err_t.
int pxx_wifi_scan(void)
{
    wifi_scan_config_t cfg = { 0 };
    uint16_t n = 0;
    esp_err_t err;
    if (!pxx_wifi_sta_active()) return -ESP_ERR_WIFI_NOT_STARTED;
    cfg.show_hidden = true;
    if ((err = esp_wifi_scan_start(&cfg, true)) != ESP_OK) return -err;
    if ((err = esp_wifi_scan_get_ap_num(&n)) != ESP_OK) return -err;
    free(s_scan);
    s_scan = NULL;
    s_scan_count = 0;
    if (n == 0) { esp_wifi_clear_ap_list(); return 0; }
    s_scan = calloc(n, sizeof *s_scan);
    if (!s_scan) { esp_wifi_clear_ap_list(); return -ESP_ERR_NO_MEM; }
    if ((err = esp_wifi_scan_get_ap_records(&n, s_scan)) != ESP_OK) return -err;
    s_scan_count = n;
    return n;
}

// Record i of the last scan: ssid (33 bytes, NUL-terminated), bssid (6),
// primary channel, RSSI and auth mode. 0, or ESP_ERR_INVALID_ARG past the end.
int pxx_wifi_scan_get(int i, char *ssid, unsigned char *bssid, int *channel, int *rssi, int *authmode)
{
    if (i < 0 || i >= s_scan_count) return ESP_ERR_INVALID_ARG;
    memcpy(ssid, s_scan[i].ssid, 33);
    ssid[32] = 0;
    memcpy(bssid, s_scan[i].bssid, 6);
    *channel = s_scan[i].primary;
    *rssi = s_scan[i].rssi;
    *authmode = s_scan[i].authmode;
    return ESP_OK;
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
