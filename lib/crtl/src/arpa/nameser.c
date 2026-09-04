/* SPDX-License-Identifier: Zlib */
/*
 * The DNS wire format: name conversion and message parsing.
 *
 * EVERY FUNCTION HERE READS ATTACKER-SUPPLIED BYTES. A DNS reply arrives from
 * the network and a resolver is one of the few pieces of a C runtime whose
 * entire input is chosen by someone else, so the bounds checks below are the
 * point of the file rather than defensive decoration:
 *
 *   - A COMPRESSION POINTER MAY ONLY POINT BACKWARDS. Two pointers aimed at
 *     each other make an infinite loop out of a 4-byte packet, and a forward
 *     pointer lets a name be built out of bytes that have not been checked
 *     yet. ns_name_unpack() enforces both, and the loop counter is a SECOND
 *     bound rather than the only one, because "strictly backwards" already
 *     terminates and a counter alone would not.
 *   - A LABEL LENGTH BYTE'S TOP TWO BITS SELECT ITS MEANING. 0x00 is a
 *     length, 0xc0 is a pointer, and 0x40 / 0x80 are reserved. Treating a
 *     reserved value as a length is how a 0x41 byte becomes a 65-byte read
 *     past the end of a label.
 *   - THE DESTINATION SIZE IS CHECKED BEFORE EVERY WRITE, not after the loop.
 *     A name that overruns must be refused with EMSGSIZE, never truncated:
 *     a truncated domain name is a DIFFERENT name that still looks valid.
 *
 * NS_MAXDNAME IS 1025 AND NS_MAXCDNAME IS 255, AND THE TWO ARE NOT THE SAME
 * QUANTITY. The wire form is capped at 255 bytes; the presentation form
 * escapes '.', '\\' and every non-printable byte as `\DDD', so one wire byte
 * can become four characters. Sizing a presentation buffer at 256 is the
 * classic overflow in this file's neighbourhood, and it is why ns_name_ntop()
 * takes a size and uses it.
 */

#include <arpa/nameser.h>
#include <string.h>
#include <errno.h>

uint16_t ns_get16(const unsigned char *src)
{
  return (uint16_t)(((uint16_t)src[0] << 8) | (uint16_t)src[1]);
}

uint32_t ns_get32(const unsigned char *src)
{
  return ((uint32_t)src[0] << 24) | ((uint32_t)src[1] << 16) |
         ((uint32_t)src[2] << 8)  | (uint32_t)src[3];
}

void ns_put16(uint16_t src, unsigned char *dst)
{
  dst[0] = (unsigned char)(src >> 8);
  dst[1] = (unsigned char)(src);
}

void ns_put32(uint32_t src, unsigned char *dst)
{
  dst[0] = (unsigned char)(src >> 24);
  dst[1] = (unsigned char)(src >> 16);
  dst[2] = (unsigned char)(src >> 8);
  dst[3] = (unsigned char)(src);
}

/* Uncompressed wire form -> presentation form.
   Returns the number of characters written, or -1 with errno set. */
int ns_name_ntop(const unsigned char *src, char *dst, size_t dstsiz)
{
  const unsigned char *cp = src;
  char *dn = dst;
  const char *eom = dst + dstsiz;
  unsigned int n;

  while ((n = *cp++) != 0) {
    if ((n & NS_CMPRSFLGS) != 0) { errno = EMSGSIZE; return -1; }
    if (n > NS_MAXLABEL)         { errno = EMSGSIZE; return -1; }
    if (dn != dst) {
      if (dn >= eom) { errno = EMSGSIZE; return -1; }
      *dn++ = '.';
    }
    for (; n > 0; n--) {
      unsigned int c = *cp++;
      if (c == '.' || c == '\\' || c == '(' || c == ')' ||
          c == '@' || c == '"'  || c == '$' || c == ';') {
        if (dn + 1 >= eom) { errno = EMSGSIZE; return -1; }
        *dn++ = '\\';
        *dn++ = (char)c;
      } else if (c < 0x21 || c > 0x7e) {
        /* `\DDD' with EXACTLY three digits, always. A variable-width escape
           would be ambiguous the moment a digit follows it: "\7" then "7"
           reads back as "\77". */
        if (dn + 3 >= eom) { errno = EMSGSIZE; return -1; }
        *dn++ = '\\';
        *dn++ = (char)('0' + (c / 100));
        *dn++ = (char)('0' + ((c % 100) / 10));
        *dn++ = (char)('0' + (c % 10));
      } else {
        if (dn >= eom) { errno = EMSGSIZE; return -1; }
        *dn++ = (char)c;
      }
    }
  }
  /* THE ROOT IS "." AND EVERY OTHER NAME IS RELATIVE HERE -- ns_name_ntop
     does NOT append a trailing dot to a non-root name. That is BIND's
     behaviour and callers depend on it: nslookup prints the result directly
     and a trailing dot would appear in its output. */
  if (dn == dst) {
    if (dn >= eom) { errno = EMSGSIZE; return -1; }
    *dn++ = '.';
  }
  if (dn >= eom) { errno = EMSGSIZE; return -1; }
  /* THE RETURN COUNTS THE TERMINATING NUL. "example.com" is 12, not 11, and
     the root "." is 2. That is BIND's contract, measured against glibc rather
     than assumed -- and the off-by-one it invites is silent, since a caller
     using it as a strlen simply drops the last character. */
  *dn++ = '\0';
  return (int)(dn - dst);
}

/* Presentation form -> uncompressed wire form.
   RETURNS 1 IF THE NAME WAS FULLY QUALIFIED, 0 IF NOT, AND -1 ON FAILURE --
   NOT the number of bytes written. That is BIND's contract and it is the one
   thing about this function everybody gets wrong, because 0/1/-1 and a length
   are indistinguishable for a one-byte name: ns_name_pton(".") answers 1
   under both readings. A caller that needs the wire length must walk the
   labels, which is what res_nmkquery() does. Measured against glibc, whose
   ns_name_pton("example.com") answers 0 and not 13. */
int ns_name_pton(const char *src, unsigned char *dst, size_t dstsiz)
{
  unsigned char *label, *bp, *eom;
  int c, n, escaped = 0, qualified = 0;

  label = dst;
  bp = dst + 1;
  eom = dst + dstsiz;
  if (bp >= eom) { errno = EMSGSIZE; return -1; }

  while ((c = *src++) != 0) {
    if (escaped) {
      if (c >= '0' && c <= '9') {
        /* An escape that STARTS with a digit must carry three of them. */
        n = (c - '0') * 100;
        if ((c = *src++) < '0' || c > '9') { errno = EMSGSIZE; return -1; }
        n += (c - '0') * 10;
        if ((c = *src++) < '0' || c > '9') { errno = EMSGSIZE; return -1; }
        n += (c - '0');
        if (n > 255) { errno = EMSGSIZE; return -1; }
        c = n;
      }
      escaped = 0;
    } else if (c == '\\') {
      escaped = 1;
      continue;
    } else if (c == '.') {
      n = (int)(bp - label - 1);
      if (n > NS_MAXLABEL) { errno = EMSGSIZE; return -1; }
      /* A ZERO-LENGTH LABEL IS ONLY LEGAL AS THE FINAL ROOT DOT. "a..b" must
         be refused rather than silently collapsed to "a.b", which would be a
         different name that resolves. */
      if (n == 0) {
        if (*src != '\0') { errno = EMSGSIZE; return -1; }
        qualified = 1;
        break;
      }
      *label = (unsigned char)n;
      label = bp;
      if (bp >= eom) { errno = EMSGSIZE; return -1; }
      bp++;
      continue;
    }
    if (bp >= eom) { errno = EMSGSIZE; return -1; }
    *bp++ = (unsigned char)c;
  }
  if (escaped) { errno = EMSGSIZE; return -1; }

  n = (int)(bp - label - 1);
  if (n > NS_MAXLABEL) { errno = EMSGSIZE; return -1; }
  if (n != 0) {
    *label = (unsigned char)n;
    if (bp >= eom) { errno = EMSGSIZE; return -1; }
    *bp++ = 0;      /* the root label terminates the name */
  } else {
    /* THE LOOP EXITED WITH AN EMPTY FINAL LABEL, which means the input ended
       with a dot -- "example.com." rather than "example.com". This is where a
       fully-qualified name is actually detected: the mid-loop n==0 branch
       only fires for a bare "." or an illegal empty label like "a..b", so
       setting `qualified' there alone would answer 0 for every ordinary
       trailing-dot name. */
    qualified = 1;
    *label = 0;
    bp = label + 1;
  }
  if ((size_t)(bp - dst) > NS_MAXCDNAME) { errno = EMSGSIZE; return -1; }
  return qualified;
}

/* Follow a (possibly compressed) name at `src' and write the UNCOMPRESSED
   wire form to `dst'. Returns how many bytes of the MESSAGE were consumed --
   which is NOT the length written, and mixing the two is the standard bug
   here: after a compression pointer the message advances 2 bytes while the
   output may grow by 250. */
int ns_name_unpack(const unsigned char *msg, const unsigned char *eom,
                   const unsigned char *src, unsigned char *dst, size_t dstsiz)
{
  const unsigned char *srcp = src, *dstlim;
  unsigned char *dstp = dst;
  int n, len = -1, jumps = 0;

  dstlim = dst + dstsiz;
  if (srcp < msg || srcp >= eom) { errno = EMSGSIZE; return -1; }

  while (srcp < eom && (n = *srcp++) != 0) {
    switch (n & NS_CMPRSFLGS) {
    case 0:
      if (srcp + n > eom)      { errno = EMSGSIZE; return -1; }
      if (dstp + n + 1 >= dstlim) { errno = EMSGSIZE; return -1; }
      *dstp++ = (unsigned char)n;
      memcpy(dstp, srcp, (size_t)n);
      dstp += n;
      srcp += n;
      break;
    case NS_CMPRSFLGS: {
      const unsigned char *target;
      if (srcp >= eom) { errno = EMSGSIZE; return -1; }
      if (len < 0) len = (int)(srcp - src + 1);   /* the pointer's 2 bytes */
      target = msg + (((n & 0x3f) << 8) | *srcp++);
      /* STRICTLY BACKWARDS. `>= src' would admit a self-pointer, which is a
         two-byte packet that loops forever. The jump counter below is a
         second, independent bound. glibc has no ordering rule here and
         follows a forward pointer -- a chosen divergence, recorded in
         known-incompat/incompat-b-crtls-dns-parser-refuses-two-malformed-
         packets-glibc-accepts. */
      if (target >= srcp - 2) { errno = EMSGSIZE; return -1; }
      if (target < msg)       { errno = EMSGSIZE; return -1; }
      if (++jumps > NS_MAXCDNAME) { errno = EMSGSIZE; return -1; }
      srcp = target;
      break;
    }
    default:
      /* 0x40 and 0x80 are reserved and have never been assigned. Reading one
         as a length is how a 0x41 byte becomes a 65-byte overread. */
      errno = EMSGSIZE;
      return -1;
    }
  }
  if (dstp >= dstlim) { errno = EMSGSIZE; return -1; }
  *dstp++ = 0;
  if (len < 0) len = (int)(srcp - src);
  return len;
}

int ns_name_uncompress(const unsigned char *msg, const unsigned char *eom,
                       const unsigned char *src, char *dst, size_t dstsiz)
{
  unsigned char tmp[NS_MAXCDNAME];
  int n = ns_name_unpack(msg, eom, src, tmp, sizeof tmp);
  if (n < 0) return -1;
  if (ns_name_ntop(tmp, dst, dstsiz) < 0) return -1;
  return n;
}

/* Write `src' (uncompressed wire form) into `dst', reusing any suffix already
   present in the message via a compression pointer.

   dnptrs[0] MUST POINT AT THE START OF THE MESSAGE and the array is
   NULL-terminated; every offset recorded is relative to dnptrs[0]. Passing a
   dnptrs whose first element is not the message base produces pointers that
   are internally consistent and name the wrong bytes. */
int ns_name_pack(const unsigned char *src, unsigned char *dst, int dstsiz,
                 const unsigned char **dnptrs, const unsigned char **lastdnptr)
{
  unsigned char *dstp = dst;
  const unsigned char *srcp = src;
  const unsigned char **cpp, **lpp, *msg = 0;
  int n;

  if (dnptrs && *dnptrs) {
    msg = *dnptrs++;
    for (cpp = dnptrs; *cpp; cpp++)
      ;
    lpp = cpp;                  /* the first free slot */
  } else {
    lpp = cpp = 0;
  }

  while (*srcp != 0) {
    /* Look for this suffix among the names already written. */
    if (msg) {
      for (cpp = dnptrs; *cpp; cpp++) {
        const unsigned char *a = srcp, *b = *cpp;
        while (*a != 0 && *a == *b) {
          if ((*a & NS_CMPRSFLGS) != 0) break;
          n = *a;
          if (memcmp(a + 1, b + 1, (size_t)n) != 0) break;
          a += n + 1;
          b += n + 1;
        }
        if (*a == 0 && *b == 0) {
          size_t off = (size_t)(*cpp - msg);
          if (off <= 0x3fff) {
            if (dstp + 2 > dst + dstsiz) { errno = EMSGSIZE; return -1; }
            *dstp++ = (unsigned char)((off >> 8) | NS_CMPRSFLGS);
            *dstp++ = (unsigned char)(off & 0xff);
            return (int)(dstp - dst);
          }
        }
      }
      /* Not found: remember where this suffix landed, if there is room. */
      if (lpp && lastdnptr && lpp < lastdnptr) {
        *lpp++ = dstp;
        *lpp = 0;
      }
    }
    n = *srcp;
    if (n > NS_MAXLABEL)                 { errno = EMSGSIZE; return -1; }
    if (dstp + n + 1 > dst + dstsiz)     { errno = EMSGSIZE; return -1; }
    memcpy(dstp, srcp, (size_t)n + 1);
    dstp += n + 1;
    srcp += n + 1;
  }
  if (dstp + 1 > dst + dstsiz) { errno = EMSGSIZE; return -1; }
  *dstp++ = 0;
  return (int)(dstp - dst);
}

int ns_name_compress(const char *src, unsigned char *dst, size_t dstsiz,
                     const unsigned char **dnptrs, const unsigned char **lastdnptr)
{
  unsigned char tmp[NS_MAXCDNAME];
  if (ns_name_pton(src, tmp, sizeof tmp) < 0) return -1;
  return ns_name_pack(tmp, dst, (int)dstsiz, dnptrs, lastdnptr);
}

/* Step over `count' records without decoding them. */
int ns_skiprr(const unsigned char *ptr, const unsigned char *eom,
              ns_sect section, int count)
{
  const unsigned char *optr = ptr;

  for (; count > 0; count--) {
    int b, rdlength;
    b = dn_skipname(ptr, eom);
    if (b < 0) { errno = EMSGSIZE; return -1; }
    ptr += b;
    /* A QUESTION CARRIES type+class AND NOTHING ELSE; every other section
       carries type+class+ttl+rdlength+rdata. Using one shape for both walks
       off by 6 bytes per record and the next name parses as garbage. */
    if (section == ns_s_qd) {
      if (ptr + NS_INT16SZ * 2 > eom) { errno = EMSGSIZE; return -1; }
      ptr += NS_INT16SZ * 2;
    } else {
      if (ptr + NS_INT16SZ * 2 + NS_INT32SZ + NS_INT16SZ > eom) {
        errno = EMSGSIZE; return -1;
      }
      ptr += NS_INT16SZ * 2 + NS_INT32SZ;
      rdlength = ns_get16(ptr);
      ptr += NS_INT16SZ;
      if (ptr + rdlength > eom) { errno = EMSGSIZE; return -1; }
      ptr += rdlength;
    }
  }
  if (ptr > eom) { errno = EMSGSIZE; return -1; }
  return (int)(ptr - optr);
}

int ns_initparse(const unsigned char *msg, int msglen, ns_msg *handle)
{
  const unsigned char *eom = msg + msglen;
  int i;

  if (!handle) { errno = EINVAL; return -1; }
  memset(handle, 0, sizeof *handle);
  handle->_msg = msg;
  handle->_eom = eom;

  if (msg + NS_INT16SZ > eom) { errno = EMSGSIZE; return -1; }
  handle->_id = ns_get16(msg); msg += NS_INT16SZ;
  if (msg + NS_INT16SZ > eom) { errno = EMSGSIZE; return -1; }
  handle->_flags = ns_get16(msg); msg += NS_INT16SZ;

  for (i = 0; i < ns_s_max; i++) {
    if (msg + NS_INT16SZ > eom) { errno = EMSGSIZE; return -1; }
    handle->_counts[i] = ns_get16(msg);
    msg += NS_INT16SZ;
  }
  for (i = 0; i < ns_s_max; i++) {
    if (handle->_counts[i] == 0) {
      handle->_sections[i] = 0;
    } else {
      int b = ns_skiprr(msg, eom, (ns_sect)i, handle->_counts[i]);
      if (b < 0) return -1;
      handle->_sections[i] = msg;
      msg += b;
    }
  }
  if (msg != eom) { errno = EMSGSIZE; return -1; }
  handle->_sect = ns_s_max;
  handle->_rrnum = -1;
  handle->_msg_ptr = 0;
  return 0;
}

/* THE HANDLE CACHES A CURSOR AND THAT IS WHY THIS IS FAST FOR A FORWARD WALK
   AND CORRECT FOR A RANDOM ONE. Asking for record n+1 after record n resumes
   where the last one stopped; asking for any other index re-walks the section
   from its start. A caller looping `for (i = 0; i < count; i++)' -- which is
   what nslookup does -- takes the cheap path every time without knowing it. */
int ns_parserr(ns_msg *handle, ns_sect section, int rrnum, ns_rr *rr)
{
  const unsigned char *p;
  int b;

  if ((int)section < 0 || section >= ns_s_max) { errno = ENODEV; return -1; }
  if (section != handle->_sect) {
    handle->_sect = section;
    handle->_rrnum = 0;
    handle->_msg_ptr = handle->_sections[section];
  }
  if (rrnum == -1) rrnum = handle->_rrnum;
  if (rrnum < 0 || rrnum >= handle->_counts[section]) { errno = ENODEV; return -1; }
  if (rrnum < handle->_rrnum) {
    handle->_rrnum = 0;
    handle->_msg_ptr = handle->_sections[section];
  }
  if (rrnum > handle->_rrnum) {
    b = ns_skiprr(handle->_msg_ptr, handle->_eom, section,
                  rrnum - handle->_rrnum);
    if (b < 0) return -1;
    handle->_msg_ptr += b;
    handle->_rrnum = rrnum;
  }
  p = handle->_msg_ptr;

  b = ns_name_uncompress(handle->_msg, handle->_eom, p,
                         rr->name, NS_MAXDNAME);
  if (b < 0) return -1;
  p += b;
  if (p + NS_INT16SZ + NS_INT16SZ > handle->_eom) { errno = EMSGSIZE; return -1; }
  rr->type     = ns_get16(p); p += NS_INT16SZ;
  rr->rr_class = ns_get16(p); p += NS_INT16SZ;
  if (section == ns_s_qd) {
    rr->ttl = 0;
    rr->rdlength = 0;
    rr->rdata = 0;
  } else {
    if (p + NS_INT32SZ + NS_INT16SZ > handle->_eom) { errno = EMSGSIZE; return -1; }
    rr->ttl      = ns_get32(p); p += NS_INT32SZ;
    rr->rdlength = ns_get16(p); p += NS_INT16SZ;
    if (p + rr->rdlength > handle->_eom) { errno = EMSGSIZE; return -1; }
    rr->rdata = p;
    p += rr->rdlength;
  }
  handle->_msg_ptr = p;
  handle->_rrnum = rrnum + 1;
  return 0;
}

/* (mask, shift) per ns_flag, in the enum's order. The header says these are
   INDICES and this is the table they index. */
static const struct { int mask, shift; } ns_flagdata[16] = {
  { 0x8000, 15 },   /* ns_f_qr     */
  { 0x7800, 11 },   /* ns_f_opcode */
  { 0x0400, 10 },   /* ns_f_aa     */
  { 0x0200,  9 },   /* ns_f_tc     */
  { 0x0100,  8 },   /* ns_f_rd     */
  { 0x0080,  7 },   /* ns_f_ra     */
  { 0x0040,  6 },   /* ns_f_z      */
  { 0x0020,  5 },   /* ns_f_ad     */
  { 0x0010,  4 },   /* ns_f_cd     */
  { 0x000f,  0 },   /* ns_f_rcode  */
  { 0x0000,  0 },
  { 0x0000,  0 },
  { 0x0000,  0 },
  { 0x0000,  0 },
  { 0x0000,  0 },
  { 0x0000,  0 },
};

int ns_msg_getflag(ns_msg handle, int flag)
{
  if (flag < 0 || flag >= ns_f_max) return 0;
  return (handle._flags & ns_flagdata[flag].mask) >> ns_flagdata[flag].shift;
}

int dn_skipname(const unsigned char *ptr, const unsigned char *eom)
{
  const unsigned char *saveptr = ptr;
  int n;

  while (ptr < eom && (n = *ptr++) != 0) {
    switch (n & NS_CMPRSFLGS) {
    case 0:
      ptr += n;
      break;
    case NS_CMPRSFLGS:
      /* A pointer ENDS the name here; nothing is followed, so no loop is
         possible and none needs guarding against. */
      ptr++;
      return (int)(ptr - saveptr);
    default:
      errno = EMSGSIZE;
      return -1;
    }
  }
  if (ptr > eom) { errno = EMSGSIZE; return -1; }
  return (int)(ptr - saveptr);
}

int dn_expand(const unsigned char *msg, const unsigned char *eom,
              const unsigned char *src, char *dst, int dstsiz)
{
  int n = ns_name_uncompress(msg, eom, src, dst, (size_t)dstsiz);
  /* dn_expand() DOES DECODE THE ROOT AS "" AND ns_name_uncompress() AS ".".
     BIND made that distinction and callers rely on it: dn_expand's caller
     usually concatenates the result, where a stray "." would appear. */
  if (n > 0 && dst[0] == '.') dst[0] = '\0';
  return n;
}

int dn_comp(const char *src, unsigned char *dst, int dstsiz,
            unsigned char **dnptrs, unsigned char **lastdnptr)
{
  return ns_name_compress(src, dst, (size_t)dstsiz,
                          (const unsigned char **)dnptrs,
                          (const unsigned char **)lastdnptr);
}
