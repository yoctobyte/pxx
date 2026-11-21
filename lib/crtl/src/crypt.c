/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: crypt(3) for SHA-crypt, "$5$" (SHA-256) and "$6$" (SHA-512),
 * per Ulrich Drepper's specification ("Unix crypt using SHA-256 and
 * SHA-512", 2007/2008). That is the scheme glibc, musl and Alpine use for
 * /etc/shadow.
 *
 * Found building dropbear (feature-c-dropbear-builds-with-pxx):
 * svr-authpasswd.c compares crypt(password, stored) with the stored hash.
 *
 * MD5-crypt ("$1$") is here too, since toybox's `mkpasswd -m md5` needed it.
 *
 * WHAT IS NOT HERE, and how it fails: yescrypt ("$y$", the default on current
 * Debian/Ubuntu), bcrypt ("$2b$") and traditional DES.
 * For those crypt() returns NULL with errno EINVAL. glibc does the same for a
 * scheme it lacks. dropbear treats NULL as a failed password check and logs
 * it, so an account hashed with one of those cannot log in by password through
 * a pxx-built dropbear. Public-key login is unaffected.
 *
 * Checked against libxcrypt's crypt() on the same inputs (see
 * test/c_crypt_sha.c).
 *
 * The SHA-256 and SHA-512 cores are private to this file: crypt.h is the only
 * public surface, and nothing else in crtl hashes yet.
 */
#include <crypt.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <stdint.h>

/* ---- SHA-256 (FIPS 180-4) ------------------------------------------------ */

typedef struct {
  uint32_t h[8];
  uint64_t len;
  unsigned char buf[64];
  size_t fill;
} sha256_ctx;

static const uint32_t K256[64] = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

#define ROR32(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void sha256_block(sha256_ctx *c, const unsigned char *p)
{
  uint32_t w[64], a, b, d, e, f, g, h, cc, t1, t2;
  int i;
  for (i = 0; i < 16; i++)
    w[i] = ((uint32_t)p[4*i] << 24) | ((uint32_t)p[4*i+1] << 16)
         | ((uint32_t)p[4*i+2] << 8) | (uint32_t)p[4*i+3];
  for (i = 16; i < 64; i++) {
    uint32_t s0 = ROR32(w[i-15], 7) ^ ROR32(w[i-15], 18) ^ (w[i-15] >> 3);
    uint32_t s1 = ROR32(w[i-2], 17) ^ ROR32(w[i-2], 19) ^ (w[i-2] >> 10);
    w[i] = w[i-16] + s0 + w[i-7] + s1;
  }
  a = c->h[0]; b = c->h[1]; cc = c->h[2]; d = c->h[3];
  e = c->h[4]; f = c->h[5]; g = c->h[6]; h = c->h[7];
  for (i = 0; i < 64; i++) {
    t1 = h + (ROR32(e, 6) ^ ROR32(e, 11) ^ ROR32(e, 25)) + ((e & f) ^ (~e & g)) + K256[i] + w[i];
    t2 = (ROR32(a, 2) ^ ROR32(a, 13) ^ ROR32(a, 22)) + ((a & b) ^ (a & cc) ^ (b & cc));
    h = g; g = f; f = e; e = d + t1; d = cc; cc = b; b = a; a = t1 + t2;
  }
  c->h[0] += a; c->h[1] += b; c->h[2] += cc; c->h[3] += d;
  c->h[4] += e; c->h[5] += f; c->h[6] += g; c->h[7] += h;
}

static void sha256_init(sha256_ctx *c)
{
  static const uint32_t iv[8] = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 };
  memcpy(c->h, iv, sizeof iv);
  c->len = 0;
  c->fill = 0;
}

static void sha256_update(sha256_ctx *c, const void *data, size_t n)
{
  const unsigned char *p = (const unsigned char *)data;
  c->len += n;
  while (n > 0) {
    size_t k = 64 - c->fill;
    if (k > n) k = n;
    memcpy(c->buf + c->fill, p, k);
    c->fill += k; p += k; n -= k;
    if (c->fill == 64) { sha256_block(c, c->buf); c->fill = 0; }
  }
}

static void sha256_final(sha256_ctx *c, unsigned char out[32])
{
  uint64_t bits = c->len * 8;
  unsigned char pad = 0x80, z = 0, lenb[8];
  int i;
  sha256_update(c, &pad, 1);
  while (c->fill != 56) sha256_update(c, &z, 1);
  for (i = 0; i < 8; i++) lenb[i] = (unsigned char)(bits >> (56 - 8 * i));
  sha256_update(c, lenb, 8);
  for (i = 0; i < 8; i++) {
    out[4*i] = (unsigned char)(c->h[i] >> 24); out[4*i+1] = (unsigned char)(c->h[i] >> 16);
    out[4*i+2] = (unsigned char)(c->h[i] >> 8); out[4*i+3] = (unsigned char)c->h[i];
  }
}

/* ---- SHA-512 (FIPS 180-4) ------------------------------------------------ */

typedef struct {
  uint64_t h[8];
  uint64_t len;
  unsigned char buf[128];
  size_t fill;
} sha512_ctx;

static const uint64_t K512[80] = {
  0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL, 0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
  0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL, 0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
  0xd807aa98a3030242ULL, 0x12835b0145706fbeULL, 0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
  0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL, 0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
  0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL, 0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
  0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL, 0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
  0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL, 0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
  0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL, 0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
  0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL, 0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
  0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL, 0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
  0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL, 0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
  0xd192e819d6ef5218ULL, 0xd69906245565a910ULL, 0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
  0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL, 0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
  0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL, 0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
  0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL, 0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
  0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL, 0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
  0xca273eceea26619cULL, 0xd186b8c721c0c207ULL, 0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
  0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL, 0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
  0x28db77f523047d84ULL, 0x32caab7b40c72493ULL, 0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
  0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL, 0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL
};

#define ROR64(x, n) (((x) >> (n)) | ((x) << (64 - (n))))

static void sha512_block(sha512_ctx *c, const unsigned char *p)
{
  uint64_t w[80], a, b, cc, d, e, f, g, h, t1, t2;
  int i, j;
  for (i = 0; i < 16; i++) {
    w[i] = 0;
    for (j = 0; j < 8; j++) w[i] = (w[i] << 8) | p[8*i + j];
  }
  for (i = 16; i < 80; i++) {
    uint64_t s0 = ROR64(w[i-15], 1) ^ ROR64(w[i-15], 8) ^ (w[i-15] >> 7);
    uint64_t s1 = ROR64(w[i-2], 19) ^ ROR64(w[i-2], 61) ^ (w[i-2] >> 6);
    w[i] = w[i-16] + s0 + w[i-7] + s1;
  }
  a = c->h[0]; b = c->h[1]; cc = c->h[2]; d = c->h[3];
  e = c->h[4]; f = c->h[5]; g = c->h[6]; h = c->h[7];
  for (i = 0; i < 80; i++) {
    t1 = h + (ROR64(e, 14) ^ ROR64(e, 18) ^ ROR64(e, 41)) + ((e & f) ^ (~e & g)) + K512[i] + w[i];
    t2 = (ROR64(a, 28) ^ ROR64(a, 34) ^ ROR64(a, 39)) + ((a & b) ^ (a & cc) ^ (b & cc));
    h = g; g = f; f = e; e = d + t1; d = cc; cc = b; b = a; a = t1 + t2;
  }
  c->h[0] += a; c->h[1] += b; c->h[2] += cc; c->h[3] += d;
  c->h[4] += e; c->h[5] += f; c->h[6] += g; c->h[7] += h;
}

static void sha512_init(sha512_ctx *c)
{
  static const uint64_t iv[8] = {
    0x6a09e667f3bcc908ULL, 0xbb67ae8584caa73bULL, 0x3c6ef372fe94f82bULL, 0xa54ff53a5f1d36f1ULL,
    0x510e527fade682d1ULL, 0x9b05688c2b3e6c1fULL, 0x1f83d9abfb41bd6bULL, 0x5be0cd19137e2179ULL };
  memcpy(c->h, iv, sizeof iv);
  c->len = 0;
  c->fill = 0;
}

static void sha512_update(sha512_ctx *c, const void *data, size_t n)
{
  const unsigned char *p = (const unsigned char *)data;
  c->len += n;
  while (n > 0) {
    size_t k = 128 - c->fill;
    if (k > n) k = n;
    memcpy(c->buf + c->fill, p, k);
    c->fill += k; p += k; n -= k;
    if (c->fill == 128) { sha512_block(c, c->buf); c->fill = 0; }
  }
}

/* The length field is 128 bits; a password hash never needs the top half. */
static void sha512_final(sha512_ctx *c, unsigned char out[64])
{
  uint64_t bits = c->len * 8;
  unsigned char pad = 0x80, z = 0, lenb[16];
  int i, j;
  sha512_update(c, &pad, 1);
  while (c->fill != 112) sha512_update(c, &z, 1);
  for (i = 0; i < 8; i++) lenb[i] = 0;
  for (i = 0; i < 8; i++) lenb[8 + i] = (unsigned char)(bits >> (56 - 8 * i));
  sha512_update(c, lenb, 16);
  for (i = 0; i < 8; i++)
    for (j = 0; j < 8; j++)
      out[8*i + j] = (unsigned char)(c->h[i] >> (56 - 8 * j));
}

/* ---- one interface over both, for the shared algorithm ------------------- */

typedef struct {
  int is512;
  union { sha256_ctx s256; sha512_ctx s512; } u;
} hctx;

static void h_init(hctx *c, int is512)
{
  c->is512 = is512;
  if (is512) sha512_init(&c->u.s512); else sha256_init(&c->u.s256);
}

static void h_update(hctx *c, const void *p, size_t n)
{
  if (c->is512) sha512_update(&c->u.s512, p, n); else sha256_update(&c->u.s256, p, n);
}

static void h_final(hctx *c, unsigned char *out)
{
  if (c->is512) sha512_final(&c->u.s512, out); else sha256_final(&c->u.s256, out);
}

/* ---- SHA-crypt ----------------------------------------------------------- */

#define SALT_MAX 16
#define ROUNDS_DEFAULT 5000UL
#define ROUNDS_MIN 1000UL
#define ROUNDS_MAX 999999999UL

static const char itoa64[] =
  "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

static char *b64_from_24bit(char *o, unsigned b2, unsigned b1, unsigned b0, int n)
{
  unsigned long w = ((unsigned long)b2 << 16) | ((unsigned long)b1 << 8) | b0;
  while (n-- > 0) { *o++ = itoa64[w & 0x3f]; w >>= 6; }
  return o;
}

/* The byte order the spec's final encoding uses: groups of three digest bytes
   (b2, b1, b0), then the tail. */
static const unsigned char perm256[10][3] = {
  {0,10,20},{21,1,11},{12,22,2},{3,13,23},{24,4,14},
  {15,25,5},{6,16,26},{27,7,17},{18,28,8},{9,19,29} };
static const unsigned char perm512[21][3] = {
  {0,21,42},{22,43,1},{44,2,23},{3,24,45},{25,46,4},{47,5,26},{6,27,48},
  {28,49,7},{50,8,29},{9,30,51},{31,52,10},{53,11,32},{12,33,54},{34,55,13},
  {56,14,35},{15,36,57},{37,58,16},{59,17,38},{18,39,60},{40,61,19},{62,20,41} };

/* "$6$rounds=" + 9 digits + "$" + 16 salt + "$" + 86 hash + NUL, rounded up. */
static char crypt_result[128];

static char *sha_crypt(const char *key, const char *setting, int is512, char *out)
{
  const char *prefix = is512 ? "$6$" : "$5$";
  const int hl = is512 ? 64 : 32;
  unsigned char a[64], b[64], dp[64], ds[64];
  unsigned char *p_bytes = 0, *s_bytes = 0;
  const char *salt = setting + 3;
  size_t keylen = strlen(key), saltlen, cnt;
  unsigned long rounds = ROUNDS_DEFAULT, r;
  int rounds_custom = 0;
  hctx c, alt;
  char *o;
  int i;

  if (strncmp(salt, "rounds=", 7) == 0) {
    char *end;
    unsigned long v = strtoul(salt + 7, &end, 10);
    if (*end == '$') {
      salt = end + 1;
      rounds_custom = 1;
      rounds = v < ROUNDS_MIN ? ROUNDS_MIN : v > ROUNDS_MAX ? ROUNDS_MAX : v;
    }
  }
  saltlen = strcspn(salt, "$");
  if (saltlen > SALT_MAX) saltlen = SALT_MAX;

  /* B = H(key salt key) */
  h_init(&alt, is512);
  h_update(&alt, key, keylen);
  h_update(&alt, salt, saltlen);
  h_update(&alt, key, keylen);
  h_final(&alt, b);

  /* A = H(key salt B-stretched-to-keylen, then B or key per bit of keylen) */
  h_init(&c, is512);
  h_update(&c, key, keylen);
  h_update(&c, salt, saltlen);
  for (cnt = keylen; cnt > (size_t)hl; cnt -= hl) h_update(&c, b, hl);
  h_update(&c, b, cnt);
  for (cnt = keylen; cnt > 0; cnt >>= 1) {
    if (cnt & 1) h_update(&c, b, hl);
    else h_update(&c, key, keylen);
  }
  h_final(&c, a);

  /* P: H(key repeated keylen times), stretched to keylen bytes */
  h_init(&alt, is512);
  for (cnt = 0; cnt < keylen; cnt++) h_update(&alt, key, keylen);
  h_final(&alt, dp);
  p_bytes = (unsigned char *)malloc(keylen ? keylen : 1);
  if (!p_bytes) { errno = ENOMEM; return 0; }
  for (cnt = 0; cnt + hl <= keylen; cnt += hl) memcpy(p_bytes + cnt, dp, hl);
  memcpy(p_bytes + cnt, dp, keylen - cnt);

  /* S: H(salt repeated 16 + A[0] times), stretched to saltlen bytes */
  h_init(&alt, is512);
  for (cnt = 0; cnt < 16u + a[0]; cnt++) h_update(&alt, salt, saltlen);
  h_final(&alt, ds);
  s_bytes = (unsigned char *)malloc(saltlen ? saltlen : 1);
  if (!s_bytes) { free(p_bytes); errno = ENOMEM; return 0; }
  memcpy(s_bytes, ds, saltlen);

  for (r = 0; r < rounds; r++) {
    h_init(&c, is512);
    if (r & 1) h_update(&c, p_bytes, keylen); else h_update(&c, a, hl);
    if (r % 3) h_update(&c, s_bytes, saltlen);
    if (r % 7) h_update(&c, p_bytes, keylen);
    if (r & 1) h_update(&c, a, hl); else h_update(&c, p_bytes, keylen);
    h_final(&c, a);
  }

  o = out;
  strcpy(o, prefix);
  o += 3;
  if (rounds_custom) {
    char digits[16];
    unsigned long v = rounds;
    int n = 0;
    strcpy(o, "rounds=");
    o += 7;
    do { digits[n++] = (char)('0' + v % 10); v /= 10; } while (v);
    while (n > 0) *o++ = digits[--n];
    *o++ = '$';
  }
  memcpy(o, salt, saltlen);
  o += saltlen;
  *o++ = '$';
  if (is512) {
    for (i = 0; i < 21; i++)
      o = b64_from_24bit(o, a[perm512[i][0]], a[perm512[i][1]], a[perm512[i][2]], 4);
    o = b64_from_24bit(o, 0, 0, a[63], 2);
  } else {
    for (i = 0; i < 10; i++)
      o = b64_from_24bit(o, a[perm256[i][0]], a[perm256[i][1]], a[perm256[i][2]], 4);
    o = b64_from_24bit(o, 0, a[31], a[30], 3);
  }
  *o = '\0';

  /* The intermediate values are password-derived: wipe them. */
  memset(p_bytes, 0, keylen);
  memset(s_bytes, 0, saltlen);
  free(p_bytes);
  free(s_bytes);
  memset(a, 0, sizeof a); memset(b, 0, sizeof b);
  memset(dp, 0, sizeof dp); memset(ds, 0, sizeof ds);
  memset(&c, 0, sizeof c); memset(&alt, 0, sizeof alt);
  return out;
}

/* ---- MD5 (RFC 1321) and MD5-crypt ("$1$") ---------------------------------
   MD5-crypt is Poul-Henning Kamp's FreeBSD scheme, which glibc and libxcrypt
   implement as "$1$": the salt is up to 8 characters, ended by '$' or the end
   of the setting, and 1000 rounds mix the key, the salt and the previous
   digest. Old /etc/shadow files and `mkpasswd -m md5` still produce it.
   Checked against libxcrypt (test/c_crypt_md5.c). */
typedef struct { uint32_t s[4]; uint64_t len; unsigned char buf[64]; } md5_ctx;

static uint32_t md5_rol(uint32_t x, int c) { return (x << c) | (x >> (32 - c)); }

static void md5_block(md5_ctx *c, const unsigned char *p)
{
  static const uint32_t K[64] = {
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
  };
  static const unsigned char R[64] = {
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
  };
  uint32_t m[16], a = c->s[0], b = c->s[1], cc = c->s[2], d = c->s[3], f, t;
  int i, g;
  for (i = 0; i < 16; i++)
    m[i] = (uint32_t)p[4 * i] | ((uint32_t)p[4 * i + 1] << 8) |
           ((uint32_t)p[4 * i + 2] << 16) | ((uint32_t)p[4 * i + 3] << 24);
  for (i = 0; i < 64; i++) {
    if (i < 16) { f = (b & cc) | (~b & d); g = i; }
    else if (i < 32) { f = (d & b) | (~d & cc); g = (5 * i + 1) & 15; }
    else if (i < 48) { f = b ^ cc ^ d; g = (3 * i + 5) & 15; }
    else { f = cc ^ (b | ~d); g = (7 * i) & 15; }
    t = d; d = cc; cc = b;
    b = b + md5_rol(a + f + K[i] + m[g], R[i]);
    a = t;
  }
  c->s[0] += a; c->s[1] += b; c->s[2] += cc; c->s[3] += d;
}

static void md5_init(md5_ctx *c)
{
  c->s[0] = 0x67452301; c->s[1] = 0xefcdab89; c->s[2] = 0x98badcfe; c->s[3] = 0x10325476;
  c->len = 0;
}

static void md5_update(md5_ctx *c, const void *data, size_t n)
{
  const unsigned char *p = (const unsigned char *)data;
  size_t have = (size_t)(c->len & 63);
  c->len += n;
  while (n > 0) {
    size_t k = 64 - have < n ? 64 - have : n;
    memcpy(c->buf + have, p, k);
    have += k; p += k; n -= k;
    if (have == 64) { md5_block(c, c->buf); have = 0; }
  }
}

static void md5_final(md5_ctx *c, unsigned char out[16])
{
  uint64_t bits = c->len * 8;
  unsigned char pad[72];
  size_t have = (size_t)(c->len & 63), n = (have < 56 ? 56 : 120) - have;
  int i;
  memset(pad, 0, sizeof pad);
  pad[0] = 0x80;
  for (i = 0; i < 8; i++) pad[n + i] = (unsigned char)(bits >> (8 * i));
  md5_update(c, pad, n + 8);
  for (i = 0; i < 4; i++) {
    out[4 * i] = (unsigned char)c->s[i];
    out[4 * i + 1] = (unsigned char)(c->s[i] >> 8);
    out[4 * i + 2] = (unsigned char)(c->s[i] >> 16);
    out[4 * i + 3] = (unsigned char)(c->s[i] >> 24);
  }
}

/* "$1$" + 8 salt + "$" + 22 hash + NUL */
static char *md5_crypt(const char *key, const char *setting, char *out)
{
  const char *salt = setting + 3;
  size_t klen = strlen(key), slen = 0, pl;
  unsigned char f[16];
  md5_ctx c, alt;
  char *o;
  int i;
  while (slen < 8 && salt[slen] && salt[slen] != '$') slen++;

  md5_init(&alt);
  md5_update(&alt, key, klen); md5_update(&alt, salt, slen); md5_update(&alt, key, klen);
  md5_final(&alt, f);

  md5_init(&c);
  md5_update(&c, key, klen); md5_update(&c, "$1$", 3); md5_update(&c, salt, slen);
  for (pl = klen; pl > 0; pl -= pl > 16 ? 16 : pl) md5_update(&c, f, pl > 16 ? 16 : pl);
  memset(f, 0, sizeof f);
  for (i = (int)klen; i; i >>= 1) md5_update(&c, (i & 1) ? (const void *)f : (const void *)key, 1);
  md5_final(&c, f);

  for (i = 0; i < 1000; i++) {
    md5_init(&c);
    if (i & 1) md5_update(&c, key, klen); else md5_update(&c, f, 16);
    if (i % 3) md5_update(&c, salt, slen);
    if (i % 7) md5_update(&c, key, klen);
    if (i & 1) md5_update(&c, f, 16); else md5_update(&c, key, klen);
    md5_final(&c, f);
  }

  memcpy(out, "$1$", 3);
  memcpy(out + 3, salt, slen);
  o = out + 3 + slen;
  *o++ = '$';
  o = b64_from_24bit(o, f[0], f[6], f[12], 4);
  o = b64_from_24bit(o, f[1], f[7], f[13], 4);
  o = b64_from_24bit(o, f[2], f[8], f[14], 4);
  o = b64_from_24bit(o, f[3], f[9], f[15], 4);
  o = b64_from_24bit(o, f[4], f[10], f[5], 4);
  o = b64_from_24bit(o, 0, 0, f[11], 2);
  *o = 0;
  memset(f, 0, sizeof f); memset(&c, 0, sizeof c); memset(&alt, 0, sizeof alt);
  return out;
}

char *crypt(const char *key, const char *setting)
{
  if (!key || !setting) { errno = EINVAL; return 0; }
  if (strncmp(setting, "$6$", 3) == 0) return sha_crypt(key, setting, 1, crypt_result);
  if (strncmp(setting, "$5$", 3) == 0) return sha_crypt(key, setting, 0, crypt_result);
  if (strncmp(setting, "$1$", 3) == 0) return md5_crypt(key, setting, crypt_result);
  errno = EINVAL;
  return 0;
}

/* The reentrant form (libxcrypt's API, struct crypt_data in <crypt.h>): the
   result lands in data->output, so two threads with two data areas do not
   share crypt()'s static buffer. test/test_c_crypt.pas. */
char *crypt_r(const char *key, const char *setting, struct crypt_data *data)
{
  if (!key || !setting || !data) { errno = EINVAL; return 0; }
  if (strncmp(setting, "$6$", 3) == 0) return sha_crypt(key, setting, 1, data->output);
  if (strncmp(setting, "$5$", 3) == 0) return sha_crypt(key, setting, 0, data->output);
  if (strncmp(setting, "$1$", 3) == 0) return md5_crypt(key, setting, data->output);
  errno = EINVAL;
  return 0;
}
