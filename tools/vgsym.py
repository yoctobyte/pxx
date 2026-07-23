#!/usr/bin/env python3
"""Symbolize valgrind output for pxx binaries using the --proc-map file.
Usage: valgrind ... ./prog 2>&1 | vgsym.py prog.map"""
import sys, re, bisect
entries=[]
for line in open(sys.argv[1]):
    parts=line.split()
    if len(parts)>=2:
        try: addr=int(parts[0],16)
        except ValueError: continue
        entries.append((addr,parts[1]))
entries.sort()
addrs=[a for a,_ in entries]
def sym(m):
    a=int(m.group(1),16)
    i=bisect.bisect_right(addrs,a)-1
    if i>=0 and a-addrs[i]<0x20000:
        return "0x%X %s+0x%x"%(a,entries[i][1],a-addrs[i])
    return m.group(0)
for line in sys.stdin:
    sys.stdout.write(re.sub(r'0x([0-9A-Fa-f]{6,})',sym,line))
