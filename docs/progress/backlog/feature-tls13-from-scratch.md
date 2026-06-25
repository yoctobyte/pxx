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
1. **Hashes:** ~~SHA-256~~ + ~~HMAC~~ + ~~HKDF-Extract/Expand~~ **landed
   2026-06-25** (`lib/rtl/sha256.pas`, RFC-vector smoke `test/lib_sha256` in
   lib-test). SHA-384 still needed for the 384 ciphersuite.
2. **AEAD:** ~~ChaCha20 + Poly1305~~ + ~~AES-128 block + GCM (GHASH)~~ **done**
   (`lib/rtl/chacha20poly1305.pas` RFC 8439, `lib/rtl/aesgcm.pas` FIPS-197 + GCM
   TC1–4).
3. ~~**X25519** (Curve25519 ECDH)~~ **done** (`lib/rtl/x25519.pas`, RFC 7748;
   16-limb radix-2^16 field, not bignum).
4. **Signature verify:** ~~RSA (PKCS#1 v1.5)~~ + ~~ECDSA-P256~~ + ~~Ed25519~~
   **done** (`rsa.pas`, `ecdsa_p256.pas`, `ed25519.pas`). RSA-PSS still to add if a
   server needs it.
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

- M1 hashes + HMAC + HKDF (RFC test vectors). **DONE for SHA-256 (2026-06-25)** —
  `lib/rtl/sha256.pas`: SHA-256 (FIPS 180-4) + HMAC-SHA256 (RFC 2104) +
  HKDF-Extract/Expand (RFC 5869), all verified against published vectors in
  `test/lib_sha256` (12 checks, gated in lib-test). Library-free, pure integer —
  the first concrete step of the from-scratch / kTLS path. SHA-384 still to add.
- M2 AES-128-GCM + ChaCha20-Poly1305 (RFC 8439 / NIST vectors). **DONE
  (2026-06-25).** ChaCha20-Poly1305: `lib/rtl/chacha20poly1305.pas` (ChaCha20 ARX +
  Poly1305 native limbs), RFC 8439 §2.5.2/§2.8.2, `test/lib_chacha20poly1305` (7
  checks). AES-128-GCM: `lib/rtl/aesgcm.pas` (AES-128 + GHASH GF(2^128) + GCM),
  FIPS-197 AES + GCM-spec TC1–4, `test/lib_aesgcm` (8 checks, gated `aes-gcm`).
  Both library-free. Surfaced Track A bugs: [[bug-managed-record-result-self-arg]],
  [[bug-fixed-array-assignment-no-copy]], [[bug-string-literal-concat-compare-segfault]].
- M3 X25519 (RFC 7748 vectors). **DONE (2026-06-25)** —
  `lib/rtl/x25519.pas`: a TweetNaCl `crypto_scalarmult` port (16-limb radix-2^16
  field, Int64), `X25519` + `X25519Base`, verified against RFC 7748 §5.2 + §6.1
  (Diffie-Hellman incl. ECDH agreement) in `test/lib_x25519` (6 checks, gated as
  `x25519`). Library-free. Surfaced Track A bug
  [[bug-not-on-int64-is-boolean]] (`not` on an Int64 expression miscompiles;
  worked around with `-x-1`).
- M4 signature verify: RSA, ECDSA-P256, Ed25519 (RFC 8032 vectors). **DONE
  (2026-06-25).** `lib/rtl/rsa.pas` (PKCS#1 v1.5 SHA-256, over bignum),
  `lib/rtl/ed25519.pas` (RFC 8032, TweetNaCl port over `lib/rtl/sha512.pas`),
  `lib/rtl/ecdsa_p256.pas` (secp256r1 SHA-256, Jacobian over bignum). All
  verify-only, library-free, vector-checked (`lib_rsa` 3, `lib_ed25519` 3,
  `lib_ecdsa_p256` 2; gated `rsa-verify`/`ed25519-verify`/`ecdsa-p256-verify`).
  Surfaced Track A bugs [[bug-not-on-int64-is-boolean]],
  [[bug-aggregate-member-array-as-var-param]].
- M5 ASN.1/X.509 parse + chain validation + trust store. **In progress
  (2026-06-25):** `lib/rtl/x509.pas` — a DER (TLV) parser + X.509 field extraction
  (tbsCertificate, signatureAlgorithm, signatureValue, SubjectPublicKeyInfo) +
  `X509VerifySig` wiring the cert signature to the M4 verifiers
  (RSA/ECDSA-P256/Ed25519 by OID). `test/lib_x509`: three self-signed certs
  (one per algorithm) parse and their self-signatures verify (5 checks, gated
  `x509`). **Chain validation added 2026-06-25:** `X509VerifyChain` (issuer-name
  link + signature + validity + hostname), `X509ValidAt`, `X509HostMatch` (SAN
  dNSName, case-insensitive, single `*.` wildcard). `lib_x509` now also validates
  a real CA→leaf chain (issuer link, SAN exact/wildcard/reject, expired-reject,
  badhost-reject, chain-ok; 12 checks). **Remaining:** loading the system trust
  store (`/etc/ssl/certs`) for the trust anchor — wired in at M6.
- M6 **key schedule done (2026-06-25):** `lib/rtl/tls13_keys.pas` —
  HKDF-Expand-Label, Derive-Secret, the Early/Handshake/Master secret chain, and
  traffic key/iv derivation (RFC 8446 §7.1), verified byte-for-byte against the
  RFC 8448 worked example (`test/lib_tls13_keys`, 5 checks, gated `tls13-keysched`).
  **Record layer done** (`lib/rtl/tls13_record.pas`, `tls13-record`): TLSCiphertext
  framing + per-record nonce (`iv XOR seq`) + AEAD wrap/unwrap over both
  ciphersuites, roundtrip + tamper-reject. **Handshake message layer done**
  (`lib/rtl/tls13_hs.pas`, `tls13-hs`): ClientHello builder (X25519 key_share,
  the two SHA-256 suites, supported_versions/groups/sig_algs/SNI), ServerHello
  parser (cipher + server key_share), HS framing + transcript hash. **Remaining
  M6:** the handshake state machine that drives these against a live server
  (decrypt the server flight, verify CertificateVerify + Finished, send client
  Finished, switch to app keys) → a real `https://` GET.
- M6 TLS 1.3 handshake state machine → a real `https://` GET (Pascal record
  layer); verify against a public host.
- M7 (optional) kTLS offload for app-data throughput.

## Done when

`HttpGet('https://host/...')` (sync + async) completes a real TLS 1.3 handshake,
validates the cert chain to the system trust store, and transfers application
data — Pascal record layer at minimum, kTLS offload optional. Every primitive
smoke-tested against published vectors. Unit head + docs state the
not-for-hostile-production caveat and point at OpenSSL-dlopen for that.
