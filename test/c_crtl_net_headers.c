/* crtl: <netinet/udp.h>, <netinet/if_ether.h>, <netinet/ether.h>.
 *
 * All three were found the same way: attempting busybox for i386, where pxx
 * has no host /usr/include to fall back on and the gaps the x86-64 build was
 * borrowing become refusals. udp.h alone stopped 7 translation units.
 *
 * TWO SPELLINGS OF ONE HEADER. `struct udphdr' is `source/dest/len/check' in
 * Linux's spelling and `uh_sport/uh_dport/uh_ulen/uh_sum' in BSD's, and
 * busybox uses BOTH IN ONE BUILD -- udhcp/packet.c writes the first,
 * traceroute.c reads the second. Rows 2 and 3 write through one and read
 * through the other, which is the only thing that catches a header carrying
 * just one of them.
 *
 * Rows 6-9 are ether_aton_r/ether_ntoa against glibc's MEASURED behaviour, not
 * its documented one: ntoa drops a leading zero (`0:11:22:...', not
 * `00:11:...'), aton demands exactly six colon-separated groups of one or two
 * hex digits -- three digits is a refusal -- and yet IGNORES anything after
 * the sixth group. Row 9 is that asymmetry. A round-trip-only test passes on
 * a zero-padded ntoa, which is a different string on the wire.
 */
#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include <netinet/udp.h>
#include <netinet/if_ether.h>
#include <netinet/ether.h>

static void aton_row(int n, const char *s)
{
  struct ether_addr a;
  struct ether_addr *r = ether_aton_r(s, &a);
  if (!r) { printf("%d NULL\n", n); return; }
  printf("%d %02x%02x%02x%02x%02x%02x %s\n", n,
         a.ether_addr_octet[0], a.ether_addr_octet[1], a.ether_addr_octet[2],
         a.ether_addr_octet[3], a.ether_addr_octet[4], a.ether_addr_octet[5],
         ether_ntoa(&a));
}

int main(void)
{
  struct udphdr u;
  struct ether_arp e;

  printf("1 %d %d %d\n", (int)sizeof(struct udphdr),
         (int)sizeof(struct ether_arp), (int)sizeof(struct arphdr));

  memset(&u, 0, sizeof u);
  u.source = 0x1234; u.dest = 0x5678; u.len = 8; u.check = 0xbeef;
  printf("2 %x %x %x %x\n", u.uh_sport, u.uh_dport, u.uh_ulen, u.uh_sum);
  u.uh_sport = 0x0a0b; u.uh_dport = 0x0c0d;
  printf("3 %x %x\n", u.source, u.dest);

  printf("4 %d %d %d %d\n", (int)offsetof(struct ether_arp, arp_sha),
         (int)offsetof(struct ether_arp, arp_spa),
         (int)offsetof(struct ether_arp, arp_tha),
         (int)offsetof(struct ether_arp, arp_tpa));
  e.arp_op = 0x0102; e.arp_hln = 6;
  printf("5 %x %d %d %d %d %d\n", e.ea_hdr.ar_op, e.ea_hdr.ar_hln,
         ETHER_ADDR_LEN, ETHER_HDR_LEN, ETHER_MIN_LEN, ETHER_MAX_LEN);

  aton_row(6, "00:11:22:33:44:55");
  aton_row(7, "0:1:2:3:4:5");
  aton_row(8, "aa:BB:cc:DD:ee:FF");
  aton_row(9, "00:11:22:33:44:55:66");   /* trailing text is IGNORED */
  aton_row(10, "000:11:22:33:44:55");    /* three digits is a REFUSAL */
  aton_row(11, "01:02:03:04:05");        /* five groups is a refusal */
  aton_row(12, "00-11-22-33-44-55");     /* '-' is not the separator */
  return 0;
}
