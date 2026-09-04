/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <arpa/nameser.h> -- the DNS wire format, and the parser for it.
 *
 * THE NUMBERS ARE RFC ASSIGNMENTS, NOT glibc's CHOICES, which is why they are
 * generated from this box's header rather than typed: every one of them also
 * appears in an IANA registry, so the header is a transcription and a
 * transcription is where a digit gets dropped. The value diff in
 * test/c_crtl_resolv.c is what actually holds them.
 *
 * ns_s_qd AND ns_s_zn ARE BOTH 0, AND THAT IS NOT A BUG TO TIDY. A DNS message
 * has four sections whose MEANING depends on the opcode: in a query, section 0
 * is the question and section 2 is the authority; in a dynamic update
 * (RFC 2136) the same four slots are zone, prerequisite, update and
 * additional. The duplicated enumerators are the two vocabularies for one
 * wire layout, so `ns_s_qd == ns_s_zn' is the design.
 *
 * ns_c_max IS 65536 AND DOES NOT FIT THE FIELD IT DESCRIBES. The class is 16
 * bits on the wire, so the largest real class is 65535; the enumerator is a
 * one-past-the-end bound, in the C idiom, and a program that treats it as a
 * class will emit a 17-bit value truncated to 0. Kept because callers switch
 * on it, and because renaming it would be a compat break for no gain.
 *
 * ns_r_badvers AND ns_r_badsig ARE BOTH 16. That collision is in the protocol,
 * not the header: EDNS0 and TSIG each numbered their first error 16 and the
 * two live in different parts of a message. A parser cannot tell them apart
 * from the rcode alone, and neither can this enum.
 *
 * Found attempting busybox on i386: networking/nslookup.c, reached through
 * <resolv.h>.
 * bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS
 */
#ifndef _CRTL_ARPA_NAMESER_H
#define _CRTL_ARPA_NAMESER_H

#include <stdint.h>
#include <sys/types.h>

/* Sizes and limits. NS_MAXDNAME is the PRESENTATION form (dots and escapes),
   which is why it is 1025 and not 255: the wire form is capped at 255 bytes,
   and a label full of characters needing `\DDD' escapes expands. Sizing a
   buffer at 256 because "a domain name is 255 bytes" is the classic overflow
   here, and ns_name_ntop is the function that writes past it. */
#define NS_PACKETSZ    512      /* a DNS message that fits one UDP datagram  */
#define NS_MAXDNAME    1025     /* a domain name in PRESENTATION form        */
#define NS_MAXMSG      65535    /* a DNS message over TCP                    */
#define NS_MAXCDNAME   255      /* a domain name in COMPRESSED wire form     */
#define NS_MAXLABEL    63       /* one label; the top two bits are the
                                   compression flag, hence 63 and not 255    */
#define NS_HFIXEDSZ    12       /* the fixed header                          */
#define NS_QFIXEDSZ    4        /* type + class, after the question's name   */
#define NS_RRFIXEDSZ   10       /* type + class + ttl + rdlength             */
#define NS_INT32SZ     4
#define NS_INT16SZ     2
#define NS_INT8SZ      1
#define NS_INADDRSZ    4
#define NS_IN6ADDRSZ   16
#define NS_CMPRSFLGS   0xc0     /* both top bits set: a compression pointer  */
#define NS_DEFAULTPORT 53

/* Which of the four sections. See the note above about the two vocabularies. */
typedef enum __ns_sect {
  ns_s_qd = 0,
  ns_s_zn = 0,
  ns_s_an = 1,
  ns_s_pr = 1,
  ns_s_ns = 2,
  ns_s_ud = 2,
  ns_s_ar = 3,
  ns_s_max = 4
} ns_sect;

/* Header flag fields, for ns_msg_getflag(). These are INDICES into a table of
   (mask, shift) pairs, not masks themselves -- ns_f_rcode is 9, not 0xf. */
typedef enum __ns_flag {
  ns_f_qr = 0,
  ns_f_opcode = 1,
  ns_f_aa = 2,
  ns_f_tc = 3,
  ns_f_rd = 4,
  ns_f_ra = 5,
  ns_f_z = 6,
  ns_f_ad = 7,
  ns_f_cd = 8,
  ns_f_rcode = 9,
  ns_f_max = 10
} ns_flag;

typedef enum __ns_opcode {
  ns_o_query = 0,
  ns_o_iquery = 1,
  ns_o_status = 2,
  ns_o_notify = 4,
  ns_o_update = 5,
  ns_o_max = 6
} ns_opcode;

typedef enum __ns_rcode {
  ns_r_noerror = 0,
  ns_r_formerr = 1,
  ns_r_servfail = 2,
  ns_r_nxdomain = 3,
  ns_r_notimpl = 4,
  ns_r_refused = 5,
  ns_r_yxdomain = 6,
  ns_r_yxrrset = 7,
  ns_r_nxrrset = 8,
  ns_r_notauth = 9,
  ns_r_notzone = 10,
  ns_r_max = 11,
  ns_r_badvers = 16,
  ns_r_badsig = 16,
  ns_r_badkey = 17,
  ns_r_badtime = 18
} ns_rcode;

typedef enum __ns_class {
  ns_c_invalid = 0,
  ns_c_in = 1,
  ns_c_2 = 2,
  ns_c_chaos = 3,
  ns_c_hs = 4,
  ns_c_none = 254,
  ns_c_any = 255,
  ns_c_max = 65536
} ns_class;

typedef enum __ns_type {
  ns_t_invalid = 0,
  ns_t_a = 1,
  ns_t_ns = 2,
  ns_t_md = 3,
  ns_t_mf = 4,
  ns_t_cname = 5,
  ns_t_soa = 6,
  ns_t_mb = 7,
  ns_t_mg = 8,
  ns_t_mr = 9,
  ns_t_null = 10,
  ns_t_wks = 11,
  ns_t_ptr = 12,
  ns_t_hinfo = 13,
  ns_t_minfo = 14,
  ns_t_mx = 15,
  ns_t_txt = 16,
  ns_t_rp = 17,
  ns_t_afsdb = 18,
  ns_t_x25 = 19,
  ns_t_isdn = 20,
  ns_t_rt = 21,
  ns_t_nsap = 22,
  ns_t_nsap_ptr = 23,
  ns_t_sig = 24,
  ns_t_key = 25,
  ns_t_px = 26,
  ns_t_gpos = 27,
  ns_t_aaaa = 28,
  ns_t_loc = 29,
  ns_t_nxt = 30,
  ns_t_eid = 31,
  ns_t_nimloc = 32,
  ns_t_srv = 33,
  ns_t_atma = 34,
  ns_t_naptr = 35,
  ns_t_kx = 36,
  ns_t_cert = 37,
  ns_t_a6 = 38,
  ns_t_dname = 39,
  ns_t_sink = 40,
  ns_t_opt = 41,
  ns_t_apl = 42,
  ns_t_ds = 43,
  ns_t_sshfp = 44,
  ns_t_ipseckey = 45,
  ns_t_rrsig = 46,
  ns_t_nsec = 47,
  ns_t_dnskey = 48,
  ns_t_dhcid = 49,
  ns_t_nsec3 = 50,
  ns_t_nsec3param = 51,
  ns_t_tlsa = 52,
  ns_t_smimea = 53,
  ns_t_hip = 55,
  ns_t_ninfo = 56,
  ns_t_rkey = 57,
  ns_t_talink = 58,
  ns_t_cds = 59,
  ns_t_cdnskey = 60,
  ns_t_openpgpkey = 61,
  ns_t_csync = 62,
  ns_t_spf = 99,
  ns_t_uinfo = 100,
  ns_t_uid = 101,
  ns_t_gid = 102,
  ns_t_unspec = 103,
  ns_t_nid = 104,
  ns_t_l32 = 105,
  ns_t_l64 = 106,
  ns_t_lp = 107,
  ns_t_eui48 = 108,
  ns_t_eui64 = 109,
  ns_t_tkey = 249,
  ns_t_tsig = 250,
  ns_t_ixfr = 251,
  ns_t_axfr = 252,
  ns_t_mailb = 253,
  ns_t_maila = 254,
  ns_t_any = 255,
  ns_t_uri = 256,
  ns_t_caa = 257,
  ns_t_avc = 258,
  ns_t_ta = 32768,
  ns_t_dlv = 32769,
  ns_t_max = 65536
} ns_type;

/* A PARSED MESSAGE. The pointers are INTO the caller's buffer and nothing here
   is allocated, so the handle is only valid while that buffer is. Copying a
   ns_msg and freeing the packet leaves every accessor reading freed memory,
   and ns_rr_name() would keep returning plausible text for a while. */
typedef struct __ns_msg {
  const unsigned char *_msg, *_eom;
  uint16_t             _id, _flags, _counts[ns_s_max];
  const unsigned char *_sections[ns_s_max];
  ns_sect              _sect;
  int                  _rrnum;
  const unsigned char *_msg_ptr;
} ns_msg;

/* A PARSED RECORD. Caller-allocated, no dynamic data -- but `rdata' still
   points into the message buffer, so the lifetime rule above applies to it
   too. Only `name' is copied out. */
typedef struct __ns_rr {
  char                 name[NS_MAXDNAME];
  uint16_t             type;
  uint16_t             rr_class;
  uint32_t             ttl;
  uint16_t             rdlength;
  const unsigned char *rdata;
} ns_rr;

/* Accessors. Part of the public interface, and they take the handle BY VALUE
   -- ns_msg_count(handle, sect), not (&handle). The `+ 0' is not decoration:
   it makes each one an rvalue, so `ns_rr_type(rr) = x' fails to compile
   rather than assigning into the parsed record. */
#define ns_msg_id(handle)          ((handle)._id + 0)
#define ns_msg_base(handle)        ((handle)._msg + 0)
#define ns_msg_end(handle)         ((handle)._eom + 0)
#define ns_msg_size(handle)        ((handle)._eom - (handle)._msg)
#define ns_msg_count(handle, sect) ((handle)._counts[sect] + 0)

/* ns_rr_name() RETURNS "." FOR THE ROOT, not "". The root's wire form is a
   single zero byte and its presentation form is a lone dot; an empty string
   would print as nothing and read as a missing value. */
#define ns_rr_name(rr)   (((rr).name[0] != '\0') ? (rr).name : ".")
#define ns_rr_type(rr)   ((ns_type)((rr).type + 0))
#define ns_rr_class(rr)  ((ns_class)((rr).rr_class + 0))
#define ns_rr_ttl(rr)    ((rr).ttl + 0)
#define ns_rr_rdlen(rr)  ((rr).rdlength + 0)
#define ns_rr_rdata(rr)  ((rr).rdata + 0)

/* Wire integers are BIG-ENDIAN regardless of the host, which is why these are
   byte-at-a-time rather than a cast plus ntohs: the source pointer is into a
   received packet and has no alignment guarantee at all. A `*(uint16_t*)cp'
   is a wrong answer on the targets that require alignment and a silent
   success on x86-64, which is the worst combination. */
uint16_t ns_get16(const unsigned char *src);
uint32_t ns_get32(const unsigned char *src);
void     ns_put16(uint16_t src, unsigned char *dst);
void     ns_put32(uint32_t src, unsigned char *dst);

int ns_initparse(const unsigned char *msg, int msglen, ns_msg *handle);
int ns_parserr(ns_msg *handle, ns_sect section, int rrnum, ns_rr *rr);
int ns_skiprr(const unsigned char *ptr, const unsigned char *eom,
              ns_sect section, int count);
int ns_msg_getflag(ns_msg handle, int flag);

/* Name conversion. `msg' and `eom' bound the packet so a compression pointer
   cannot escape it; `comp_dn'/`src' is where the name starts. */
int ns_name_ntop(const unsigned char *src, char *dst, size_t dstsiz);
int ns_name_pton(const char *src, unsigned char *dst, size_t dstsiz);
int ns_name_unpack(const unsigned char *msg, const unsigned char *eom,
                   const unsigned char *src, unsigned char *dst, size_t dstsiz);
int ns_name_pack(const unsigned char *src, unsigned char *dst, int dstsiz,
                 const unsigned char **dnptrs, const unsigned char **lastdnptr);
int ns_name_uncompress(const unsigned char *msg, const unsigned char *eom,
                       const unsigned char *src, char *dst, size_t dstsiz);
int ns_name_compress(const char *src, unsigned char *dst, size_t dstsiz,
                     const unsigned char **dnptrs, const unsigned char **lastdnptr);

#include <arpa/nameser_compat.h>

#endif /* _CRTL_ARPA_NAMESER_H */
