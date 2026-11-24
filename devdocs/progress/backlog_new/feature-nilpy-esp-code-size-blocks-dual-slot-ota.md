---
slug: feature-nilpy-esp-code-size-blocks-dual-slot-ota
track: N
prio: 60
type: feature
status: backlog
created: 2026-11-23
found-by: rfid project (Nil Python firmware on ESP32-C3), via claude session rfid-0e
tags: [nilpy, esp, size, riscv32]
blocked-by: []
summary: "A 263-line Nil Python program (JSON lines over USB, a config dict in NVS, one class, RC522 and OTA externals) is ~1.06 MB of flash on ESP32-C3 at -O2 (.text 949 KB, .rodata 115 KB). The whole IDF image is 1.62 MB without Wi-Fi and 1.96 MB with Wi-Fi + HTTP in C, against a ~1.94 MB two-slot OTA limit on 4 MB flash, so the Python runtime decides whether the product can do safe OTA. Target: under ~0.6 MB of app code for a program like this. Leads: a dict literal costs ~360 B per key and a 1-function if/elif dispatcher 32 KB; the generic call-binding bodies (PyHostCall 36K, PyBoundFnCallvnMaskBody 26K, PyDynMethL 20K, PyStrMethodByName 17K, PyBoundPairCallKwBody 14K, PyBoundCallStarSig 9K) are linked when the program never uses star or keyword calls; a size-oriented codegen mode for --platform=esp."
---

# Nil Python code size on ESP blocks dual-slot OTA

Reported 2026-11-23 by the rfid project (session rfid-0e, owner-approved).
`near` found nothing similar. backlog-esp/feature-code-size-int64-arith-and-string-building
is about Pascal app code (int64 and string building), not the Nil Python
runtime's dispatch bodies.

## Numbers (theirs)

Built with pxx latest-4c6195305e (compiler d190f0ee65f5), `--target=riscv32
--platform=esp --no-signals`, default -O2. The source is
/home/neo/rfid/firmware/main/main.npy, 263 lines; `./build.sh` builds it.
That tree belongs to the rfid project: copy it to a scratch directory, don't
edit it in place.

- main.o: .text 949,328, .rodata 114,552, .data 15,960, .bss 33,980.
- -O1 is ~1.7 MB. --dce changes nothing, because -O2 already prunes.
- The image (ESP-IDF 6.0.1, -Os, no IPv6/softAP) is 1.62 MB. With Wi-Fi +
  HTTP in C it is 1.96 MB; with pxx `network` + `urequests` it is 2.32 MB.
  The OTA two-slot maximum on 4 MB is ~1.94 MB.

Largest symbols: PyHostCall 35.9K, user `handle` 32.2K (one if/elif over a
parsed JSON dict), PyBoundFnCallvnMaskBody 26.3K, PyDynMethL 19.6K,
PyStrMethodByName 17.1K, PyBoundPairCallKwBody 13.9K, pyiter_has_slow 12.5K,
PyEvalMethodOn 11.2K, user `main` 9.0K, PyBoundCallStarSig 8.7K,
pypercent_format 7.5K, PyBuiltinMethodCallL 7.2K, user `default_config` 6.1K
(one 17-key dict literal), user `load_config` 4.3K.

## Leads

1. Generated code per user line: ~360 B per dict-literal key, and 32 KB for
   the dispatcher.
2. The generic by-name, keyword and star-call binding bodies are linked
   when no call in the program uses them. That's a DCE question: what roots
   them?
3. A size-oriented codegen mode for --platform=esp.

The rfid project has a fallback in the meantime: a C factory updater plus one
big app slot.

## 2026-11-24 measured (claude-pxx): two init hooks root ~314 KB

Reproduced at cfbc7b2726: main.o .text 951,532. `--dce-why=<name>` on the
large bodies gives one root for nearly all of them:

    PyHostCall <- PyCallDunder <- pyvar_callv0 <- [@proc taken in unowned code]
    PyBoundFnCallvnMaskBody <- pyboundfn_callvn_mask <- pyboundfn_callvn <- pyvar_callv0 <- ...
    PyDynMethL / PyStrMethodByName / PyEvalMethodOn / PyBuiltinMethodCallL <- PyCallDunder <- pyvar_callv0 <- ...
    PyBoundPairCallKwBody / PyBoundCallStarSig <- ... <- PyCallDunder <- pyvar_callv0 <- ...

The address is taken in pyeval.pas's `initialization`:
`PyIterCallHook := @PyCallKey1; PyCall0Hook := @pyvar_callv0;`.

| pyeval init (scratch copy) | .text |
|---|---|
| as shipped | 951,532 |
| only PyIterCallHook installed | 951,508 |
| only PyCall0Hook installed | 944,640 |
| neither | 637,656 (-314 KB, -33%) |

So both must go. Neither is used by this program: it has no defaultdict
factory, no sort key, no min/max key.

Why the obvious fixes don't work:
- Deleting the install is wrong. It is unconditional because a lazy install
  (map/filter only) gave bug-nilpy-min-max-with-a-key-held-in-a-variable;
  with no hook, PyCallKeyVar falls back to pybound_callv1, which answers
  None for tags 9/10/12.
- A DCE rule "root the hook's target only if a reader of the hook is live"
  saves nothing here. The readers are TPyDict.fetch (every dict lookup) and
  TPyList.sort (kept by its VMT slot), both live.

Direction: install the hooks where a value that needs them is made, as
PyClosureInvokeHook already is (pyeval.pas, "NOT A LAZY HOOK OF THE
PyIterCallHook KIND"):
- tag 9/10 (closure, bound fn) are made in pyeval: install there;
- a defaultdict factory: route collections.defaultdict through a pyeval
  wrapper that installs PyCall0Hook;
- tag 12 (a compiled def boxed into a Variant) is stamped inline by every
  backend (IRSrcIsCallable), so there is no runtime site. It needs a
  compiler-emitted install at program start when any surviving body boxes a
  callable; to measure whether builtin units box callables themselves, which
  would void the gain.
