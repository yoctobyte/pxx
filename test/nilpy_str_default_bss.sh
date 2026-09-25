#!/bin/sh
# A NilPy str default (or any hidden variable typed after a str literal) must
# not cost .bss.
#
#   sh test/nilpy_str_default_bss.sh <compiler> <tmpdir>
#
# The defect: a hidden global typed from a VALUE node took the literal's own
# type, tyString, and tyString STORAGE is the fixed buffer, so a global of it is
# STRING_CAP + 8 = 8,388,616 bytes. `def f(s, safe="/")` added 8 MiB of .bss on
# every target, `a = b = "x"` 25 MB, and mimic_urllib_parse's three defaults
# made `from urllib.parse import unquote` 25 MB, unlinkable on an ESP32-S3.
#
# THE OUTPUT WAS ALWAYS RIGHT, so an expect_same on it cannot fail for this
# defect. The assertion is the size: each shape's bss must sit within SLACK
# bytes of its twin that has no str-literal-typed hidden variable. SLACK is far
# below one STRING_CAP, so any regression of the class, not only this spelling,
# reds it. Measured positive control, 2026-09-25: the compiler before the fix
# (3c3aae9e56fc) fails every shape except `lambda` (which never took this path)
# with deltas of one or three STRING_CAP + 8 slots
# (8388616 B each) plus a few bytes.
#
# The bss figure is read off the compiler's own `ok:` line, not from the ELF: a
# pxx binary carries no section headers, so `size` reads 0.
set -u
PXX="$1"; T="$2"
SLACK=4096
fail=0
bss() { "$PXX" "$1" "$2" 2>&1 | sed -n 's/.*bss=\([0-9]*\)B.*/\1/p'; }

row() {  # row <name> <expected output> ; sources in $T/<name>.py and $T/<name>_twin.py
  n="$1"; want="$2"
  a="$(bss "$T/$n.py" "$T/$n")"; b="$(bss "$T/${n}_twin.py" "$T/${n}_twin")"
  if [ -z "$a" ] || [ -z "$b" ]; then echo "FAIL strdflt-$n: did not build"; fail=1; return; fi
  got="$("$T/$n" 2>&1)"
  d=$((a - b))
  if [ "$got" != "$want" ]; then echo "FAIL strdflt-$n: output [$got] want [$want]"; fail=1
  elif [ "$d" -gt "$SLACK" ] || [ "$d" -lt "-$SLACK" ]; then
    echo "FAIL strdflt-$n: bss $a vs twin $b (delta $d > $SLACK)"; fail=1
  else echo "PASS strdflt-$n (bss delta $d)"; fi
}

printf 'def f(s, safe="/"):\n    return s + safe\nprint(f("a"))\nh = f\nprint(h("b"))\n' > "$T/def.py"
printf 'def f(s, safe):\n    return s + safe\nprint(f("a", "/"))\nprint(f("b", "/"))\n' > "$T/def_twin.py"
row def "$(printf 'a/\nb/')"

printf 'class C:\n    def m(self, s, sep="/"):\n        return s + sep\nprint(C().m("a"))\n' > "$T/meth.py"
printf 'class C:\n    def m(self, s, sep):\n        return s + sep\nprint(C().m("a", "/"))\n' > "$T/meth_twin.py"
row meth "a/"

printf 'def outer():\n    def f(s, safe="/"):\n        return s + safe\n    return f("a")\nprint(outer())\n' > "$T/nested.py"
printf 'def outer():\n    def f(s, safe):\n        return s + safe\n    return f("a", "/")\nprint(outer())\n' > "$T/nested_twin.py"
row nested "a/"

printf 'g = lambda s, t="/": s + t\nprint(g("a"))\n' > "$T/lambda.py"
printf 'g = lambda s, t: s + t\nprint(g("a", "/"))\n' > "$T/lambda_twin.py"
row lambda "a/"

printf 'a = b = "x"\nprint(a + b)\n' > "$T/chain.py"
printf 'a = "x"\nb = "x"\nprint(a + b)\n' > "$T/chain_twin.py"
row chain "xx"

printf 'from urllib.parse import unquote\nprint(unquote("a%%20b"))\n' > "$T/url.py"
printf 'print("a b")\n' > "$T/url_twin.py"
row url "a b"

[ "$fail" = 0 ] && echo "nilpy_str_default_bss: GREEN" || { echo "nilpy_str_default_bss: RED"; exit 1; }
