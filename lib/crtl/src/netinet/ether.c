/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: ethernet address <-> text.
 *
 * THE FORMAT IS glibc's, MEASURED RATHER THAN ASSUMED (2026-09-02, against
 * glibc 2.x on this host). Both halves have a detail that a reasonable guess
 * gets wrong:
 *
 *   ether_ntoa prints "%x:%x:...", NOT "%02x". `00:11:22:33:44:55' comes back
 *   as `0:11:22:33:44:55' -- the leading zero of a byte below 0x10 is dropped,
 *   including in the first component. A padded implementation round-trips
 *   correctly and prints a different string, which is exactly the divergence a
 *   test that only round-trips cannot see.
 *
 *   ether_aton_r requires EXACTLY six colon-separated components of one or two
 *   hex digits. Three digits is a refusal (`000:11:...' -> NULL), `-' as the
 *   separator is a refusal, five components is a refusal -- but text AFTER the
 *   sixth component is IGNORED, so `00:11:22:33:44:55:66' parses and returns
 *   the first six. That asymmetry is glibc's and is reproduced deliberately.
 *
 * ether_ntoa's buffer is static, as the interface requires; ether_aton's is
 * too. Both are the documented non-reentrant halves of the _r pair.
 */
#include <netinet/ether.h>

static int cr_ether_hexval(char c)
{
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

static char *cr_ether_byte(char *p, unsigned int v)
{
  const char *hex = "0123456789abcdef";
  if (v >= 16) *p++ = hex[(v >> 4) & 0xf];
  *p++ = hex[v & 0xf];
  return p;
}

char *ether_ntoa_r(const struct ether_addr *addr, char *buf)
{
  char *p = buf;
  int i;

  for (i = 0; i < 6; i++) {
    if (i) *p++ = ':';
    p = cr_ether_byte(p, addr->ether_addr_octet[i]);
  }
  *p = '\0';
  return buf;
}

char *ether_ntoa(const struct ether_addr *addr)
{
  static char cr_ether_ntoa_buf[18];
  return ether_ntoa_r(addr, cr_ether_ntoa_buf);
}

struct ether_addr *ether_aton_r(const char *asc, struct ether_addr *addr)
{
  int i;
  int d0;
  int d1;

  for (i = 0; i < 6; i++) {
    d0 = cr_ether_hexval(*asc);
    if (d0 < 0) return (struct ether_addr *)0;
    asc++;
    d1 = cr_ether_hexval(*asc);
    if (d1 >= 0) {
      d0 = d0 * 16 + d1;
      asc++;
    }
    if (d0 > 255) return (struct ether_addr *)0;
    /* A third hex digit is a refusal, not a truncation: `000:11:...' is not a
       long spelling of 0, it is a different string, and glibc says NULL. */
    if (cr_ether_hexval(*asc) >= 0) return (struct ether_addr *)0;
    if (i < 5) {
      if (*asc != ':') return (struct ether_addr *)0;
      asc++;
    }
    addr->ether_addr_octet[i] = (unsigned char)d0;
  }
  /* Nothing is asserted about what follows the sixth component -- see the
     header comment; glibc accepts `00:11:22:33:44:55:66'. */
  return addr;
}

struct ether_addr *ether_aton(const char *asc)
{
  static struct ether_addr cr_ether_aton_buf;
  return ether_aton_r(asc, &cr_ether_aton_buf);
}
