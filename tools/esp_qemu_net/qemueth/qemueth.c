// SPDX-License-Identifier: 0BSD
// Bring up QEMU's emulated Ethernet (open_eth) and wait for slirp's DHCP
// lease, so a NilPy program under QEMU can reach the HOST at 10.0.2.2 -- the
// closest thing to a station on a LAN that exists without a radio. This is
// the part a MicroPython program on a board gets from network.WLAN; the
// program under test then uses the ordinary socket surface, unchanged.
//
// Returns 0 once the interface has an address, -1 on a driver failure, -2
// if no lease came within timeout_ms.
#include "esp_eth.h"
#include "esp_eth_mac_openeth.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

static SemaphoreHandle_t s_got_ip;

static void on_got_ip(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    xSemaphoreGive(s_got_ip);
}

int pxx_qemu_eth_up(int timeout_ms)
{
    if (esp_netif_init() != ESP_OK) return -1;
    esp_err_t err = esp_event_loop_create_default();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) return -1;   // already made
    esp_netif_config_t ncfg = ESP_NETIF_DEFAULT_ETH();
    esp_netif_t *nif = esp_netif_new(&ncfg);
    if (!nif) return -1;
    eth_mac_config_t mcfg = ETH_MAC_DEFAULT_CONFIG();
    eth_phy_config_t pcfg = ETH_PHY_DEFAULT_CONFIG();
    pcfg.autonego_timeout_ms = 100;   // the emulated PHY negotiates at once
    pcfg.reset_gpio_num = -1;         // and has no reset pin
    esp_eth_mac_t *mac = esp_eth_mac_new_openeth(&mcfg);
    esp_eth_phy_t *phy = esp_eth_phy_new_generic(&pcfg);
    if (!mac || !phy) return -1;
    esp_eth_config_t ecfg = ETH_DEFAULT_CONFIG(mac, phy);
    esp_eth_handle_t eth = NULL;
    if (esp_eth_driver_install(&ecfg, &eth) != ESP_OK) return -1;
    if (esp_netif_attach(nif, esp_eth_new_netif_glue(eth)) != ESP_OK) return -1;
    s_got_ip = xSemaphoreCreateBinary();
    esp_event_handler_register(IP_EVENT, IP_EVENT_ETH_GOT_IP, on_got_ip, NULL);
    if (esp_eth_start(eth) != ESP_OK) return -1;
    return xSemaphoreTake(s_got_ip, pdMS_TO_TICKS(timeout_ms)) == pdTRUE ? 0 : -2;
}
