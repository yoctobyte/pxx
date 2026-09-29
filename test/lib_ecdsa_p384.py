# Emits the vector table of test/lib_ecdsa_p384.pas with Python's cryptography.
# Signatures are randomised, so a rerun gives different (equally valid) rows.
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature, Prehashed
from cryptography.hazmat.primitives import hashes
rows = []
msgs = [b"", b"abc", b"x" * 200, bytes(range(256))]
for i, m in enumerate(msgs):
    k = ec.generate_private_key(ec.SECP384R1())
    pn = k.public_key().public_numbers()
    qxy = pn.x.to_bytes(48, "big") + pn.y.to_bytes(48, "big")
    h = hashes.SHA384() if i % 2 == 0 else hashes.SHA256()
    r, s = decode_dss_signature(k.sign(m, ec.ECDSA(h)))
    rows.append((qxy.hex(), m.hex(), (r.to_bytes(48, "big") + s.to_bytes(48, "big")).hex(), h.name))
for q, m, sg, hn in rows:
    print("  V(%r, %r, %r, %r);" % (q, m, sg, hn))
