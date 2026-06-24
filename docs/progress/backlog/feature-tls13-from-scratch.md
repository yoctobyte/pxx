# TLS 1.3 from scratch — syscall-only (Pascal handshake + kTLS bulk)

- **Type:** feature (library / crypto / protocol) — flagship
- **Status:** backlog — **DEFERRED**, start alongside BSD support (not now)
- **Owner:** —
- **Opened:** 2026-06-24
- **Relation:** the **native backend** behind [[feature-tls-provider-abstraction]]
  (the common TLS seam); the OpenSSL backend is the co-equal default. The `https`
  half of [[feature-own-net-http-lib]].

## Scope decision (2026-06-24)

**Target: POSIX/Linux only.** This from-scratch stack is *our* TLS for the
desktop/server targets. **ESP32 is out of scope** — ESP-IDF already ships
mbedTLS + HW crypto; link those there, don't run our software stack. **BSD/kTLS
(FreeBSD) is deferred to when BSD support proper begins.** So: don't pre-build
multi-platform crypto seams now — keep the primitives portable Pascal targeting
Linux/POSIX; the per-platform notes below are forward-looking context, not work
to do up front. Whole feature is deferred until we pick up BSD anyway.

## Why / stance

TLS is **not** a kernel feature. Linux `kTLS` only does the **record layer**
(bulk AEAD of application data) once you hand it negotiated keys — it does *not*
do the handshake. The handshake (the actual difficulty) is pure userspace
computation over our socket syscalls: key exchange, cert-chain signature verify,
key schedule. So a syscall-only TLS = **we write the TLS stack in Pascal**; the
kernel just moves bytes (and, via kTLS, can do the bulk symmetric crypto so our
Pascal AEAD only ever touches the low-volume handshake — no throughput concern).

This is squarely our lane and a superb real-world compiler stress test: big-int
math, bit-twiddling, AEAD state machines, ASN.1 parsing, a multi-state protocol —
"platonic cryptographic code."

**Security stance (explicit):** this is educational / platonic / a compiler
exercise. It will NOT be constant-time-audited or hardened against timing/padding
side channels initially. **For production / hostile networks, recommend the
OpenSSL-dlopen path.** Document this loudly at the unit head and in any API doc.
That neatly sidesteps the real risk (subtle crypto bugs) without giving up the
build.

## Architecture

1. **Handshake in Pascal** (once per connection, low volume — speed irrelevant):
   ClientHello → ServerHello, derive shared secret, key schedule, decrypt+verify
   the (encrypted) EncryptedExtensions / Certificate / CertVerify / Finished,
   send our Finished. Our AEAD runs here on a few KB only.
2. **Bulk record layer**: two options, build (a) first.
   - (a) **Pascal record layer** — AEAD each app-data record in Pascal. Works
     everywhere (other arches too), simplest, no kTLS dependency. Throughput is
     Pascal-AES-bound but correct.
   - (b) **kTLS offload** — after the handshake, install the app traffic keys via
     `setsockopt(TCP_ULP,"tls")` + `setsockopt(SOL_TLS, TLS_TX/TLS_RX,
     crypto_info)`; the kernel then encrypts/decrypts bulk data at line rate and
     `read`/`write` look plaintext. Needs `PalSetSockOpt` + the `SOL_TLS`
     crypto-info structs. The perf path; **per-platform behind PAL** (Linux and
     FreeBSD have kTLS with *different* APIs; OpenBSD/NetBSD/macOS/ESP do not —
     see the platform table below). Never the baseline.

## Platform abstraction (get the seam at the right level)

The protocol is portable; the crypto and the offloads are not. Three layers:

- **TLS protocol** (handshake state machine, key schedule, transcript hash,
  ASN.1/X.509, alerts) — **pure portable Pascal, identical on every target.**
- **Crypto primitives** (AES block, SHA-2 compression, bignum modexp, AEAD) —
  behind a **thin PAL-swappable seam** so a target can substitute hardware:
  software Pascal on Linux/BSD; **ESP32 has HW AES/SHA/RSA accelerators** (MMIO
  via the PAL ESP backend, and ESP-IDF mbedTLS) — don't run software AES there.
  Every implementation is held to the same RFC/NIST test vectors.
- **Record layer** — pluggable. **Portable Pascal AEAD is the baseline (works on
  EVERY target).** kTLS is an *optional per-platform offload*, not the baseline.

### kTLS availability (offload only — the handshake is always ours)

| OS | kTLS | API |
|----|------|-----|
| Linux | yes (TX 4.13+, RX 4.17+) | `setsockopt(TCP_ULP,"tls")` + `SOL_TLS` crypto_info |
| FreeBSD | yes (pioneered) | `setsockopt(TCP_TXTLS_ENABLE,...)` — **different** API/structs |
| OpenBSD / NetBSD / macOS | no | (userspace TLS) |
| ESP32 | no | FreeRTOS/lwIP; use HW accel + Pascal record layer |

So kTLS glue is **per-platform behind PAL** (separate Linux and FreeBSD backends),
absent elsewhere — which is exactly why the Pascal record layer must be the
baseline. The from-scratch TLS is therefore never wasted: the SW path always
works; kTLS/HW-accel plug in where present.

## Target ciphersuite (TLS 1.3 only — far simpler than 1.2)

Mandatory + modern, minimal set:
- **Cipher:** `TLS_AES_128_GCM_SHA256` (mandatory) + `TLS_CHACHA20_POLY1305_SHA256`.
- **Key exchange:** `X25519` (mandatory-to-offer); P-256 optional later.
- **Cert verify (server):** ECDSA-P256, Ed25519, RSA-PKCS#1 v1.5 + RSA-PSS.

No 1.2, no RC4/CBC/renegotiation/compression. Client-side only first (we are an
HTTP client); server-side later if wanted.

## Building blocks

**Have:** `lib/rtl/bignum.pas` — `BigModPow` (RSA verify), `BigDivMod`/`BigMul`/…
(EC field arithmetic). Big head start.

**Need (each its own unit + smoke):**
1. **Hashes:** SHA-256, SHA-384 (`lib/rtl/hashing` has only CRC/Adler today),
   HMAC, HKDF-Extract/Expand (the 1.3 key schedule).
2. **AEAD:** AES-128 block + GCM (GHASH), and ChaCha20 + Poly1305.
3. **X25519** (Curve25519 ECDH) — field arithmetic mod 2^255-19 (can sit on
   bignum or a dedicated 64-bit-limb field).
4. **Signature verify:** RSA (PKCS#1 v1.5 + PSS) over bignum; ECDSA-P256;
   Ed25519.
5. **ASN.1/DER** parser + **X.509** cert parse; chain build + validation
   (validity dates, key usage, name match); **trust store** from `/etc/ssl/certs`
   (file syscalls — fine).
6. **TLS 1.3 record + handshake state machine**; transcript hash; key schedule;
   alerts.
7. **Crypto-primitive PAL seam** so HW accel can substitute SW (ESP32 AES/SHA/RSA
   peripherals); + **kTLS** glue `PalSetSockOpt` per-platform (Linux `SOL_TLS`,
   FreeBSD `TCP_TXTLS_ENABLE`) — optional offload, absent on OpenBSD/NetBSD/macOS/ESP.
8. **Integration:** `https://` in `http` (its `isTls` branch is already stubbed
   to refuse); async path too.

## Milestones (suggested order — each smoke-tested against known test vectors)

- M1 hashes + HMAC + HKDF (RFC test vectors).
- M2 AES-128-GCM + ChaCha20-Poly1305 (RFC 8439 / NIST vectors).
- M3 X25519 (RFC 7748 vectors).
- M4 signature verify: RSA, ECDSA-P256, Ed25519 (RFC 8032 vectors).
- M5 ASN.1/X.509 parse + chain validation + trust store.
- M6 TLS 1.3 handshake state machine → a real `https://` GET (Pascal record
  layer); verify against a public host.
- M7 (optional) kTLS offload for app-data throughput.

## Done when

`HttpGet('https://host/...')` (sync + async) completes a real TLS 1.3 handshake,
validates the cert chain to the system trust store, and transfers application
data — Pascal record layer at minimum, kTLS offload optional. Every primitive
smoke-tested against published vectors. Unit head + docs state the
not-for-hostile-production caveat and point at OpenSSL-dlopen for that.
