/* SPDX-License-Identifier: Zlib */
/* <linux/wireless.h>: the WE ioctl numbers AND the struct LAYOUTS, diffed
   against gcc at both widths.

   THE LAYOUT IS THE INTERFACE. Every SIOCGIW* is a filled-buffer ioctl: the
   kernel writes fields at fixed offsets into `union iwreq_data' and the caller
   reads them back by name. A struct whose field is one word off does not
   error -- it reads a neighbouring field and reports it as an answer.
   busybox's ifplugd.c does exactly that, `memcpy(mac, &iwrequest.u.ap_addr.
   sa_data, ETH_ALEN)' after SIOCGIWAP, so a shifted `ap_addr' hands six bytes
   of something else to a MAC comparison and the link-detect logic silently
   decides the interface changed AP.

   THE 32- AND 64-BIT ANSWERS DIFFER ON PURPOSE, AND THAT IS THE WHOLE REASON
   THIS FILE PRINTS sizeof/offsetof RATHER THAN A TABLE OF NUMBERS.
   `struct iw_point' carries `void *pointer', so it is 16 bytes on x86-64 and 8
   on i386 -- which makes `union iwreq_data' the same size only by accident
   (`struct sockaddr' is 16 either way and is the union's largest member at
   both widths), while `struct iw_event' genuinely differs: 24 against 20.
   Measured 2026-09-04 against the host header:

       gcc         iw_point 16  iw_event 24   (x86-64)
       gcc -m32    iw_point  8  iw_event 20

   A file asserting written-down constants would have had to pick one and would
   have been wrong on the other target -- and i386 is the target this header
   was written for, since the host-header fallback that quietly supplies
   /usr/include on x86-64 is a hard `include file not found' on every cross
   target. The Makefile diffs pxx against gcc on the SAME width, so both rows
   are asserted without this file carrying a per-target expectation.

   iw_range IS HERE EVEN THOUGH busybox NEVER READS IT. It is the largest
   struct in the header, it embeds iw_freq, iw_quality and iw_point arrays, and
   its size is therefore a checksum over most of the file: a wrong element size
   anywhere inside moves it. ifplugd's own surface -- iwreq, ap_addr,
   SIOCGIWAP -- is four rows and could not tell a correct header from one that
   happens to agree about its first union member. */

#define _GNU_SOURCE 1
#include <stdio.h>
#include <stddef.h>
#include <linux/wireless.h>

#define P(x)   printf("%-34s %ld\n", #x, (long)(x))
#define S(t)   printf("sizeof %-27s %ld\n", #t, (long)sizeof(struct t))
#define U(t)   printf("sizeof %-27s %ld\n", #t, (long)sizeof(union t))
#define O(t,f) printf("offsetof %-25s %ld\n", #t "." #f, (long)offsetof(struct t, f))
#define OU(t,f) printf("offsetof %-25s %ld\n", #t "." #f, (long)offsetof(union t, f))

int main(void)
{
  /* The ioctl block. SIOCGIWAP is the one busybox issues; the rest are the
     range it lives in, and a shifted base would move all of them together. */
  P(SIOCSIWCOMMIT); P(SIOCGIWNAME); P(SIOCSIWNWID); P(SIOCGIWNWID);
  P(SIOCSIWFREQ); P(SIOCGIWFREQ); P(SIOCSIWMODE); P(SIOCGIWMODE);
  P(SIOCSIWSENS); P(SIOCGIWSENS); P(SIOCSIWRANGE); P(SIOCGIWRANGE);
  P(SIOCSIWPRIV); P(SIOCGIWPRIV); P(SIOCSIWSTATS); P(SIOCGIWSTATS);
  P(SIOCSIWSPY); P(SIOCGIWSPY); P(SIOCSIWTHRSPY); P(SIOCGIWTHRSPY);
  P(SIOCSIWAP); P(SIOCGIWAP); P(SIOCGIWAPLIST); P(SIOCSIWSCAN);
  P(SIOCGIWSCAN); P(SIOCSIWESSID); P(SIOCGIWESSID); P(SIOCSIWNICKN);
  P(SIOCGIWNICKN); P(SIOCSIWRATE); P(SIOCGIWRATE); P(SIOCSIWRTS);
  P(SIOCGIWRTS); P(SIOCSIWFRAG); P(SIOCGIWFRAG); P(SIOCSIWTXPOW);
  P(SIOCGIWTXPOW); P(SIOCSIWRETRY); P(SIOCGIWRETRY); P(SIOCSIWENCODE);
  P(SIOCGIWENCODE); P(SIOCSIWPOWER); P(SIOCGIWPOWER);
  P(SIOCSIWGENIE); P(SIOCGIWGENIE); P(SIOCSIWMLME); P(SIOCSIWAUTH);
  P(SIOCGIWAUTH); P(SIOCSIWENCODEEXT); P(SIOCGIWENCODEEXT); P(SIOCSIWPMKSA);
  P(SIOCIWFIRST); P(SIOCIWLAST); P(SIOCIWFIRSTPRIV); P(SIOCIWLASTPRIV);
  P(IWEVTXDROP); P(IWEVQUAL); P(IWEVCUSTOM); P(IWEVREGISTERED);
  P(IWEVEXPIRED); P(IWEVGENIE); P(IWEVMICHAELMICFAILURE); P(IWEVASSOCREQIE);
  P(IWEVASSOCRESPIE); P(IWEVPMKIDCAND); P(IWEVFIRST);

  P(WIRELESS_EXT); P(IW_MAX_FREQUENCIES); P(IW_MAX_BITRATES);
  P(IW_MAX_TXPOWER); P(IW_MAX_SPY); P(IW_MAX_AP); P(IW_ESSID_MAX_SIZE);
  P(IW_ENCODING_TOKEN_MAX); P(IW_MODE_AUTO); P(IW_MODE_MASTER);
  P(IW_MODE_MONITOR); P(IW_QUAL_QUAL_UPDATED); P(IW_QUAL_ALL_INVALID);
  P(IW_FREQ_AUTO); P(IW_FREQ_FIXED); P(IW_ENCODE_INDEX); P(IW_ENCODE_FLAGS);
  P(IW_ENCODE_MODE); P(IW_ENCODE_DISABLED); P(IW_POWER_ON);
  P(IW_TXPOW_DBM); P(IW_TXPOW_MWATT); P(IW_TXPOW_RELATIVE);
  P(IW_RETRY_ON); P(IW_SCAN_DEFAULT); P(IW_SCAN_THIS_ESSID);
  P(IW_AUTH_WPA_VERSION); P(IW_AUTH_CIPHER_PAIRWISE); P(IW_AUTH_PRIVACY_INVOKED);
  P(IW_ENCODE_ALG_NONE); P(IW_ENCODE_ALG_TKIP); P(IW_ENCODE_ALG_CCMP);
  P(IW_PMKSA_ADD); P(IW_PMKID_LEN); P(IW_EV_LCP_LEN); P(IW_EV_CHAR_LEN);
  P(IW_EV_POINT_LEN); P(IW_EV_ADDR_LEN);

  /* Sizes. iw_point and iw_event are the two that MUST differ between the
     widths; the rest must agree, and a row that agreed everywhere would not
     be able to tell this header apart from a 64-bit-only one. */
  S(iw_param); S(iw_point); S(iw_freq); S(iw_quality);
  S(iw_discarded); S(iw_missed); S(iw_thrspy); S(iw_scan_req);
  S(iw_encode_ext); S(iw_mlme); S(iw_pmksa); S(iw_michaelmicfailure);
  S(iw_pmkid_cand); S(iw_statistics); S(iw_range); S(iw_priv_args);
  S(iw_event); U(iwreq_data); S(iwreq);

  /* ifplugd's own path, field by field: iwreq -> u -> ap_addr -> sa_data. */
  O(iwreq, ifr_ifrn); O(iwreq, u);
  OU(iwreq_data, name); OU(iwreq_data, essid); OU(iwreq_data, nwid);
  OU(iwreq_data, freq); OU(iwreq_data, sens); OU(iwreq_data, bitrate);
  OU(iwreq_data, txpower); OU(iwreq_data, rts); OU(iwreq_data, frag);
  OU(iwreq_data, mode); OU(iwreq_data, retry); OU(iwreq_data, encoding);
  OU(iwreq_data, power); OU(iwreq_data, qual); OU(iwreq_data, ap_addr);
  OU(iwreq_data, addr); OU(iwreq_data, param); OU(iwreq_data, data);

  O(iw_point, pointer); O(iw_point, length); O(iw_point, flags);
  O(iw_param, value); O(iw_param, fixed); O(iw_param, disabled); O(iw_param, flags);
  O(iw_freq, m); O(iw_freq, e); O(iw_freq, i); O(iw_freq, flags);
  O(iw_quality, qual); O(iw_quality, level); O(iw_quality, noise); O(iw_quality, updated);
  O(iw_discarded, nwid); O(iw_discarded, code); O(iw_discarded, fragment);
  O(iw_discarded, retries); O(iw_discarded, misc);
  O(iw_statistics, status); O(iw_statistics, qual);
  O(iw_statistics, discard); O(iw_statistics, miss);

  O(iw_scan_req, scan_type); O(iw_scan_req, essid_len);
  O(iw_scan_req, num_channels); O(iw_scan_req, min_channel_time);
  O(iw_scan_req, max_channel_time); O(iw_scan_req, channel_list);
  O(iw_scan_req, essid);
  O(iw_encode_ext, ext_flags); O(iw_encode_ext, tx_seq); O(iw_encode_ext, rx_seq);
  O(iw_encode_ext, addr); O(iw_encode_ext, alg); O(iw_encode_ext, key_len);
  O(iw_encode_ext, key);
  O(iw_mlme, cmd); O(iw_mlme, reason_code); O(iw_mlme, addr);
  O(iw_pmksa, cmd); O(iw_pmksa, bssid); O(iw_pmksa, pmkid);
  O(iw_michaelmicfailure, flags); O(iw_michaelmicfailure, src_addr);
  O(iw_michaelmicfailure, tsc);
  O(iw_pmkid_cand, flags); O(iw_pmkid_cand, index); O(iw_pmkid_cand, bssid);

  /* iw_range: the checksum struct. Offsets across its whole span, so a wrong
     element size in any embedded array names itself rather than only moving
     the total. */
  O(iw_range, throughput); O(iw_range, min_nwid); O(iw_range, max_nwid);
  O(iw_range, old_num_channels); O(iw_range, num_channels);
  O(iw_range, freq); O(iw_range, we_version_compiled);
  O(iw_range, we_version_source); O(iw_range, retry_capa);
  O(iw_range, min_retry); O(iw_range, max_retry);
  O(iw_range, num_bitrates); O(iw_range, bitrate);
  O(iw_range, min_rts); O(iw_range, max_rts);
  O(iw_range, min_frag); O(iw_range, max_frag);
  O(iw_range, min_pmp); O(iw_range, max_pmp);
  O(iw_range, txpower_capa); O(iw_range, num_txpower); O(iw_range, txpower);
  O(iw_range, encoding_size); O(iw_range, num_encoding_sizes);
  O(iw_range, max_encoding_tokens); O(iw_range, encoding_login_index);
  O(iw_range, sensitivity); O(iw_range, max_qual); O(iw_range, avg_qual);
  O(iw_range, enc_capa); O(iw_range, event_capa);

  O(iw_event, len); O(iw_event, cmd); O(iw_event, u);
  O(iw_priv_args, cmd); O(iw_priv_args, set_args);
  O(iw_priv_args, get_args); O(iw_priv_args, name);
  return 0;
}
