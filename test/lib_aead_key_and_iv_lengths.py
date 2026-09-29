# Oracle for test/lib_aead_key_and_iv_lengths.pas: prints the .expected with
# Python's cryptography package (checked with 46.0.5). The gate does not run
# this; regenerate with
#   python3 test/lib_aead_key_and_iv_lengths.py > test/lib_aead_key_and_iv_lengths.expected
# A "refused" line is printed only when cryptography also raises for that input.
from cryptography.hazmat.primitives.ciphers.aead import AESGCM, ChaCha20Poly1305
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.exceptions import InvalidTag


def seq(n, mul, add):
    return bytes((i * mul + add) & 255 for i in range(n))


def key(n):
    return seq(n, 37, n)


def iv(n):
    return seq(n, 11, 3 + n)


PT = seq(37, 5, 1)
AAD = seq(20, 3, 2)


def refused(label, fn):
    try:
        fn()
    except ValueError:
        print("refused", label)
        return
    raise SystemExit("cryptography accepted " + label)


# AES single block, FIPS-197 appendix C.1-C.3 inputs
blk = bytes.fromhex("00112233445566778899aabbccddeeff")
for n in (16, 24, 32):
    e = Cipher(algorithms.AES(bytes(range(n))), modes.ECB()).encryptor()
    print("aes%d-block" % (n * 8), (e.update(blk) + e.finalize()).hex())

for kn in (16, 24, 32):
    for ivn in (12, 8, 16, 60):
        sealed = AESGCM(key(kn)).encrypt(iv(ivn), PT, AAD)
        label = "aes%d-gcm-iv%d" % (kn * 8, ivn)
        print("seal", label, sealed.hex())
        print("open", label, AESGCM(key(kn)).decrypt(iv(ivn), sealed, AAD).hex())
        bad = bytes([sealed[0] ^ 1]) + sealed[1:]
        try:
            AESGCM(key(kn)).decrypt(iv(ivn), bad, AAD)
            print("open", label, "tampered opened")
        except InvalidTag:
            print("open", label, "tampered False")

for kn in (0, 15, 17, 31, 33, 64):
    refused("aes-gcm-key%d" % kn, lambda: AESGCM(key(kn)))
refused("aes-gcm-iv0", lambda: AESGCM(key(32)).encrypt(b"", PT, AAD))

sealed = ChaCha20Poly1305(key(32)).encrypt(iv(12), PT, AAD)
print("seal chacha20poly1305", sealed.hex())
print("open chacha20poly1305", ChaCha20Poly1305(key(32)).decrypt(iv(12), sealed, AAD).hex())
for kn in (0, 16, 31, 33):
    refused("chacha20poly1305-key%d" % kn, lambda: ChaCha20Poly1305(key(kn)))
for nn in (8, 16):
    refused("chacha20poly1305-nonce%d" % nn,
            lambda: ChaCha20Poly1305(key(32)).encrypt(iv(nn), PT, AAD))
