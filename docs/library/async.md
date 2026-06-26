---
title: Coroutines & Async
order: 54
---

# Coroutines & Async Networking

PXX features a built-in, cooperative, single-threaded coroutine scheduler and an asynchronous networking reactor. This allows a single operating system thread to manage thousands of concurrent connections and tasks without the overhead of OS threads.

---

## Cooperative Scheduling — the `scheduler` unit

The `scheduler` unit provides the core coroutine lifestyle routines. Coroutines are cooperatively scheduled, meaning a running task continues execution until it voluntarily yields control back to the scheduler.

### Key Routines

- **`procedure Spawn(entry: TCoroEntry; arg: Pointer);`**
  Spawns a new coroutine with a default stack size (64 KB). The `entry` parameter is a procedural type matching `procedure(arg: Pointer)`.
  
- **`procedure SpawnSized(entry: TCoroEntry; arg: Pointer; stackBytes: Int64);`**
  Spawns a coroutine with a custom stack size in bytes. This is highly useful for memory-constrained platforms (such as embedded ESP32 targets), where small 4 KB or 8 KB stacks are sufficient and conserve RAM.
  
- **`procedure CoYield;`**
  Voluntarily yields control, allowing the scheduler to run other ready coroutines in a round-robin fashion.
  
- **`procedure CoSleep(ms: Integer);`**
  Suspends the current coroutine for `ms` milliseconds. The scheduler registers a non-blocking timer and yields, allowing other tasks to run. Control returns to the coroutine once the timer expires.
  
- **`procedure RunUntilDone;`**
  Starts the scheduler's reactor loop. This routine blocks the host thread and drives the coroutines until all spawned tasks have completed.

---

## Asynchronous Sockets — the `asyncnet` unit

The `asyncnet` unit provides non-blocking TCP socket operations integrated with the scheduler's reactor. When a socket operation would block (returning `EAGAIN`), the coroutine automatically parks on the reactor and yields, waking up only when the socket becomes ready.

### Key Routines

- **`function TcpListen(port: Integer): Integer;`**
  Creates a non-blocking listening socket bound to the loopback IPv4 address (`127.0.0.1`) on the specified port. Returns the socket file descriptor, or a negative value on error.
  
- **`function TcpAccept(lfd: Integer): Integer;`**
  Accepts an incoming connection on a listening socket `lfd`. If no connection is pending, the calling coroutine yields and parks until a client connects. Returns the connected socket descriptor.
  
- **`function TcpConnect(port: Integer): Integer;`**
  Connects asynchronously to a loopback port. Yields control until the connection is established.
  
- **`function TcpConnectAddr(host: LongWord; port: Integer): Integer;`**
  Connects asynchronously to an arbitrary IPv4 address (in host byte order) and port.
  
- **`function TcpRecv(fd: Integer; buf: Pointer; len: Integer): Int64;`**
  Receives up to `len` bytes from the socket into `buf`. If no data is available, it yields and parks. Returns the number of bytes read, `0` if the peer closed the connection, or a negative error code.
  
- **`function TcpSend(fd: Integer; buf: Pointer; len: Integer): Int64;`**
  Sends up to `len` bytes from `buf` over the socket. Yields and parks if the socket's write buffer is full. Returns the number of bytes sent.
  
- **`procedure TcpClose(fd: Integer);`**
  Closes the socket file descriptor and cleans up reactor state.

---

## Under the Hood

The coroutine system is built on two key pillars:
1. **Low-level context switching**: A compiler intrinsic (`__pxxcoswitch`) saves and restores CPU registers and stack pointers.
2. **Procedural types**: Coroutines are defined using plain Pascal procedures, requiring no target-specific assembly entry shims.

On **x86-64 Linux**, the scheduler utilizes a high-performance **epoll** reactor. Socket wait states (`WaitReadable` / `WaitWritable`) and sleep states are registered as epoll events. On other targets (or platforms where epoll is unavailable), these operations gracefully degrade to a busy-poll `CoYield` loop, maintaining API compatibility across the entire PXX target matrix.

---

## Compiling Example

The following program implements a concurrent TCP echo server and client running on a single thread. The client sends a message, and the server receives and echoes it back. 

This program compiles and runs on the pinned compiler:

```pascal
program async_echo_demo;

uses scheduler, asyncnet, sysutils;

const
  PORT = 28888;
  BUF_SIZE = 256;

procedure ServerCo(arg: Pointer);
var
  lfd, cfd: Integer;
  buf: array[0..BUF_SIZE-1] of Char;
  bytes: Int64;
  s: AnsiString;
  i: Integer;
begin
  lfd := TcpListen(PORT);
  if lfd < 0 then
  begin
    writeln('Server failed to listen');
    Exit;
  end;
  
  writeln('Server listening on port ', PORT);
  cfd := TcpAccept(lfd);
  if cfd < 0 then
  begin
    writeln('Server failed to accept');
    TcpClose(lfd);
    Exit;
  end;
  
  writeln('Server accepted connection');
  
  // Read client message (yields coroutine if data is not yet ready)
  bytes := TcpRecv(cfd, @buf[0], BUF_SIZE - 1);
  if bytes > 0 then
  begin
    // Copy character array to string for printing
    SetLength(s, bytes);
    for i := 0 to bytes - 1 do
      s[i + 1] := buf[i];
    writeln('Server received: ', s);
    
    // Echo the bytes back to the client
    TcpSend(cfd, @buf[0], bytes);
  end;
  
  TcpClose(cfd);
  TcpClose(lfd);
  writeln('Server shut down');
end;

procedure ClientCo(arg: Pointer);
var
  cfd: Integer;
  msg: AnsiString;
  buf: array[0..BUF_SIZE-1] of Char;
  bytes: Int64;
  s: AnsiString;
  i: Integer;
begin
  // Give the server a moment to start up
  CoSleep(100);
  
  writeln('Client connecting...');
  cfd := TcpConnect(PORT);
  if cfd < 0 then
  begin
    writeln('Client failed to connect');
    Exit;
  end;
  
  writeln('Client connected');
  msg := 'Hello from PXX Async!';
  
  // Send message over the socket
  TcpSend(cfd, @msg[1], Length(msg));
  
  // Read the echoed message back
  bytes := TcpRecv(cfd, @buf[0], BUF_SIZE - 1);
  if bytes > 0 then
  begin
    SetLength(s, bytes);
    for i := 0 to bytes - 1 do
      s[i + 1] := buf[i];
    writeln('Client received echo: ', s);
  end;
  
  TcpClose(cfd);
  writeln('Client shut down');
end;

begin
  // Spawn both coroutines on the single thread
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  
  // Hand control to the scheduler reactor
  RunUntilDone;
  writeln('All done');
end.
```

### Output

```
Server listening on port 28888
Client connecting...
Server accepted connection
Client connected
Server received: Hello from PXX Async!
Server shut down
Client received echo: Hello from PXX Async!
Client shut down
All done
```

---

## Next

- [Networking (HTTP / HTTPS)](./networking.md)
- [JSON processing](./json.md)
- [Back to the standard library reference](./index.md)
