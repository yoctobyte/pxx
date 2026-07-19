/* Known-answer-test driver for js-sha256 v0.11.1 under the compiled qjs
   (feature-c-corpus-quickjs: "run one real pure-compute JS library").

   Concatenated AFTER library_candidates/js-sha256/src/sha256.js by the
   make test-quickjs recipe, with a `var window = globalThis;` prelude so the
   library's UMD wrapper attaches sha256/sha224 to the global object. Like
   smoke.js, accumulates lines and yields them as the script's final value,
   which the runner prints.

   The NIST FIPS 180-4 / RFC 6234 / RFC 4231 vectors are the oracle; the
   gcc-built qjs runs the same concatenation as a cross-check (byte-exact). */

var out = [];
var failures = 0;

function check(name, got, want) {
    if (got === want) {
        out.push("PASS " + name + " " + got);
    } else {
        failures++;
        out.push("FAIL " + name + " got=" + got + " want=" + want);
    }
}

/* NIST FIPS 180-4 / RFC 6234 test vectors */
check("sha256-empty", sha256(""),
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
check("sha256-abc", sha256("abc"),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
check("sha256-448bit", sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
check("sha256-896bit", sha256("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"),
      "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1");
check("sha224-abc", sha224("abc"),
      "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7");
check("sha224-448bit", sha224("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
      "75388b16512776cc5dba5da1fd890150b0c6455cb4f58b1952522525");

/* One million 'a' — incremental update API, 1000 chunks of 1000 */
var chunk = "";
for (var i = 0; i < 1000; i++) chunk += "a";
var h = sha256.create();
for (var j = 0; j < 1000; j++) h.update(chunk);
check("sha256-million-a", h.hex(),
      "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");

/* Non-string inputs: byte array + Uint8Array paths */
check("sha256-bytearray", sha256([0x61, 0x62, 0x63]),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
check("sha256-uint8array", sha256(new Uint8Array([0x61, 0x62, 0x63])),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");

/* UTF-8 encoding path (multi-byte code points) vs explicit bytes */
check("sha256-utf8", sha256("café 中文"),
      sha256([0x63, 0x61, 0x66, 0xc3, 0xa9, 0x20, 0xe4, 0xb8, 0xad, 0xe6, 0x96, 0x87]));

/* HMAC-SHA256 (RFC 4231 test cases 1 & 2) */
var key1 = "0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b".match(/../g).map(function (x) { return parseInt(x, 16); });
check("hmac-sha256-tc1", sha256.hmac(key1, "Hi There"),
      "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7");
check("hmac-sha256-tc2", sha256.hmac("Jefe", "what do ya want for nothing?"),
      "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");

out.push(failures === 0 ? "ALL PASS" : "FAILURES: " + failures);
out.join('\n');
