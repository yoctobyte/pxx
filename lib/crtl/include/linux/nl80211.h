/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/nl80211.h>, A SMALL PART: the commands and attributes a
 * client reads the current SSID and BSS with (dhcpcd's if-linux.c). nl80211
 * has hundreds of each; these values are the kernel ABI and never change, but
 * the enums are NOT complete -- a program that needs more names fails to
 * compile rather than getting a wrong number. Grow it by value, from the
 * kernel's numbering.
 */
#ifndef _CRTL_LINUX_NL80211_H
#define _CRTL_LINUX_NL80211_H

#define NL80211_GENL_NAME "nl80211"

/* commands */
#define NL80211_CMD_UNSPEC        0
#define NL80211_CMD_GET_WIPHY     1
#define NL80211_CMD_GET_INTERFACE 5
#define NL80211_CMD_GET_SCAN      32
#define NL80211_CMD_TRIGGER_SCAN  33

/* top-level attributes */
#define NL80211_ATTR_UNSPEC   0
#define NL80211_ATTR_WIPHY    1
#define NL80211_ATTR_IFINDEX  3
#define NL80211_ATTR_IFNAME   4
#define NL80211_ATTR_MAC      6
#define NL80211_ATTR_BSS      47
#define NL80211_ATTR_SSID     52

/* attributes nested in NL80211_ATTR_BSS */
#define NL80211_BSS_BSSID                1
#define NL80211_BSS_FREQUENCY            2
#define NL80211_BSS_TSF                  3
#define NL80211_BSS_BEACON_INTERVAL      4
#define NL80211_BSS_CAPABILITY           5
#define NL80211_BSS_INFORMATION_ELEMENTS 6
#define NL80211_BSS_SIGNAL_MBM           7
#define NL80211_BSS_SIGNAL_UNSPEC        8
#define NL80211_BSS_STATUS               9

/* values of NL80211_BSS_STATUS */
#define NL80211_BSS_STATUS_AUTHENTICATED 0
#define NL80211_BSS_STATUS_ASSOCIATED    1
#define NL80211_BSS_STATUS_IBSS_JOINED   2

#endif
