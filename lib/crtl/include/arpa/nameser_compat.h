/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <arpa/nameser_compat.h> -- the pre-BIND8 spellings.
 *
 * ONE VOCABULARY, TWO SPELLINGS. T_A is ns_t_a and C_IN is ns_c_in; nothing
 * here has a value of its own. They exist because a large amount of real code
 * -- busybox's nslookup among it -- was written against the older names, and
 * <arpa/nameser.h> includes this file for exactly that reason.
 *
 * `struct HEADER' IS BITFIELDS OVER THE WIRE AND ITS FIELD ORDER DEPENDS ON
 * THE BYTE ORDER. That is not a portability wart to fix: the DNS header's
 * flag byte is defined bit by bit, and a C compiler lays bitfields out from
 * the least significant end on a little-endian target and the most
 * significant end on a big-endian one. The two arms below are what makes the
 * SAME field names describe the SAME wire bits on both. Every pxx target is
 * little-endian today, so the big-endian arm is unexercised here and is kept
 * correct rather than dropped -- a struct that silently means something else
 * on a future target is worse than one that does not compile.
 *
 * PREFER ns_msg AND ns_msg_getflag() TO THIS STRUCT. `struct HEADER' assumes
 * the caller has the whole message in a suitably aligned buffer and casts it
 * in place; ns_initparse() copies the fixed fields out and bounds-checks the
 * message first.
 */
#ifndef _CRTL_ARPA_NAMESER_COMPAT_H
#define _CRTL_ARPA_NAMESER_COMPAT_H

#include <endian.h>

#define PACKETSZ    NS_PACKETSZ
#define MAXDNAME    NS_MAXDNAME
#define MAXCDNAME   NS_MAXCDNAME
#define MAXLABEL    NS_MAXLABEL
#define HFIXEDSZ    NS_HFIXEDSZ
#define QFIXEDSZ    NS_QFIXEDSZ
#define RRFIXEDSZ   NS_RRFIXEDSZ
#define INT32SZ     NS_INT32SZ
#define INT16SZ     NS_INT16SZ
#define INADDRSZ    NS_INADDRSZ
#define IN6ADDRSZ   NS_IN6ADDRSZ
#define INDIR_MASK  NS_CMPRSFLGS
#define NAMESERVER_PORT NS_DEFAULTPORT

typedef struct {
  unsigned  id     :16;   /* query identification number */
#if __BYTE_ORDER == __BIG_ENDIAN
  unsigned  qr     : 1;   /* response flag */
  unsigned  opcode : 4;   /* purpose of message */
  unsigned  aa     : 1;   /* authoritative answer */
  unsigned  tc     : 1;   /* truncated message */
  unsigned  rd     : 1;   /* recursion desired */
  unsigned  ra     : 1;   /* recursion available */
  unsigned  unused : 1;
  unsigned  ad     : 1;   /* authentic data from named */
  unsigned  cd     : 1;   /* checking disabled by resolver */
  unsigned  rcode  : 4;   /* response code */
#else
  unsigned  rd     : 1;
  unsigned  tc     : 1;
  unsigned  aa     : 1;
  unsigned  opcode : 4;
  unsigned  qr     : 1;
  unsigned  rcode  : 4;
  unsigned  cd     : 1;
  unsigned  ad     : 1;
  unsigned  unused : 1;
  unsigned  ra     : 1;
#endif
  unsigned  qdcount:16;   /* number of question entries */
  unsigned  ancount:16;   /* number of answer entries */
  unsigned  nscount:16;   /* number of authority entries */
  unsigned  arcount:16;   /* number of resource entries */
} HEADER;

/* Opcodes. */
#define QUERY       ns_o_query
#define IQUERY      ns_o_iquery
#define STATUS      ns_o_status
#define NS_NOTIFY_OP ns_o_notify
#define NS_UPDATE_OP ns_o_update

/* Response codes. */
#define NOERROR     ns_r_noerror
#define FORMERR     ns_r_formerr
#define SERVFAIL    ns_r_servfail
#define NXDOMAIN    ns_r_nxdomain
#define NOTIMP      ns_r_notimpl
#define REFUSED     ns_r_refused
#define YXDOMAIN    ns_r_yxdomain
#define YXRRSET     ns_r_yxrrset
#define NXRRSET     ns_r_nxrrset
#define NOTAUTH     ns_r_notauth
#define NOTZONE     ns_r_notzone

/* Types. */
#define T_A              ns_t_a
#define T_NS             ns_t_ns
#define T_MD             ns_t_md
#define T_MF             ns_t_mf
#define T_CNAME          ns_t_cname
#define T_SOA            ns_t_soa
#define T_MB             ns_t_mb
#define T_MG             ns_t_mg
#define T_MR             ns_t_mr
#define T_NULL           ns_t_null
#define T_WKS            ns_t_wks
#define T_PTR            ns_t_ptr
#define T_HINFO          ns_t_hinfo
#define T_MINFO          ns_t_minfo
#define T_MX             ns_t_mx
#define T_TXT            ns_t_txt
#define T_RP             ns_t_rp
#define T_AFSDB          ns_t_afsdb
#define T_X25            ns_t_x25
#define T_ISDN           ns_t_isdn
#define T_RT             ns_t_rt
#define T_NSAP           ns_t_nsap
#define T_NSAP_PTR       ns_t_nsap_ptr
#define T_SIG            ns_t_sig
#define T_KEY            ns_t_key
#define T_PX             ns_t_px
#define T_GPOS           ns_t_gpos
#define T_AAAA           ns_t_aaaa
#define T_LOC            ns_t_loc
#define T_NXT            ns_t_nxt
#define T_EID            ns_t_eid
#define T_NIMLOC         ns_t_nimloc
#define T_SRV            ns_t_srv
#define T_ATMA           ns_t_atma
#define T_NAPTR          ns_t_naptr
#define T_KX             ns_t_kx
#define T_CERT           ns_t_cert
#define T_A6             ns_t_a6
#define T_DNAME          ns_t_dname
#define T_SINK           ns_t_sink
#define T_OPT            ns_t_opt
#define T_APL            ns_t_apl
#define T_DS             ns_t_ds
#define T_SSHFP          ns_t_sshfp
#define T_IPSECKEY       ns_t_ipseckey
#define T_RRSIG          ns_t_rrsig
#define T_NSEC           ns_t_nsec
#define T_DNSKEY         ns_t_dnskey
#define T_DHCID          ns_t_dhcid
#define T_NSEC3          ns_t_nsec3
#define T_NSEC3PARAM     ns_t_nsec3param
#define T_TLSA           ns_t_tlsa
#define T_SMIMEA         ns_t_smimea
#define T_HIP            ns_t_hip
#define T_NINFO          ns_t_ninfo
#define T_RKEY           ns_t_rkey
#define T_TALINK         ns_t_talink
#define T_CDS            ns_t_cds
#define T_CDNSKEY        ns_t_cdnskey
#define T_OPENPGPKEY     ns_t_openpgpkey
#define T_CSYNC          ns_t_csync
#define T_SPF            ns_t_spf
#define T_UINFO          ns_t_uinfo
#define T_UID            ns_t_uid
#define T_GID            ns_t_gid
#define T_UNSPEC         ns_t_unspec
#define T_NID            ns_t_nid
#define T_L32            ns_t_l32
#define T_L64            ns_t_l64
#define T_LP             ns_t_lp
#define T_EUI48          ns_t_eui48
#define T_EUI64          ns_t_eui64
#define T_TKEY           ns_t_tkey
#define T_TSIG           ns_t_tsig
#define T_IXFR           ns_t_ixfr
#define T_AXFR           ns_t_axfr
#define T_MAILB          ns_t_mailb
#define T_MAILA          ns_t_maila
#define T_ANY            ns_t_any
#define T_URI            ns_t_uri
#define T_CAA            ns_t_caa
#define T_AVC            ns_t_avc
#define T_TA             ns_t_ta
#define T_DLV            ns_t_dlv

/* Classes. */
#define C_IN             ns_c_in
#define C_CHAOS          ns_c_chaos
#define C_HS             ns_c_hs
#define C_NONE           ns_c_none
#define C_ANY            ns_c_any

#endif /* _CRTL_ARPA_NAMESER_COMPAT_H */
