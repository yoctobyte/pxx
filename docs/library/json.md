---
title: JSON
order: 53
---

# JSON processing — the `json` unit

PXX includes a native, lightweight JSON parser and serializer in the `json` unit. It features a recursive-descent parser, typed value accessors, canonical round-trip serialization, and pretty-printing.

---

## TJSONValue (JSON Node)

The `TJSONValue` class represents any node in a JSON tree, such as an object, an array, a string, a number, a boolean, or a null value. 

### Key Members

- **`Count: Integer`**: Property returning the number of elements (for arrays) or the number of key-value pairs (for objects). Returns `0` for scalar values.
- **`HasKey(const Key: AnsiString): Boolean`**: Returns `True` if the node is a JSON object and contains the specified key.
- **`GetValue(const Key: AnsiString): TJSONValue`**: Returns the child `TJSONValue` associated with the specified key in a JSON object. Returns `nil` if the key is absent or the node is not an object.
- **`GetItem(Index: Integer): TJSONValue`**: Returns the child `TJSONValue` at the specified 0-based index in a JSON array.
- **`AsString: AnsiString`**: Converts and returns the node value as a string.
- **`AsInteger: Int64`**: Converts and returns the node value as an integer.
- **`AsBoolean: Boolean`**: Converts and returns the node value as a boolean.
- **`ToString(Pretty: Boolean): AnsiString`**: Serializes the JSON tree back into a string.
  - `Pretty = False` (default): Emits a compact, canonical JSON string (whitespace-free, stable key ordering).
  - `Pretty = True`: Emits formatted, indented JSON.
- **`FreeTree`**: Recursively releases the entire JSON tree from memory. Call this on the root node when you are finished to prevent memory leaks.

---

## Parsing JSON

To parse a JSON string, use the global `JSONParse` function, which returns the root `TJSONValue` node:

```pascal
function JSONParse(const S: AnsiString): TJSONValue;
```

### Error Handling
If the input string is malformed or has trailing junk, `JSONParse` raises an **`EJSONError`** exception (defined in the `json` unit).

---

## Compiling Example

The following program demonstrates parsing, reading typed values, checking keys, serializing, and handling parse errors. It compiles and runs on the pinned compiler:

```pascal
program json_demo;

uses json, sysutils;

procedure DemoJsonParsing;
var
  jsonText: AnsiString;
  root, nameVal, ageVal, activeVal, tagsVal: TJSONValue;
  i: Integer;
begin
  // A sample JSON payload
  jsonText := '{"name": "Alice", "age": 30, "active": true, "tags": ["admin", "user"]}';
  
  writeln('Parsing JSON payload...');
  root := JSONParse(jsonText);
  try
    // Accessing object fields by name
    nameVal := root.GetValue('name');
    writeln('Name: ', nameVal.AsString);
    
    ageVal := root.GetValue('age');
    writeln('Age: ', ageVal.AsInteger);
    
    activeVal := root.GetValue('active');
    writeln('Active: ', activeVal.AsBoolean);
    
    // Accessing array items by index
    tagsVal := root.GetValue('tags');
    writeln('Tags count: ', tagsVal.Count);
    for i := 0 to tagsVal.Count - 1 do
      writeln('  Tag ', i, ': ', tagsVal.GetItem(i).AsString);
      
    // Check if a key exists
    if root.HasKey('missing') then
      writeln('Key "missing" is present')
    else
      writeln('Key "missing" is absent');
      
    // Serializing back to JSON strings
    writeln('Compact JSON:');
    writeln(root.ToString(False));
    
    writeln('Pretty JSON:');
    writeln(root.ToString(True));
  finally
    // Free the entire tree recursively
    root.FreeTree;
  end;
end;

procedure DemoJsonError;
var
  root: TJSONValue;
begin
  writeln('--- Testing Parse Error ---');
  try
    // Malformed JSON (missing closing brace)
    root := JSONParse('{"name": "Alice"');
    root.FreeTree;
  except
    on E: EJSONError do
      writeln('Caught expected JSON parse error: ', E.Reason);
  end;
end;

begin
  DemoJsonParsing;
  DemoJsonError;
end.
```

Output:

```
Parsing JSON payload...
Name: Alice
Age: 30
Active: TRUE
Tags count: 2
  Tag 0: admin
  Tag 1: user
Key "missing" is absent
Compact JSON:
{"name":"Alice","age":30,"active":true,"tags":["admin","user"]}
Pretty JSON:
{
  "name": "Alice",
  "age": 30,
  "active": true,
  "tags": [
    "admin",
    "user"
  ]
}
--- Testing Parse Error ---
Caught expected JSON parse error: expected value
```
