---
title: Core classes
order: 52
---

# Core classes — lists and streams

PXX provides a lightweight, FPC-compatible implementation of core Object Pascal container and stream classes in the `classes` unit. 

These classes are reference types (managed on the heap) and must be instantiated with `Create` and released with `Free`.

---

## TList (Pointer List)

`TList` maintains a dynamic, ordered list of raw pointers (`Pointer`). It is useful for managing low-level collections of objects or records.

### Key Members

- **`Add(Ptr: Pointer): Integer`**: Appends a pointer to the end of the list and returns its index.
- **`Insert(Index: Integer; Ptr: Pointer)`**: Inserts a pointer at the specified index, shifting subsequent items right.
- **`Delete(Index: Integer)`**: Removes the pointer at the specified index and shifts subsequent items left.
- **`Remove(Ptr: Pointer): Integer`**: Removes the first occurrence of the specified pointer from the list. Returns the index of the removed item, or `-1` if not found.
- **`IndexOf(Ptr: Pointer): Integer`**: Returns the 0-based index of the first occurrence of the pointer, or `-1` if not found.
- **`Count: Integer`**: Property returning the number of items currently in the list.
- **`Items[Index: Integer]: Pointer`** (Default): Gets or sets the pointer at the specified index. You can use array bracket syntax directly on the list instance (e.g., `list[i]`).

---

## TStrings & TStringList (String List)

`TStringList` is a concrete class that implements the abstract `TStrings` contract. It manages a list of strings, providing sorting, search, multiline conversion, and association of custom metadata objects with each string.

### Key Members

- **`Add(const S: string): Integer`**: Appends a string to the list.
- **`IndexOf(const S: string): Integer`**: Returns the 0-based index of the first occurrence of the string, or `-1` if not found.
- **`Sort`**: Sorts the list alphabetically using `CompareStr` (character-code comparison).
- **`Strings[Index: Integer]: string`** (Default): Gets or sets the string at the specified index. Supports bracket syntax (e.g., `sl[i]`).
- **`Objects[Index: Integer]: TObject`**: Gets or sets a custom object reference associated with the string at the specified index.
- **`Text: string`**: Property that gets or sets the entire list as a single multiline string with CRLF (`#13#10`) line endings.
- **`SetText(const S: string)`**: Populates the list by parsing a single multiline string (supporting LF and CRLF line endings).

---

## TStream & TMemoryStream (Byte Streams)

`TStream` is the abstract base class for sequential byte streams. `TMemoryStream` is a concrete implementation that backs the stream with a dynamic, automatically resizing memory buffer.

### Key Members

- **`Write(const Buffer; Count: Longint): Longint`**: Writes `Count` bytes from the buffer to the stream at the current position. Returns the number of bytes actually written.
- **`Read(var Buffer; Count: Longint): Longint`**: Reads `Count` bytes from the stream into the buffer starting at the current position. Returns the number of bytes actually read.
- **`Seek(const Offset: Int64; Origin: TSeekOrigin): Int64`**: Sets the stream position. `Origin` can be:
  - `soBeginning`: Seek relative to the start of the stream.
  - `soCurrent`: Seek relative to the current position.
  - `soEnd`: Seek relative to the end of the stream.
- **`Position: Int64`**: Property to get or set the current byte offset in the stream.
- **`Size: Int64`**: Read-only property returning the total size of the stream in bytes.
- **`CopyFrom(Source: TStream; Count: Int64): Int64`**: Copies `Count` bytes from the `Source` stream to this stream.

---

## Compiling Example

The following program demonstrates lists, string lists, and streams. It compiles and runs on the pinned compiler:

```pascal
program core_classes_demo;

uses classes, sysutils;

procedure DemoList;
var
  list: TList;
begin
  writeln('--- TList Demo ---');
  list := TList.Create;
  try
    list.Add(Pointer(100));
    list.Add(Pointer(200));
    list.Add(Pointer(300));
    
    writeln('List count: ', list.Count);
    writeln('Item at index 1: ', Int64(list[1]));
    
    // Insert an item
    list.Insert(1, Pointer(150));
    writeln('After insert, item at index 1: ', Int64(list[1]));
    writeln('New count: ', list.Count);
  finally
    list.Free;
  end;
end;

procedure DemoStringList;
var
  sl: TStringList;
  i: Integer;
begin
  writeln('--- TStringList Demo ---');
  sl := TStringList.Create;
  try
    sl.Add('orange');
    sl.Add('apple');
    sl.Add('banana');
    
    sl.Sort;
    writeln('Sorted fruit:');
    for i := 0 to sl.Count - 1 do
      writeln('  ', sl[i]);
      
    writeln('Multiline representation:');
    write(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure DemoMemoryStream;
var
  ms: TMemoryStream;
  wVal, rVal: Integer;
begin
  writeln('--- TMemoryStream Demo ---');
  ms := TMemoryStream.Create;
  try
    wVal := 12345;
    
    // Write 4 bytes (size of Integer) to the stream
    ms.Write(wVal, 4);
    writeln('Stream size: ', ms.Size);
    writeln('Stream position: ', ms.Position);
    
    // Reset position to the beginning to read
    ms.Position := 0;
    ms.Read(rVal, 4);
    writeln('Read integer value: ', rVal);
  finally
    ms.Free;
  end;
end;

begin
  DemoList;
  DemoStringList;
  DemoMemoryStream;
end.
```

Output:

```
--- TList Demo ---
List count: 3
Item at index 1: 200
After insert, item at index 1: 150
New count: 4
--- TStringList Demo ---
Sorted fruit:
  apple
  banana
  orange
Multiline representation:
apple
banana
orange
--- TMemoryStream Demo ---
Stream size: 4
Stream position: 4
Read integer value: 12345
```
