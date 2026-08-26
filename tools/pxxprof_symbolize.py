r"""Symbolize tools/pxxprof's RIP samples into a hot-function report.

    python3 tools/pxxprof_symbolize.py syms.txt samples.txt | head -30

syms.txt is "hexaddr name" per line, sorted. Build it from whichever the binary
offers:

  FPC-built (has a symtab, but fpc strips by default -- add -Xs-):
    nm -n BIN | grep -E ' [tT] ' | awk '{print $1, $3}' | sort > syms.txt

  pxx-built (no symtab at all; build it with -g and read DWARF):
    readelf --debug-dump=info BIN | awk '
      /DW_TAG_subprogram/ {name=""; low=""}
      /DW_AT_name/ { n=$0; sub(/.*DW_AT_name *: */,"",n);
                     gsub(/^\(indirect string, offset: 0x[0-9a-f]*\): /,"",n); name=n }
      /DW_AT_low_pc/ { l=$0; sub(/.*DW_AT_low_pc *: */,"",l); low=l;
                       if(name!="" && low!="") print low, name }' \
      | sed 's/^0x//' | sort > syms.txt

  Caveat for the pxx case: the BUILTIN units (PXXAlloc, PXXFree, the runtime
  blobs) carry no DWARF, so they all fall into the FIRST symbol's range. When
  that range is hot -- it was 56 percent of a one-line NilPy compile -- read it
  by disassembling around the hot addresses, not by trusting the name.

Samples above the last symbol are the vDSO, not code: they are counted
separately and must never be read as time (see tools/pxxprof.c).
"""
import sys, bisect, collections

syms = []
with open(sys.argv[1]) as f:
    for line in f:
        p = line.split()
        if len(p) >= 2:
            syms.append((int(p[0], 16), p[1]))
syms.sort()
addrs = [a for a, _ in syms]

cnt = collections.Counter()
tot = 0
with open(sys.argv[2]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        a = int(line, 16)
        if a > addrs[-1] + 0x20000:
            cnt["<outside .text / vdso>"] += 1
            tot += 1
            continue
        i = bisect.bisect_right(addrs, a) - 1
        name = syms[i][1] if i >= 0 else "??"
        cnt[name] += 1
        tot += 1

print("total samples:", tot)
for name, c in cnt.most_common(200):
    print("%6.2f%% %6d  %s" % (100.0 * c / tot, c, name))
