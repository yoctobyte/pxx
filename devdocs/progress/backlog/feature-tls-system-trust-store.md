# Chain-to-system-trust-store (/etc/ssl/certs) for the TLS client

- **Type:** feature (library) — TLS trust anchoring
- **Status:** backlog
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
