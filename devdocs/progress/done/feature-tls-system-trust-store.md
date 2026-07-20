---
prio: 45  # auto
---

# Chain-to-system-trust-store (/etc/ssl/certs) for the TLS client

- **Type:** feature (library) — TLS trust anchoring
- **Status:** done
- **Track:** B (`lib/rtl`)
- **Opened:** 2026-06-25
- **Parent / depends-on:** [[feature-tls13-from-scratch]] (M5 X.509 + M6 handshake,
  both done). Consumes `lib/rtl/x509.pas` (`X509Parse`, `X509VerifyChain`,
  `X509ValidAt`, `X509HostMatch`).

## Why

The from-scratch TLS 1.3 client now verifies the server cert **chain** in the
handshake — but only against a CA explicitly handed in
(`test/devtest_tls13_handshake.pas`). A real client must anchor trust in the
**system trust store** (`/etc/ssl/certs`): build the chain leaf→…→root and accept
only when the root is one of the system-trusted CAs. This is the last piece of
M5 ("trust store") and the difference between "verifies a CA I passed" and
"verifies a real public server".

## Scope

1. **Load the trust store.** Read the system CA bundle into a set of trusted
   roots. On Debian/Ubuntu the anchors are:
   - `/etc/ssl/certs/ca-certificates.crt` — one concatenated PEM file (preferred,
     a single read), **or**
   - the `/etc/ssl/certs/*.pem` directory of individual PEM CAs (+ the
     `<hash>.0` symlinks). Support at least the concatenated file; the directory
     form is optional.
   PEM = base64 between `-----BEGIN CERTIFICATE-----`/`-----END CERTIFICATE-----`;
   decode each block to DER and `X509Parse` it. Index roots by **Subject** (raw
   DN bytes) for issuer lookup. File reads via `PalOpen`/`PalRead` (see the
   long-argv landmine in [[track-b-workarounds]] — bulk data comes from files,
   not argv).

2. **Build + validate the chain.** Given the server's `certificate_list` (leaf +
   any intermediates it sent), chain each cert to its issuer (an intermediate in
   the server's list, then a root in the store) using `X509VerifyChain` per link
   (name link + signature + validity), terminating at a trusted root. Verify the
   leaf hostname against the SNI (`X509HostMatch`). A trusted self-signed root
   that *is* the leaf (direct) also validates.

3. **API.** Something like:
   ```pascal
   type TTrustStore = …;                 { the parsed roots, keyed by Subject }
   function LoadSystemTrust: TTrustStore; { reads /etc/ssl/certs }
   function VerifyServerChain(const store: TTrustStore;
                              const certList: array of AnsiString;  { DER leaf+intermediates }
                              const nowStr, host: AnsiString): Boolean;
   ```
   Wire `VerifyServerChain` into the handshake in place of the hand-passed CA.

4. **Test.** Hermetic: build a small root→intermediate→leaf chain with `openssl`
   in a devtest, point the loader at a temp "store" file containing the test
   root, and assert leaf validates / a tampered or untrusted chain is rejected /
   an expired cert is rejected / a hostname mismatch is rejected. (Hitting a real
   public host is a non-hermetic devtest at most — keep the gate offline.) Also a
   PEM-decoder unit test (decode the concatenated bundle → N certs parse).

## Notes / non-goals

- Path-length / basicConstraints CA flag and keyUsage checks are a follow-on
  hardening step; first cut may skip them (document the gap).
- Revocation (CRL/OCSP) is out of scope.
- RSA-PSS and ECDSA `CertificateVerify`/chain-signature schemes: the M4 verifiers
  exist (RSA-PKCS1, ECDSA-P256, Ed25519); RSA-PSS is not yet implemented — note if
  a store CA needs it.

## Done when

- `LoadSystemTrust` parses `/etc/ssl/certs/ca-certificates.crt` into trusted
  roots; `VerifyServerChain` validates a leaf+intermediates against them
  (name+signature+validity to a trusted root) plus hostname.
- Hermetic devtest: a temp root→leaf chain validates; untrusted / expired /
  wrong-host / tampered chains are rejected.
- Wired into `test/devtest_tls13_handshake.pas` (replace the hand-passed CA with
  the system store, or a `--store <file>` for the test root).

## Log
- 2026-07-20 — Landed (Track B). `lib/rtl/truststore.pas` + `make truststore-devtest`.
  Loads `/etc/ssl/certs/ca-certificates.crt` (then the Fedora/RHEL and Alpine/BSD
  bundle paths); verified against the real host store — 121 anchors parse. Chain
  walk accepts leaf+intermediate to a trusted root, tolerates an out-of-order
  certificate_list (real servers send these wrong), and rejects hostname
  mismatch, missing intermediate, expired, tampered signature, untrusted root,
  and an empty store.

  **Fails closed by construction:** an unreadable bundle yields an empty store
  and an empty store validates nothing. This matters more than it looks — the
  loader was silently returning 0 anchors during development (see the bug below)
  and the only reason that was safe is that "no roots" refuses everything. Code
  written the other way round would have failed open.

  **Deferred, and still open:** basicConstraints CA flag, keyUsage, and
  path-length are NOT enforced, so a leaf a trusted CA signed could itself act
  as an intermediate. Documented at the top of the unit. That is the next
  hardening slice and should be filed as its own ticket before this is relied on
  for anything real.

  Not done here: wiring `VerifyServerChain` into
  `test/devtest_tls13_handshake.pas` in place of the hand-passed CA. The unit
  and its devtest stand alone; the handshake swap is a separate, small slice.

  Found on the way, filed rather than absorbed:
  [[bug-open-array-param-length-high-zero]] — `Length()`/`High()` on an
  open-array parameter return 0/-1, so `PemSplit` silently found no certificates
  in a 121-cert bundle. `PemSplit` takes an explicit `cap` until that is fixed.

- 2026-07-20 — resolved, commit HEAD.
