---
track: C
tags: [cfront, typedef, function-types, enum, pathb, expat]
prio: 85
type: bug
blocked-by: []
summary: "`typedef enum E Processor(XML_Parser, ...);` went to the typedef parser's enum arm, which registered Processor as an int and skipped the parameter list. `static Processor prologInitProcessor;` then declared a 4-byte object, and every `parser->m_processor = prologInitProcessor` stored 0. expat parsed every document as `ok` without calling one handler, so fontconfig ignored its whole config."
status: done
owner: pxx2
---

# A function typedef returning an enum declared objects

cparser.inc, the typedef parser: `enum TAG` with no body followed by a
function declarator (`NAME (` or `( *`) is not an enum typedef; it takes the
general path, which reads `enum E` as a type and registers the function type.

Test: test/c_enum_fn_typedef.c (row c_enumfnt26) against gcc, x86-64 and i386.
