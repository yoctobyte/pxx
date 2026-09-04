/* SPDX-License-Identifier: Zlib */
/* <resolv.h> and <arpa/nameser.h>: constants, name conversion, and the
   message parser, all diffed against glibc.

   THE PARSER IS THE PART THAT MATTERS AND IT IS TESTED ON A CANNED PACKET,
   not on a live lookup. A test that resolved a real name would be measuring
   the network: it would pass on a box with DNS and fail on one without, and
   neither outcome would say anything about the parser. The bytes below are a
   complete, well-formed DNS response constructed for this file, so both
   compilers read exactly the same input and any difference is theirs.

   THE ADVERSARIAL ROWS ARE THE POSITIVE CONTROLS AND THEY ARE DRAWN FROM THE
   RIGHT POPULATION. Every function in nameser.c reads bytes chosen by whoever
   sent the packet, so a control built from a well-formed message proves
   nothing about the checks that exist for malformed ones. The six rows at the
   end are the malformed packets those checks are FOR -- a forward compression
   pointer, a self-pointer, a two-pointer loop, a reserved length byte, an
   over-long name, and a truncated message. Each MUST be refused, and a
   parser with the bounds checks deleted passes every other row in this file
   while failing exactly these.

   NO EXPECTED CONSTANTS FOR THE PARSE ROWS. glibc is the oracle and the
   Makefile diffs against it, so the rows carry no written-down answer that
   could collide with a failure value -- and "returns -1" is a failure value
   that a great many wrong implementations also produce. */

#define _GNU_SOURCE 1
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <arpa/inet.h>
#include <arpa/nameser.h>
#include <resolv.h>

/* A complete DNS response: 1 question (example.com A), 3 answers (A, MX with
   a compressed exchange, TXT), 1 authority (NS with a compressed target), and
   1 additional (AAAA whose OWNER name is itself compressed). Generated, not
   hand-counted -- every offset in it is a place a typo would be invisible. */
static const unsigned char pkt[] = {
  0x12, 0x34, 0x81, 0x80, 0x00, 0x01, 0x00, 0x03, 0x00, 0x01, 0x00, 0x01,
  0x07, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x03, 0x63, 0x6f, 0x6d,
  0x00, 0x00, 0x01, 0x00, 0x01, 0xc0, 0x0c, 0x00, 0x01, 0x00, 0x01, 0x00,
  0x00, 0x0e, 0x10, 0x00, 0x04, 0x5d, 0xb8, 0xd8, 0x22, 0xc0, 0x0c, 0x00,
  0x0f, 0x00, 0x01, 0x00, 0x00, 0x01, 0x2c, 0x00, 0x09, 0x00, 0x0a, 0x04,
  0x6d, 0x61, 0x69, 0x6c, 0xc0, 0x0c, 0xc0, 0x0c, 0x00, 0x10, 0x00, 0x01,
  0x00, 0x00, 0x00, 0x3c, 0x00, 0x0c, 0x0b, 0x68, 0x65, 0x6c, 0x6c, 0x6f,
  0x20, 0x77, 0x6f, 0x72, 0x6c, 0x64, 0xc0, 0x0c, 0x00, 0x02, 0x00, 0x01,
  0x00, 0x00, 0x0e, 0x10, 0x00, 0x06, 0x03, 0x6e, 0x73, 0x31, 0xc0, 0x0c,
  0x03, 0x6e, 0x73, 0x31, 0xc0, 0x0c, 0x00, 0x1c, 0x00, 0x01, 0x00, 0x00,
  0x0e, 0x10, 0x00, 0x10, 0x20, 0x01, 0x0d, 0xb8, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
};

static void show_rr(ns_msg *h, ns_sect sect, int i)
{
  ns_rr rr;
  char dn[NS_MAXDNAME];
  char astr[64];

  if (ns_parserr(h, sect, i, &rr) != 0) {
    printf("  [%d] parserr FAILED errno=%d\n", i, errno);
    return;
  }
  printf("  [%d] %-16s type=%-3d class=%d ttl=%-5u rdlen=%d",
         i, ns_rr_name(rr), (int)ns_rr_type(rr), (int)ns_rr_class(rr),
         (unsigned)ns_rr_ttl(rr), (int)ns_rr_rdlen(rr));
  /* A QUESTION HAS NO RDATA AND ns_rr_rdata() IS NULL FOR IT. Decoding it as
     if it were an answer dereferences that NULL -- which is how the first
     draft of this file crashed under glibc, before pxx had even seen it. The
     guard is here rather than in the caller because every section walks
     through this one function. */
  if (ns_rr_rdata(rr) == 0 || ns_rr_rdlen(rr) == 0) { printf("\n"); return; }
  switch (ns_rr_type(rr)) {
  case ns_t_a:
    inet_ntop(AF_INET, ns_rr_rdata(rr), astr, sizeof astr);
    printf(" addr=%s", astr);
    break;
  case ns_t_aaaa:
    inet_ntop(AF_INET6, ns_rr_rdata(rr), astr, sizeof astr);
    printf(" addr=%s", astr);
    break;
  case ns_t_mx:
    if (ns_name_uncompress(ns_msg_base(*h), ns_msg_end(*h),
                           ns_rr_rdata(rr) + 2, dn, sizeof dn) < 0)
      printf(" mx=UNCOMPRESS-FAILED");
    else
      printf(" pref=%d mx=%s", (int)ns_get16(ns_rr_rdata(rr)), dn);
    break;
  case ns_t_ns:
  case ns_t_cname:
  case ns_t_ptr:
    if (ns_name_uncompress(ns_msg_base(*h), ns_msg_end(*h),
                           ns_rr_rdata(rr), dn, sizeof dn) < 0)
      printf(" target=UNCOMPRESS-FAILED");
    else
      printf(" target=%s", dn);
    break;
  case ns_t_txt: {
    int n = *(const unsigned char *)ns_rr_rdata(rr);
    memcpy(dn, ns_rr_rdata(rr) + 1, (size_t)n);
    dn[n] = '\0';
    printf(" txt=\"%s\"", dn);
    break;
  }
  default:
    break;
  }
  printf("\n");
}

/* wire -> presentation -> wire, printed at every step. A round trip that only
   printed the final bytes would pass an implementation whose ntop and pton
   are wrong in mirror-image ways. */
static void nameroundtrip(const char *label, const unsigned char *wire, size_t wlen)
{
  char pres[NS_MAXDNAME];
  unsigned char back[NS_MAXCDNAME];
  int n, m;
  size_t i;

  n = ns_name_ntop(wire, pres, sizeof pres);
  printf("%-12s ntop=%d", label, n);
  if (n >= 0) printf(" [%s]", pres);
  if (n >= 0) {
    /* ns_name_pton() ANSWERS 0 OR 1 (was the name fully qualified), NOT a
       length -- measured against glibc, which returns 0 for "example.com".
       The wire length has to be walked, and printing the bytes is how this
       row stays meaningful: a `pton=0' on its own is indistinguishable from
       a failure that happened to return 0. */
    memset(back, 0xee, sizeof back);
    m = ns_name_pton(pres, back, sizeof back);
    printf(" pton=%d", m);
    if (m >= 0) {
      size_t bl = 0;
      while (back[bl] != 0 && bl < sizeof back) bl += back[bl] + 1;
      bl++;
      printf(" wire=");
      for (i = 0; i < bl && i < sizeof back; i++) printf("%02x", back[i]);
      printf(" same=%d", (bl == wlen && memcmp(back, wire, wlen) == 0));
    }
  }
  printf("\n");
}

/* A malformed packet that MUST be refused. Prints the verdict for the parse
   AND for a direct name decode, because the two reach the bounds checks by
   different routes and a fix to one does not imply the other. */
static void reject(const char *label, const unsigned char *p, int len)
{
  ns_msg h;
  char dn[NS_MAXDNAME];
  int a, b;
  a = ns_initparse(p, len, &h);
  b = (len > 12) ? ns_name_uncompress(p, p + len, p + 12, dn, sizeof dn) : -1;
  printf("%-14s initparse=%d uncompress=%d\n", label, a < 0 ? -1 : a, b < 0 ? -1 : b);
}

int main(void)
{
  ns_msg handle;
  int i;

  printf("=== sizes and limits\n");
  printf("NS_PACKETSZ=%d NS_MAXDNAME=%d NS_MAXCDNAME=%d NS_MAXLABEL=%d\n",
         NS_PACKETSZ, NS_MAXDNAME, NS_MAXCDNAME, NS_MAXLABEL);
  printf("NS_HFIXEDSZ=%d NS_QFIXEDSZ=%d NS_RRFIXEDSZ=%d NS_CMPRSFLGS=%d NS_DEFAULTPORT=%d\n",
         NS_HFIXEDSZ, NS_QFIXEDSZ, NS_RRFIXEDSZ, NS_CMPRSFLGS, NS_DEFAULTPORT);
  printf("MAXNS=%d MAXDNSRCH=%d MAXDFLSRCH=%d MAXRESOLVSORT=%d\n",
         MAXNS, MAXDNSRCH, MAXDFLSRCH, MAXRESOLVSORT);
  printf("RES_TIMEOUT=%d RES_MAXNDOTS=%d RES_DFLRETRY=%d RES_DEFAULT=%d\n",
         RES_TIMEOUT, RES_MAXNDOTS, RES_DFLRETRY, RES_DEFAULT);
  printf("compat PACKETSZ=%d MAXDNAME=%d INDIR_MASK=%d NAMESERVER_PORT=%d\n",
         PACKETSZ, MAXDNAME, INDIR_MASK, NAMESERVER_PORT);

  printf("=== enums\n");
  printf("sect qd=%d an=%d ns=%d ar=%d max=%d zn=%d\n",
         ns_s_qd, ns_s_an, ns_s_ns, ns_s_ar, ns_s_max, ns_s_zn);
  printf("type a=%d ns=%d cname=%d soa=%d ptr=%d mx=%d txt=%d aaaa=%d srv=%d any=%d\n",
         ns_t_a, ns_t_ns, ns_t_cname, ns_t_soa, ns_t_ptr, ns_t_mx,
         ns_t_txt, ns_t_aaaa, ns_t_srv, ns_t_any);
  printf("class in=%d chaos=%d none=%d any=%d\n",
         ns_c_in, ns_c_chaos, ns_c_none, ns_c_any);
  printf("rcode noerror=%d formerr=%d servfail=%d nxdomain=%d notimpl=%d refused=%d\n",
         ns_r_noerror, ns_r_formerr, ns_r_servfail, ns_r_nxdomain,
         ns_r_notimpl, ns_r_refused);
  printf("opcode query=%d iquery=%d status=%d notify=%d update=%d\n",
         ns_o_query, ns_o_iquery, ns_o_status, ns_o_notify, ns_o_update);
  printf("compat T_A=%d T_MX=%d T_TXT=%d T_AAAA=%d T_ANY=%d C_IN=%d QUERY=%d NXDOMAIN=%d\n",
         T_A, T_MX, T_TXT, T_AAAA, T_ANY, C_IN, QUERY, NXDOMAIN);

  printf("=== wire integers\n");
  {
    static const unsigned char b[4] = { 0xde, 0xad, 0xbe, 0xef };
    unsigned char o[4];
    printf("get16=%u get32=%u\n", (unsigned)ns_get16(b), (unsigned)ns_get32(b));
    ns_put16(0x1234, o); ns_put32(0x89abcdefu, o);
    printf("put32=%02x%02x%02x%02x\n", o[0], o[1], o[2], o[3]);
    ns_put16(0x1234, o);
    printf("put16=%02x%02x\n", o[0], o[1]);
  }

  printf("=== parse\n");
  if (ns_initparse(pkt, (int)sizeof pkt, &handle) != 0) {
    printf("initparse FAILED errno=%d\n", errno);
    return 1;
  }
  printf("id=%u qd=%d an=%d ns=%d ar=%d size=%d\n",
         (unsigned)ns_msg_id(handle),
         ns_msg_count(handle, ns_s_qd), ns_msg_count(handle, ns_s_an),
         ns_msg_count(handle, ns_s_ns), ns_msg_count(handle, ns_s_ar),
         (int)ns_msg_size(handle));
  printf("flags qr=%d opcode=%d aa=%d tc=%d rd=%d ra=%d rcode=%d\n",
         ns_msg_getflag(handle, ns_f_qr), ns_msg_getflag(handle, ns_f_opcode),
         ns_msg_getflag(handle, ns_f_aa), ns_msg_getflag(handle, ns_f_tc),
         ns_msg_getflag(handle, ns_f_rd), ns_msg_getflag(handle, ns_f_ra),
         ns_msg_getflag(handle, ns_f_rcode));
  printf("question:\n");
  for (i = 0; i < ns_msg_count(handle, ns_s_qd); i++) show_rr(&handle, ns_s_qd, i);
  printf("answer:\n");
  for (i = 0; i < ns_msg_count(handle, ns_s_an); i++) show_rr(&handle, ns_s_an, i);
  printf("authority:\n");
  for (i = 0; i < ns_msg_count(handle, ns_s_ns); i++) show_rr(&handle, ns_s_ns, i);
  printf("additional:\n");
  for (i = 0; i < ns_msg_count(handle, ns_s_ar); i++) show_rr(&handle, ns_s_ar, i);

  /* OUT-OF-ORDER ACCESS, because the handle caches a cursor and a forward
     walk never exercises the rewind. Asking for answer 2 then 0 then 1 must
     give the same three records the loop above did. */
  printf("out-of-order:\n");
  show_rr(&handle, ns_s_an, 2);
  show_rr(&handle, ns_s_an, 0);
  show_rr(&handle, ns_s_an, 1);
  printf("out-of-range:\n");
  show_rr(&handle, ns_s_an, 3);
  show_rr(&handle, ns_s_an, -1);

  printf("=== names\n");
  nameroundtrip("simple",  (const unsigned char *)"\7example\3com\0", 13);
  nameroundtrip("root",    (const unsigned char *)"\0", 1);
  nameroundtrip("onelabel",(const unsigned char *)"\4mail\0", 6);
  nameroundtrip("dotted",  (const unsigned char *)"\7a\\.b\\.c\3net\0", 13);
  nameroundtrip("space",   (const unsigned char *)"\5a b c\3org\0", 11);
  nameroundtrip("highbit", (const unsigned char *)"\3\xc3\xa9x\3com\0", 9);
  {
    /* A 63-byte label is legal; the length byte's top two bits are the
       compression flag, so 64 is not representable at all. */
    unsigned char w[70];
    memset(w, 'z', sizeof w);
    w[0] = 63; w[64] = 0;
    nameroundtrip("label63", w, 65);
  }
  printf("pton bad:\n");
  {
    unsigned char w[NS_MAXCDNAME];
    printf("  empty-label=%d\n", ns_name_pton("a..b", w, sizeof w));
    printf("  trailing-esc=%d\n", ns_name_pton("ab\\", w, sizeof w));
    printf("  short-ddd=%d\n", ns_name_pton("a\\12b", w, sizeof w));
    printf("  tiny-buf=%d\n", ns_name_pton("example.com", w, 4));
    printf("  root-dot=%d\n", ns_name_pton(".", w, sizeof w));
  }
  printf("ntop tiny buffer=%d\n",
         ns_name_ntop((const unsigned char *)"\7example\3com\0",
                      (char[4]){0}, 4));

  printf("=== dn_ wrappers\n");
  {
    char dn[NS_MAXDNAME];
    unsigned char out[NS_PACKETSZ];
    unsigned char *dnptrs[8];
    int n;
    n = dn_expand(pkt, pkt + sizeof pkt, pkt + 12, dn, sizeof dn);
    printf("dn_expand=%d [%s]\n", n, dn);
    printf("dn_skipname=%d\n", dn_skipname(pkt + 12, pkt + sizeof pkt));
    memset(dnptrs, 0, sizeof dnptrs);
    dnptrs[0] = out; dnptrs[1] = 0;
    n = dn_comp("example.com", out, (int)sizeof out, dnptrs, dnptrs + 7);
    printf("dn_comp=%d", n);
    if (n > 0) { int k; printf(" ["); for (k = 0; k < n; k++) printf("%02x", out[k]); printf("]"); }
    printf("\n");
    /* Compressing the SAME name again must produce a 2-byte pointer, which is
       the only row that proves dnptrs is being used rather than ignored. */
    {
      int m = dn_comp("example.com", out + n, (int)sizeof out - n, dnptrs, dnptrs + 7);
      printf("dn_comp again=%d\n", m);
    }
  }

  printf("=== malformed (every row must refuse)\n");
  {
    unsigned char bad[64];
    /* A forward pointer: the name at offset 12 points at offset 20, which is
       ahead of it. Following it would build a name out of bytes that have not
       been validated. */
    memset(bad, 0, sizeof bad);
    memcpy(bad, pkt, 12);
    bad[12] = 0xc0; bad[13] = 20;
    /* THE ONE ROW WHERE crtl AND glibc DISAGREE ON PURPOSE, tagged so it can
       be separated from the diff rather than quietly excluded. glibc follows
       a forward pointer as long as it lands inside the message and the jump
       count stays bounded, and answers 2 here; crtl refuses it. RFC 1035
       4.1.4 says a pointer names "a prior occurrence of the same name", so
       forward is not a thing a conforming server emits, and following one
       builds a name out of bytes the parser has not validated yet. See
       known-incompat/incompat-b-crtl-refuses-a-forward-dns-compression-pointer-where-glibc-follows-it. */
    reject("forward-ptr(STRICTER)", bad, 32);
    /* A pointer at offset 12 aimed at offset 12. */
    memset(bad, 0, sizeof bad);
    memcpy(bad, pkt, 12);
    bad[12] = 0xc0; bad[13] = 12;
    reject("self-ptr", bad, 32);
    /* Two pointers aimed at each other. */
    memset(bad, 0, sizeof bad);
    memcpy(bad, pkt, 12);
    bad[12] = 0xc0; bad[13] = 14;
    bad[14] = 0xc0; bad[15] = 12;
    reject("ptr-loop", bad, 32);
    /* 0x41: the reserved 0x40 label type. Read as a length it is a 65-byte
       overread; the parser must reject it instead. */
    memset(bad, 0, sizeof bad);
    memcpy(bad, pkt, 12);
    bad[12] = 0x41;
    reject("reserved-len", bad, 32);
    /* A length byte that runs past the end of the message. */
    memset(bad, 0, sizeof bad);
    memcpy(bad, pkt, 12);
    bad[12] = 40;
    reject("len-past-eom", bad, 20);
    /* A header that claims records the message does not contain. */
    memcpy(bad, pkt, 12);
    reject("counts-no-data", bad, 12);
  }
  return 0;
}
