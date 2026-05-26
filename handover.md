# Frankonpiler — Class Methods Handover

**Date:** 2026-05-26  
**Commits this session:** `f6ed3a4`, `ac034ec`

---

## What Was Done This Session

### 1. Fixed class field access (segfault resolved)

`GenLValueAddress` in `compiler/codegen.inc` was extended with a `derefClass: Boolean` parameter:
- **`True`** → emit `mov rax, [GlobRef]` — load heap pointer (for field access / method dispatch)
- **`False`** → emit `lea rax, [GlobRef]` — address of the pointer slot (for assignment targets, pass-by-ref)

All call sites updated. `test/test_class.pas` compiles and runs correctly:
```
1  (obj1 <> 0)
1  (obj2 <> 0)
1  (obj1 <> obj2)
42 (obj1.x)
100 (obj1.y)
999 (obj2.x)
888 (obj2.y)
```

### 2. Dynamic record/class table — plumbing for class methods

Replaced all hardcoded field/size/type lookup chains in `compiler/symtab.inc` with a proper runtime table.

**Files changed:**

| File | What changed |
|---|---|
| `compiler/defs.inc` | Added `TField`, `TRecord` types; `Records[]`, `RecordCount` globals; `MAX_RECORDS=64`, `MAX_FIELDS=64` |
| `compiler/symtab.inc` | `IsRecordType`, `IsClassType`, `RecSize`, `RecFieldOffset`, `RecFieldType`, `RecFieldRecId`, `RecFieldIsArray` now do generic table lookups; added `InitRecords`, `AddRecord`, `AddField`, `AddRecordManual`, `AddFieldManual`, `FieldNameEqual`, `GetFieldSize` |
| `compiler/compiler.pas` | Calls `InitRecords` at startup |

The 10 compiler-internal records (TToken, TSymbol, TProc, etc.) are seeded by `InitRecords` so self-hosting is unaffected. Any record declared by the user in Pascal source will be registered dynamically into the same table.

---

## Where to Pick Up Next: Full Class Method Support

The plumbing is in place. Four steps remain.

### Step 1 — Parse `type` class declarations

**File:** `compiler/parser.inc` → `ParseTypeSection` (~line 1568)

Currently skips class bodies with a depth counter. Must instead:
1. `AddRecord(name, 0, isClass)` → get `recId`
2. Parse field lines: `FieldName : TypeKind;` → `AddField(recId, name, tk, ...)`
3. Parse method signatures inside the class body: `procedure Foo;` / `function Bar: Integer;` — store the method name bound to the class (see step 2), skip body

```pascal
{ What to parse: }
type
  TAnimal = class
    Name : AnsiString;     { → AddField }
    Age  : Integer;        { → AddField }
    procedure Speak;       { → register method declaration }
    function  GetAge: Integer;
  end;
```

### Step 2 — Bind method implementations to their class

**File:** `compiler/parser.inc` → `ParseSubroutine` (~line 1611)  
**File:** `compiler/defs.inc` → `TProc`

Add `OwnerClass: Integer` to `TProc` (default `REC_NONE`).  
When the parser encounters `procedure TAnimal.Speak;` (dot-qualified name), look up `TAnimal` in `Records[]`, bind the `TProc.OwnerClass` field, and map back to the method's earlier declaration in the class body.

### Step 3 — Inject implicit `Self` parameter

When entering a bound method body:
- Add `CurSelfClass: Integer` global (like `CurProc`; `REC_NONE` when outside a method)
- Inject a hidden first parameter `Self: TAnimal` (`tyClass`, same mechanics as any other param)
- In the expression parser, when resolving a bare identifier: if `CurSelfClass <> REC_NONE` and the name matches a field of the owner class → treat as `Self.fieldname`

### Step 4 — `obj.Method(args)` call syntax

**File:** `compiler/parser.inc` → expression parser / field access (~line 393)

When `obj.Ident(` is seen:
- Check if `Ident` is a method name in `obj`'s class (via `Records[recId]`)
- If yes → emit `AN_CALL` with `obj` prepended as the first implicit `Self` argument

No changes needed in `codegen.inc` — `Self` is just another pushed argument.

### Step 5 — `TAnimal.Create` constructor (optional, can come after step 4)

Treat `Create` as a built-in class method: allocate `RecSize(recId)` bytes via `GetMem`, zero-init optional, return pointer.

---

## Target Test

Create `test/test_class_methods.pas` and make it pass:

```pascal
program test_class_methods;
type
  TCounter = class
    Value : Integer;
    procedure Reset;
    procedure Increment;
    function  Get: Integer;
  end;

procedure TCounter.Reset;
begin
  Self.Value := 0;
end;

procedure TCounter.Increment;
begin
  Self.Value := Self.Value + 1;
end;

function TCounter.Get: Integer;
begin
  Result := Self.Value;
end;

var c: TCounter;
begin
  c := TCounter.Create;
  c.Reset;
  c.Increment;
  c.Increment;
  c.Increment;
  writeln(c.Get);   { expect: 3 }
end.
```

---

## Quick File Map

| File | Role |
|---|---|
| `compiler/defs.inc` | All types, constants, global variables |
| `compiler/symtab.inc` | Symbol table + `Records[]` table + all field helpers |
| `compiler/parser.inc` | Recursive-descent parser — `ParseTypeSection`, `ParseSubroutine`, expression parser |
| `compiler/codegen.inc` | AST → x86-64 bytes — `GenLValueAddress` (`derefClass`), `GenAST` |
| `compiler/elfwriter.inc` | ELF output |
| `test/test_class.pas` | Currently passing class field test |
