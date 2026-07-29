# SPDX-License-Identifier: Zlib
"""gdb pretty-printers for pxx-compiled programs.

    (gdb) source tools/pxx-gdb.py

Compile with -g (and -O2 if you want the optimisation level the ownership bugs
actually appear at; -g only forces -O0 when no -O is given).

What it adds:

  * Variant        {VType=6, Payload=...}   ->   'hello' (str)
  * object header  `pxxrc <expr>`           ->   refcount + population tag
  * poison         a quarantined block      ->   named as such, not printed as
                                                 a plausible value

The refcount is the point. Half the bugs in this runtime are "who took a
reference and who dropped it", and until now the answer was invisible from the
debugger: the count lives at [inst-16], below the pointer gdb shows you.

See devdocs/dev/debug-heap.md for the -dPXX_HEAP_DEBUG / -dPXX_OBJTRACE
switches this complements, and devdocs/dev/dwarf.md for what the DWARF covers.
"""

import gdb
import struct

# Variant tags — pylib's PyVarSlot* family is the authority; keep in step.
VT_EMPTY, VT_INT, VT_INT64, VT_DOUBLE, VT_BOOL = 0, 1, 2, 3, 4
VT_CHAR, VT_STRING, VT_OBJECT, VT_BOUNDMETHOD, VT_PYCLOSURE = 5, 6, 7, 8, 9
VT_PROMO_INT64 = 8193

# builtinheap: rc at [inst-16], population tag at [inst-8].
PXX_OBJ_MAGIC = 0x505942F1          # class instance
PXX_OBJ_MAGIC_RAW = 0x505942F9      # VMT-less block ({code,recv} pairs)
PXX_OBJ_MAGIC_RAW2 = 0x505942E1     # pyeval closure
POISON_WORD = 0xDDDDDDDDDDDDDDDD    # -dPXX_HEAP_DEBUG quarantine fill

MAGIC_NAME = {
    PXX_OBJ_MAGIC: "obj",
    PXX_OBJ_MAGIC_RAW: "raw",
    PXX_OBJ_MAGIC_RAW2: "closure",
}


def _read_cstring(addr, limit=200):
    """The bytes at addr up to a NUL. A managed string handle points straight
    at the character data (length and refcount live below it)."""
    if addr == 0:
        return None
    try:
        return gdb.selected_inferior().read_memory(addr, limit).tobytes().split(b"\0")[0]
    except gdb.MemoryError:
        return None


def _obj_header(addr):
    """(refcount, magic) for a headered object, or None if addr is not one.

    Deliberately tolerant: the guards must not fault on a boxed int or a
    sentinel that merely looks like a pointer, which is the same reason
    PXXObjPlausible exists on the runtime side."""
    if addr == 0:
        return None
    try:
        mem = gdb.selected_inferior().read_memory(addr - 16, 16).tobytes()
    except gdb.MemoryError:
        return None
    rc, magic = struct.unpack("<qq", mem)
    return rc, magic


def _describe_object(addr):
    hdr = _obj_header(addr)
    if hdr is None:
        return "0x%x" % addr
    rc, magic = hdr
    if (magic & 0xFFFFFFFFFFFFFFFF) == POISON_WORD:
        return "0x%x <FREED — poison, still in quarantine>" % addr
    name = MAGIC_NAME.get(magic & 0xFFFFFFFF)
    if name is None:
        return "0x%x <unheadered>" % addr      # plain GetMem instance
    return "0x%x <%s rc=%d>" % (addr, name, rc)


class VariantPrinter:
    """A NilPy Variant: two words {VType, Payload}, decoded by tag."""

    def __init__(self, val):
        self.val = val

    def to_string(self):
        try:
            tag = int(self.val["VType"])
            payload = int(self.val["Payload"])
        except (gdb.error, gdb.MemoryError):
            return "<unreadable Variant>"

        if tag == VT_EMPTY:
            return "None"
        if tag in (VT_INT, VT_INT64):
            return "%d" % payload
        if tag == VT_BOOL:
            return "True" if payload else "False"
        if tag == VT_DOUBLE:
            # the payload holds IEEE bits, not a number — reinterpret, never cast
            return repr(struct.unpack("<d", struct.pack("<q", payload))[0])
        if tag == VT_CHAR:
            return repr(chr(payload & 0xFF))
        if tag in (VT_STRING, VT_PROMO_INT64):
            s = _read_cstring(payload)
            what = "str" if tag == VT_STRING else "promo-int"
            if s is None:
                return "<%s at 0x%x — unreadable>" % (what, payload)
            return "%r (%s)" % (s.decode("utf-8", "replace"), what)
        if tag == VT_OBJECT:
            return "object %s" % _describe_object(payload)
        if tag == VT_BOUNDMETHOD:
            return "bound-method %s" % _describe_object(payload)
        if tag == VT_PYCLOSURE:
            return "pyeval-closure #%d" % payload
        return "<tag %d payload 0x%x>" % (tag, payload)


def _lookup(val):
    try:
        t = val.type.strip_typedefs()
    except gdb.error:
        return None
    if t.code == gdb.TYPE_CODE_STRUCT and t.tag == "Variant":
        return VariantPrinter(val)
    return None


class PxxRefcount(gdb.Command):
    """pxxrc EXPR — refcount and population tag of a pxx heap object.

    The count lives at [inst-16], which is below the pointer the debugger
    shows, so it is otherwise invisible. Under -dPXX_HEAP_DEBUG a freed block
    is reported as such rather than as whatever its recycled bytes look like."""

    def __init__(self):
        super(PxxRefcount, self).__init__("pxxrc", gdb.COMMAND_DATA)

    def invoke(self, arg, from_tty):
        if not arg.strip():
            raise gdb.GdbError("usage: pxxrc EXPR")
        val = gdb.parse_and_eval(arg)
        t = val.type.strip_typedefs()
        if t.code == gdb.TYPE_CODE_STRUCT and t.tag == "Variant":
            addr = int(val["Payload"])          # a variant: report its payload
        else:
            addr = int(val)
        hdr = _obj_header(addr)
        if hdr is None:
            gdb.write("0x%x: not readable as a pxx object\n" % addr)
            return
        rc, magic = hdr
        if (magic & 0xFFFFFFFFFFFFFFFF) == POISON_WORD:
            gdb.write("0x%x: FREED (poison) — a use-after-free is in progress\n" % addr)
            return
        name = MAGIC_NAME.get(magic & 0xFFFFFFFF)
        if name is None:
            gdb.write("0x%x: unheadered (plain GetMem) — not refcounted\n" % addr)
            return
        gdb.write("0x%x: %s, refcount %d\n" % (addr, name, rc))


def register():
    gdb.pretty_printers.append(_lookup)
    PxxRefcount()
    gdb.write("pxx: pretty-printers loaded (Variant), command: pxxrc\n")


register()
