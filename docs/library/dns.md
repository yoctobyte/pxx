---
title: DNS
order: 51
---

# DNS: turning names into addresses

The `dns` unit resolves a host name to its IPv4 or IPv6 addresses. By default
it does the work itself: it reads `/etc/hosts` and `/etc/resolv.conf` and
asks the configured nameserver over UDP, falling back to TCP when an answer
is too long, so a program needs no C library. The `http` unit uses it for
every URL with a host name. `dns_async` does the same inside the coroutine
scheduler, and `dns_libc` is an optional backend that asks the C library
instead.

Every example here was built with pin v451 (compiler sha256 `d9b7226769cc`)
through `./pxx` and run on Linux x86-64 on 2026-09-29, a machine whose
`/etc/resolv.conf` points at systemd-resolved. Python's
`socket.getaddrinfo` was the reference.

## Resolving a name

`DnsResolveHost(name, ips, count)` returns 0 and fills `ips[0..count-1]`,
or returns an error code. Each address is a `LongWord` in host byte order,
so `127.0.0.1` is `$7F000001`. A positive code is the DNS server's answer
code (3 means the name does not exist), and a negative one is a local failure
such as a timeout; `DNS_ERR_NOCONFIG` (-4) means there is no nameserver in
`/etc/resolv.conf` and no match in `/etc/hosts`. PXX never falls back to a
public resolver on its own.

```pascal
program dns_demo;
uses dns, dns_wire_core, sysutils;

function IpStr(ip: LongWord): string;
begin
  IpStr := IntToStr((ip shr 24) and 255) + '.' + IntToStr((ip shr 16) and 255) + '.' +
           IntToStr((ip shr 8) and 255) + '.' + IntToStr(ip and 255);
end;

var
  ips: TDnsIpv4Array;
  n, i, k, rc: Integer;
begin
  for k := 1 to ParamCount do
  begin
    rc := DnsResolveHost(ParamStr(k), ips, n);
    write(ParamStr(k), ':');
    if rc <> 0 then
      write(' not resolved (code ', rc, ')')
    else
      for i := 0 to n - 1 do write(' ', IpStr(ips[i]));
    writeln;
  end;
end.
```

```sh
./pxx dns_demo.pas dns_demo
./dns_demo localhost example.com no-such-name.invalid
```

```text
localhost: 127.0.0.1
example.com: 104.20.23.154 172.66.147.243
no-such-name.invalid: not resolved (code 3)
```

Python's `getaddrinfo` gave the same addresses for these names, and for
`github.com`. The addresses you see depend on your network and on the day,
and their order is the order the server sent them in.

`DnsResolveHost6(name, ips6, count)` is the IPv6 form. Each entry of a
`TDnsIpv6Array` is 16 bytes, most significant first. For `example.com` it
returned the same two addresses as `getaddrinfo(..., AF_INET6)`, and for the
literal `::1` it returns `::1` without asking the network.

The resolver follows `/etc/resolv.conf`'s `search` and `ndots` settings,
tries each nameserver in turn, and follows CNAME aliases. Answers are cached
for the lifetime the server gave them. The cache is on by default,
`DnsCacheSetEnabled(False)` turns it off, and `DnsCacheFlush` empties it. It
is shared by the whole process and not safe for threads, so a program that
resolves names from several threads should turn it off.

`DnsResolveService('https', 'tcp', port)` looks a service name up in
`/etc/services` and sets `port` to 443, as Python's `getservbyname` does. A
numeric string is returned as a number, and an unknown name gives
`DNS_ERR_NOCONFIG`.

## Choosing a backend

The same `DnsResolveHost` call can be answered in three ways, chosen when
you build the program:

| Build flags | Who answers | Needs |
| --- | --- | --- |
| none (the default) | PXX's own resolver: `/etc/hosts`, then the nameservers in `/etc/resolv.conf` | nothing |
| `-dPXX_DNS_RESOLVED` | systemd-resolved, asked directly | systemd-resolved running |
| `-dPXX_DNS_LIBC -dPXX_DYNLIB_LIBC` | the C library's `getaddrinfo` | glibc at run time; the program then links `libc.so.6` |

Use the C library backend when names come from somewhere other than DNS:
`/etc/nsswitch.conf` modules such as mDNS (`.local` names), LDAP or a VPN's
name service. Only that backend sees them. `-dPXX_DNS_LIBC` alone stops the
build and names the missing flag: "PXX_DNS_LIBC needs the runtime loader
too: add -dPXX_DYNLIB_LIBC". Choosing two backends at once is a compile
error too.

`dns_demo` above, built each of the three ways, printed the same addresses
for the same names. The systemd-resolved build listed `example.com`'s two
addresses in the other order.

On the ESP32 (ESP-IDF builds) the default is different: names go to lwIP's
resolver, which holds the nameservers the network's DHCP server handed out.
`examples/esp32/dns-c3` shows it.

## Resolving without blocking: dns_async

`DnsResolveHostAsync(name, ips, count)` and `DnsResolveHost6Async` take the
same arguments and give the same answers, but they are meant to be called
inside a coroutine (see [Async](./async.md)). While one waits for the
nameserver, the other coroutines run.

```pascal
program dns_async_demo;
uses scheduler, dns, dns_async, dns_wire_core, sysutils;

var
  names: array[0..1] of string = ('example.com', 'localhost');
  results: array[0..1] of string;
  ticks: Integer = 0;
  done: Integer = 0;

function IpStr(ip: LongWord): string;
begin
  IpStr := IntToStr((ip shr 24) and 255) + '.' + IntToStr((ip shr 16) and 255) + '.' +
           IntToStr((ip shr 8) and 255) + '.' + IntToStr(ip and 255);
end;

procedure Resolve(arg: Pointer);
var
  k, n, rc: Integer;
  ips: TDnsIpv4Array;
begin
  k := PtrInt(arg);
  rc := DnsResolveHostAsync(names[k], ips, n);
  if rc = 0 then results[k] := IpStr(ips[0]) + ' (' + IntToStr(n) + ' found)'
  else results[k] := 'code ' + IntToStr(rc);
  Inc(done);
end;

procedure Ticker(arg: Pointer);
begin
  while done < 2 do
  begin
    Inc(ticks);
    CoSleep(1);
  end;
end;

begin
  Spawn(@Resolve, Pointer(PtrInt(0)));
  Spawn(@Resolve, Pointer(PtrInt(1)));
  Spawn(@Ticker, nil);
  RunUntilDone;
  writeln(names[0], ': ', results[0]);
  writeln(names[1], ': ', results[1]);
  writeln('the ticker ran while they waited: ', ticks > 0);
end.
```

```text
example.com: 104.20.23.154 (2 found)
localhost: 127.0.0.1 (1 found)
the ticker ran while they waited: TRUE
```

`ips[0]` for `example.com` is either of its two addresses: on the next run
the server listed them the other way round.

**Wait with `CoSleep`, not a `CoYield` loop.** The scheduler checks the
network only when no coroutine is ready to run. A coroutine that loops on
`CoYield` is always ready, so the lookups never finish: with `CoYield` in
place of `CoSleep(1)` above, the program ran at full CPU for five minutes
and was stopped by hand. The waiting on sockets and timers is done with
epoll on x86-64 Linux; the unit's source says other targets fall back to
polling.
