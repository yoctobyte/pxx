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
    /* THE STORE IS AFTER THE SEPARATOR CHECK AND THAT IS OBSERVABLE, not
       tidiness. On a refusal the caller keeps whatever octets were written
       BEFORE the failing component, and glibc writes exactly the same ones:
       measured 2026-09-04 (frankD's oracle, re-run here), `00:11:22:33:44 x'
       gives -1 with 00:11:22:33:00:00 under both, because the fifth component
       fails its `:' test before being stored. Hoisting this assignment above
       the check would still pass every ACCEPTING row and would leave
       00:11:22:33:44:00 in a struct the caller may inspect after -1.
       test/c_crtl_busybox_394_gaps.c row 12 asserts it. */
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

/* ---- /etc/ethers --------------------------------------------------------
 * ether_line / ether_hostton / ether_ntohost. Found attempting busybox at 394
 * applets: networking/ether-wake.c:134 wakes a host by name.
 *
 * THE FILE, NOT NSS -- the same boundary <grp.h> and <pwd.h> draw for their
 * own files. A site keeping ethers in LDAP resolves nothing here, which is
 * also what glibc does without nss_ldap configured.
 *
 * ONE PARSER, run over the file by the other two. Three copies of a tokeniser
 * is how the forward and reverse lookups come to disagree about what a valid
 * line is.
 */

#include <stdio.h>
#include <string.h>
#include <ctype.h>

/* Parses `<ether-address> <hostname>'. Leading blanks, a `#' comment to end of
 * line, and blank lines are all handled here rather than in the two callers.
 * Returns 0 on success, -1 if the line holds no complete pair.
 *
 * `hostname' MUST have room for the name plus its terminator -- there is no
 * length argument in this interface, which is glibc's shape and not a choice
 * available here. Both callers below pass a buffer sized for a whole line, so
 * a name can never be longer than the text it was read from. */
int ether_line(const char *line, struct ether_addr *addr, char *hostname)
{
  char abuf[64];
  const char *p = line;
  size_t i;

  if (!line || !addr || !hostname) return -1;

  /* NO LEADING WHITESPACE, and this is glibc-matching rather than strictness
     for its own sake: measured 2026-09-04, glibc rejects " 01:02:...:06 host"
     outright. An indented line in /etc/ethers therefore resolves nothing under
     either libc, and a crtl that accepted it would make a host reachable here
     and unreachable everywhere else -- the wrong direction for a lookup whose
     entire job is to agree with the rest of the system. */
  if (*p == '\0' || *p == '#' || isspace((unsigned char)*p)) return -1;

  for (i = 0; *p && !isspace((unsigned char)*p) && *p != '#'; p++) {
    if (i + 1 >= sizeof(abuf)) return -1;
    abuf[i++] = *p;
  }
  abuf[i] = '\0';
  if (!ether_aton_r(abuf, addr)) return -1;

  while (*p && isspace((unsigned char)*p) && *p != '\n') p++;
  if (*p == '\0' || *p == '#' || *p == '\n') return -1;

  for (i = 0; *p && !isspace((unsigned char)*p) && *p != '#'; p++)
    hostname[i++] = *p;
  hostname[i] = '\0';
  return i ? 0 : -1;
}

#define PXX_ETHERS_LINE 512

/* Both lookups are the same walk with the comparison swapped, so they share
 * it. `want_host' NULL means "match on address instead". */
static int pxx_ethers_lookup(const char *want_host, struct ether_addr *addr,
                             char *out_host)
{
  FILE *f;
  char line[PXX_ETHERS_LINE];
  char name[PXX_ETHERS_LINE];
  struct ether_addr got;

  f = fopen("/etc/ethers", "r");
  if (!f) return -1;

  while (fgets(line, (int)sizeof(line), f)) {
    if (ether_line(line, &got, name) != 0) continue;
    if (want_host) {
      if (strcmp(name, want_host) != 0) continue;
      *addr = got;
    } else {
      if (memcmp(got.ether_addr_octet, addr->ether_addr_octet,
                 sizeof(got.ether_addr_octet)) != 0) continue;
      strcpy(out_host, name);
    }
    fclose(f);
    return 0;
  }
  fclose(f);
  return -1;
}

int ether_hostton(const char *hostname, struct ether_addr *addr)
{
  if (!hostname || !addr) return -1;
  return pxx_ethers_lookup(hostname, addr, 0);
}

int ether_ntohost(char *hostname, const struct ether_addr *addr)
{
  struct ether_addr key;
  if (!hostname || !addr) return -1;
  key = *addr;
  return pxx_ethers_lookup(0, &key, hostname);
}
