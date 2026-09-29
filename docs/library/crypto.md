---
title: Cryptography
order: 51
---

# Cryptography: ciphers, keys, signatures and certificates

PXX has its own Pascal implementations of the algorithms TLS 1.3 uses. They
need no external library:

| Unit | What it does |
| --- | --- |
| [`aesgcm`](#encrypting-aesgcm-and-chacha20poly1305) | AES-GCM authenticated encryption (128, 192 and 256-bit keys) |
| [`chacha20poly1305`](#encrypting-aesgcm-and-chacha20poly1305) | ChaCha20-Poly1305 authenticated encryption, and ChaCha20 and Poly1305 on their own |
| [`x25519`](#agreeing-on-a-key-x25519) | X25519 key agreement |
| [`ecdsa_p256`](#signing-ecdsa_p256) | ECDSA on P-256 with SHA-256: key generation, signing and verifying |
| [`ed25519`](#checking-signatures-and-certificates-x509-rsa-ed25519) | Ed25519 verification |
| [`rsa`](#checking-signatures-and-certificates-x509-rsa-ed25519) | RSA verification, PKCS#1 v1.5 and PSS, with SHA-256 |
| [`x509`](#checking-signatures-and-certificates-x509-rsa-ed25519) | Reading a DER certificate, and checking its signature, dates and host name |

For HTTPS, use the OpenSSL backend described on the
[networking page](./networking.md#openssl-backend) (`tls_openssl`), not
these units.

**Read this before you use them.** These units give the right answers:
every example below prints what Python's `cryptography` package (46.0.5)
or OpenSSL (3.5.5) gives for the same input. What they do not claim is
resistance to side channels. Nobody has checked whether they take the same
time whatever the key is, and a test that compares output values cannot
find out. The source of `aesgcm`, `x25519`, `ecdsa_p256` and `rsa` says
so. They are fine for checking signatures
on files, for tests and for learning. Do not use them where an attacker can
time many operations with your key, for instance to protect a server.

**Up to and including pin v451, `aesgcm` and `chacha20poly1305` did not
check the length of a key or a nonce, and a wrong length was not an
error.** Measured with v451:

- `aesgcm` is AES-128 only. Given a 32-byte key meant for AES-256,
  `AesGcmSeal` uses the first 16 bytes and encrypts with AES-128.
  Anything that expects AES-256 cannot open the result, and the key is
  half as strong as you meant.
- An `iv` that is not 12 bytes gives output that is not AES-GCM.
- `Chacha20Poly1305Seal` takes a key that is not 32 bytes.

After v451 all three are fixed (see "Fixed after pin v451" below). With
v451 itself, pass exactly the lengths given below. For comparison, Python's
`cryptography` treats a 32-byte AES key as AES-256, gives real AES-GCM for
an `iv` of another length, and refuses a ChaCha20 key that is not 32 bytes.

All byte strings (keys, nonces, messages, signatures) are `AnsiString`, one
byte per character. After v451, `aesgcm` and `chacha20poly1305` refuse a
key or a nonce of a length they do not implement: they raise an exception
(`EAesGcm`, `EChaCha20Poly1305`) instead of encrypting. The other units do
not check lengths, so pass exactly the lengths given here.

Each example was built with pin v451 (compiler sha256 `d9b7226769cc`)
through `./pxx` on Linux x86-64 on 2026-09-29.

## Encrypting: aesgcm and chacha20poly1305

Both are AEAD ciphers: sealing encrypts the message and appends a 16-byte
tag, and opening checks the tag before it hands the message back. The tag
also covers extra data you pass unencrypted (`aad`, such as a header), so a
change to either is caught.

- `AesGcmSeal(key, iv, aad, plaintext)` and
  `AesGcmOpen(key, iv, aad, sealed, plaintext)`: a 16, 24 or 32-byte key
  (AES-128, AES-192 or AES-256) and an `iv` of any length but 0; 12 bytes
  is the usual length.
- `Chacha20Poly1305Seal(key, nonce, aad, plaintext)` and
  `Chacha20Poly1305Open(key, nonce, aad, sealed, plaintext)`: a 32-byte key
  and a 12-byte nonce.

Open returns `True` and sets `plaintext`, or returns `False` when the tag
does not match. A key or nonce of the wrong length raises, on Open as on
Seal. Never use the
same key and nonce twice for two different messages.

```pascal
program aead_demo;
uses aesgcm, chacha20poly1305;

function Hex(const s: AnsiString): AnsiString;
const d = '0123456789abcdef';
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(s) do
    Result := Result + d[Ord(s[i]) shr 4 + 1] + d[Ord(s[i]) and 15 + 1];
end;

function Repeated(c: Char; n: Integer): AnsiString;
var i: Integer;
begin
  Result := '';
  for i := 1 to n do Result := Result + c;
end;

var
  key16, key32, nonce, aad, msg, sealed, opened: AnsiString;
begin
  key16 := Repeated('k', 16);
  key32 := Repeated('K', 32);
  nonce := Repeated('n', 12);
  aad := 'header v1';
  msg := 'attack at dawn';

  sealed := AesGcmSeal(key16, nonce, aad, msg);
  writeln('AES-128-GCM:       ', Hex(sealed));
  if AesGcmOpen(key16, nonce, aad, sealed, opened) then writeln('  opened: ', opened);
  sealed[1] := Chr(Ord(sealed[1]) xor 1);
  writeln('  one bit flipped, opens: ', AesGcmOpen(key16, nonce, aad, sealed, opened));

  sealed := Chacha20Poly1305Seal(key32, nonce, aad, msg);
  writeln('ChaCha20-Poly1305: ', Hex(sealed));
  if Chacha20Poly1305Open(key32, nonce, aad, sealed, opened) then writeln('  opened: ', opened);
  writeln('  other header, opens: ', Chacha20Poly1305Open(key32, nonce, 'header v2', sealed, opened));
end.
```

```text
AES-128-GCM:       5a883ec7600ed9dec5cf73281f0c1061ac0923cbbfbe7ad7d8ef9cae0f75
  opened: attack at dawn
  one bit flipped, opens: FALSE
ChaCha20-Poly1305: 78739b8826d0b7d8f4e38feefd00f7099bb501e55cedbcfe3d439dce79e3
  opened: attack at dawn
  other header, opens: FALSE
```

Python's `AESGCM(b"k" * 16).encrypt(b"n" * 12, b"attack at dawn", b"header v1")`
and `ChaCha20Poly1305(b"K" * 32).encrypt(...)` give the same two hex
strings. An empty message gives the same bare tag as Python too.

Where it differs from Python's `cryptography`: an `iv` of 1 to 7 bytes, or
more than 128, is accepted here, as GCM allows; Python refuses it.

**Fixed after pin v451.** Up to and including v451, `aesgcm` was AES-128
only and used the first 16 bytes of a longer key without a word, so asking
for AES-256 gave AES-128. An `iv` that was not 12 bytes gave output that
was not GCM. `chacha20poly1305` took a key of any length and read past the
end of a short one. All three now match `cryptography`, refusals included
(`test/lib_aead_key_and_iv_lengths`, on x86-64 and on the ESP32-C3 and S3).

`ChaCha20(key, counter, nonce, data)` and `Poly1305(key, msg)` are the two
halves on their own (RFC 8439), and `AesEncryptBlock(key, block)` encrypts
one 16-byte block.

## Agreeing on a key: x25519

`X25519Base(priv)` turns a 32-byte private key into a 32-byte public key.
`X25519(myPriv, theirPub)` gives the secret two sides share: each side
combines its own private key with the other's public key, and both get
the same 32 bytes. Hash the result before you use it as a key, for
instance with HKDF from the [`hashing`](./more-units.md#hashing-sha256-and-sha512-checksums-and-digests) unit.

## Signing: ecdsa_p256

- `EcdsaP256GenKey(priv, pub)` makes a new key pair from the operating
  system's random numbers.
- `EcdsaP256PubFromPriv(priv)` gives the public key of a 32-byte private
  key.
- `EcdsaP256Sign(priv, msg)` signs the SHA-256 hash of `msg` with a fresh
  random nonce.
- `EcdsaP256Verify(pub, msg, sig)` checks a signature.

A public key is the 64 bytes X‖Y, and a signature is the 64 bytes r‖s. Both
are raw, without the DER wrapping OpenSSL uses. Signatures differ from run
to run, because the nonce is random. `EcdsaP256SignK` takes the nonce as an
argument instead, for tests: a nonce used twice, or one that leaks, gives
away the private key.

```pascal
program keys_demo;
uses x25519, ecdsa_p256;

function Hex(const s: AnsiString): AnsiString;
const d = '0123456789abcdef';
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(s) do
    Result := Result + d[Ord(s[i]) shr 4 + 1] + d[Ord(s[i]) and 15 + 1];
end;

function Bytes(first: Integer): AnsiString;   { 32 bytes: first, first+1, ... }
var i: Integer;
begin
  Result := '';
  for i := 0 to 31 do Result := Result + Chr((first + i) and 255);
end;

var
  alicePriv, bobPriv, alicePub, bobPub: AnsiString;
  priv, pub, sig: AnsiString;
begin
  { X25519: each side combines its own private key with the other's public key }
  alicePriv := Bytes(1);
  bobPriv := Bytes(101);
  alicePub := X25519Base(alicePriv);
  bobPub := X25519Base(bobPriv);
  writeln('alice public: ', Hex(alicePub));
  writeln('bob public:   ', Hex(bobPub));
  writeln('alice shares: ', Hex(X25519(alicePriv, bobPub)));
  writeln('bob shares:   ', Hex(X25519(bobPriv, alicePub)));

  { ECDSA P-256 with SHA-256 }
  priv := Bytes(7);
  pub := EcdsaP256PubFromPriv(priv);
  writeln('P-256 public: ', Hex(pub));
  sig := EcdsaP256Sign(priv, 'pay 10 to bob');
  writeln('signature length: ', Length(sig));
  writeln('verifies: ', EcdsaP256Verify(pub, 'pay 10 to bob', sig));
  writeln('other message verifies: ', EcdsaP256Verify(pub, 'pay 99 to bob', sig));
end.
```

```text
alice public: 07a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c
bob public:   5714769d116bf76436ae74bc793d2c30ad1903c59ac5273805c7e2698b410c36
alice shares: c9ea6a3f79a000b60b076d4afc990b272f3f0b5aaa3f0b8713c209273e363863
bob shares:   c9ea6a3f79a000b60b076d4afc990b272f3f0b5aaa3f0b8713c209273e363863
P-256 public: a28e38dcab1689b9c2f413141939416fea9dcc8e6ad76a8a13422bb4c11e6e32695b1a0d140033e7e0eaa5634fb5e6d36beedcbc67ad3eeb5a8b7f477a59bfda
signature length: 64
verifies: TRUE
other message verifies: FALSE
```

Python's `cryptography` gives the same two X25519 public keys, the same
shared secret and the same P-256 public key for these private keys. It
also accepts the signature PXX made (turned into DER with
`encode_dss_signature`) for the first message and refuses it for the
second.

## Checking signatures and certificates: x509, rsa, ed25519

`X509Parse(der)` reads a certificate in DER form into a `TCert` record
(`Ok` is `False` if it is malformed). With it:

- `X509VerifySig(cert, issuer)` checks the certificate's signature with
  the issuer's public key. Pass the certificate twice for a self-signed
  one. It understands RSA with SHA-256 (PKCS#1 v1.5 or PSS), ECDSA on
  P-256 with SHA-256, and Ed25519. Anything else gives `FALSE`, as if the
  signature were wrong: a certificate signed with P-384, or with RSA and
  SHA-384, both common among public certificate authorities, does not
  verify, where OpenSSL accepts it.
- `X509ValidAt(cert, 'YYYYMMDDHHMMSS')` checks the dates. The time is UTC,
  written as 14 digits.
- `X509HostMatch(cert, host)` checks the host name against the
  certificate's subjectAltName names, including one `*.` wildcard.
- `X509VerifyChain(leaf, issuer, now, host)` does all three for a leaf and
  its issuer. Whether the issuer is one you trust is up to you: the unit
  has no trust store.

The public key is in `cert.PubBits`. `RsaKey(cert.PubBits, n, e)` splits an
RSA key into modulus and exponent. `EcdsaRS(der, rs)` turns an ECDSA
signature in OpenSSL's DER form into the 64 bytes `EcdsaP256Verify` takes.
Ed25519 and RSA can only verify here; there is no signing and no key
generation.

This example checks three self-signed certificates made by OpenSSL, and a
file signed with their keys:

```sh
openssl req -x509 -newkey rsa:2048 -nodes -keyout rsa.key -outform DER -out rsa.der \
  -days 3650 -subj /CN=example.test -addext subjectAltName=DNS:example.test,DNS:*.example.test
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout ec.key \
  -outform DER -out ec.der -days 3650 -subj /CN=example.test -addext subjectAltName=DNS:example.test
openssl req -x509 -newkey ed25519 -nodes -keyout ed.key -outform DER -out ed.der \
  -days 3650 -subj /CN=example.test -addext subjectAltName=DNS:example.test
printf 'release 1.2.3' > msg.txt
openssl dgst -sha256 -sign rsa.key -out rsa-pkcs1.sig msg.txt
openssl dgst -sha256 -sign rsa.key -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:32 \
  -out rsa-pss.sig msg.txt
openssl dgst -sha256 -sign ec.key -out ec.sig msg.txt
openssl pkeyutl -sign -inkey ed.key -rawin -in msg.txt -out ed.sig
```

```pascal
program cert_demo;
uses x509, rsa, ecdsa_p256, ed25519;

function ReadAll(const path: string): AnsiString;
var f: File; n: LongInt;
begin
  Assign(f, path);
  Reset(f, 1);
  n := FileSize(f);
  SetLength(Result, n);
  if n > 0 then BlockRead(f, Result[1], n);
  Close(f);
end;

procedure Check(const name: string; const cert: TCert);
begin
  writeln(name, ': parsed ', cert.Ok,
          ', self-signature ', X509VerifySig(cert, cert),
          ', valid in 2027 ', X509ValidAt(cert, '20270101000000'),
          ', valid in 2040 ', X509ValidAt(cert, '20400101000000'));
  writeln('  example.test ', X509HostMatch(cert, 'example.test'),
          ', www.example.test ', X509HostMatch(cert, 'www.example.test'),
          ', example.org ', X509HostMatch(cert, 'example.org'));
end;

var
  rsaCert, ecCert, edCert: TCert;
  msg, n, e, rs: AnsiString;
begin
  rsaCert := X509Parse(ReadAll('rsa.der'));
  ecCert := X509Parse(ReadAll('ec.der'));
  edCert := X509Parse(ReadAll('ed.der'));
  Check('RSA', rsaCert);
  Check('P-256', ecCert);
  Check('Ed25519', edCert);

  { a message signed by OpenSSL, checked with each certificate's public key }
  msg := ReadAll('msg.txt');
  RsaKey(rsaCert.PubBits, n, e);
  writeln('RSA PKCS#1 v1.5: ', RsaVerifyPkcs1Sha256(n, e, msg, ReadAll('rsa-pkcs1.sig')));
  writeln('RSA PSS:         ', RsaVerifyPssSha256(n, e, msg, ReadAll('rsa-pss.sig')));
  EcdsaRS(ReadAll('ec.sig'), rs);
  writeln('ECDSA P-256:     ', EcdsaP256Verify(Copy(ecCert.PubBits, 2, 64), msg, rs));
  writeln('Ed25519:         ', Ed25519Verify(edCert.PubBits, msg, ReadAll('ed.sig')));
  writeln('Ed25519, altered message: ', Ed25519Verify(edCert.PubBits, msg + '.', ReadAll('ed.sig')));
end.
```

```text
RSA: parsed TRUE, self-signature TRUE, valid in 2027 TRUE, valid in 2040 FALSE
  example.test TRUE, www.example.test TRUE, example.org FALSE
P-256: parsed TRUE, self-signature TRUE, valid in 2027 TRUE, valid in 2040 FALSE
  example.test TRUE, www.example.test FALSE, example.org FALSE
Ed25519: parsed TRUE, self-signature TRUE, valid in 2027 TRUE, valid in 2040 FALSE
  example.test TRUE, www.example.test FALSE, example.org FALSE
RSA PKCS#1 v1.5: TRUE
RSA PSS:         TRUE
ECDSA P-256:     TRUE
Ed25519:         TRUE
Ed25519, altered message: FALSE
```

OpenSSL agrees on every line: `openssl verify` accepts each self-signed
certificate at 2027 and calls it expired at 2040, `openssl x509
-checkhost` gives the same host-name answers, and `openssl dgst -verify`
and `openssl pkeyutl -verify` accept the four signatures. With one byte of
the P-256 certificate changed, its self-signature check gives `FALSE`.

The P-256 key in `PubBits` starts with the byte `04`, which marks an
uncompressed point, so the example passes the 64 bytes after it.

**PSS needs a 32-byte salt.** `RsaVerifyPssSha256` accepts only the salt
length TLS 1.3 uses, the length of the hash. `openssl dgst` with
`-sigopt rsa_padding_mode:pss` and no salt length uses the longest salt that
fits, and PXX refuses that signature (`FALSE`), where OpenSSL accepts it.
Sign with `-sigopt rsa_pss_saltlen:32`, as above.
