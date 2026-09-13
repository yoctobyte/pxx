#!/usr/bin/env python3
"""CPython is the independent decoder for lib/rtl/zlib.pas's encoder.

Reads `<name> <level> <rawhex> <enchex>` lines from test/lib_zlib_emit and
asserts, for every one, that CPython's zlib.decompress reads our stream back to
the bytes that went in.

THE SIZE COMPARISON IS PRINTED AND NOT ASSERTED, deliberately. Deflate has no
single right answer -- which matches an encoder finds is latitude, and CPython
emits dynamic-Huffman blocks where we emit fixed -- so a size assertion would be
pinning another implementation's choices, which CLAUDE.md rules out. What is
assertable is that an independent decoder accepts what we produce.
"""
import sys, zlib

def main() -> int:
    rows, bad = 0, 0
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        name, level, rawhex, enchex = line.split()
        raw = b'' if rawhex == '-' else bytes.fromhex(rawhex)
        enc = b'' if enchex == '-' else bytes.fromhex(enchex)
        rows += 1
        try:
            got = zlib.decompress(enc)
        except Exception as exc:                       # noqa: BLE001
            print(f"FAIL {name} level={level}: CPython rejected our stream: {exc}")
            bad += 1
            continue
        if got != raw:
            # Say WHICH way it differs. "decoded 4 bytes, expected 4" is what
            # this printed first, which reads as a contradiction and hides that
            # the lengths agreed while the content did not.
            how = (f"{len(got)} bytes, expected {len(raw)}"
                   if len(got) != len(raw) else
                   f"{len(got)} bytes of different content")
            print(f"FAIL {name} level={level}: CPython decoded {how}")
            bad += 1
            continue
        theirs = len(zlib.compress(raw, 6 if level == '-1' else int(level)))
        print(f"  {name:12} level={level:>2} in={len(raw):6} ours={len(enc):6} "
              f"cpython={theirs:6}")
    if rows == 0:
        # An empty run must not read as a pass: a comparison whose inputs were
        # never proven to exist cannot fail (CLAUDE.md, aim the guard).
        print("FAIL no rows on stdin -- lib_zlib_emit produced nothing")
        return 1
    print(f"zlib cpython oracle: {rows} streams, {bad} rejected")
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main())
