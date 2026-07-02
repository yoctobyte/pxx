{ SPDX-License-Identifier: Zlib }
unit tls13_ktls;
{ Linux kernel-TLS (kTLS) offload for TLS 1.3 (RFC 8446 M7 of
  feature-tls13-from-scratch). After our Pascal handshake derives the application
  traffic keys, install them into the kernel so bulk app data is encrypted/
  decrypted by the kernel and plain read()/write() carry plaintext.

  Optional and Linux-only: needs the `tls` kernel module (and on most systems
  loading it needs privilege). Every call returns False when unavailable — the
  Pascal record layer (lib/rtl/tls13_record) is always the baseline. }

interface

{ Switch the socket's upper-layer protocol to "tls" (setsockopt TCP_ULP). False
  if the kTLS module isn't available. Call once, after the handshake. }
function KtlsEnable(fd: Integer): Boolean;

{ Install one direction's AES-128-GCM TLS 1.3 traffic key. `tx`=True for the
  send side (our app key), False for the receive side (server app key). iv is the
  12-byte traffic iv, key the 16-byte traffic key. rec_seq starts at 0. }
function KtlsSetAesGcm128(fd: Integer; tx: Boolean; const key, iv: AnsiString): Boolean;

implementation

uses platform;

const
  SOL_TCP = 6;
  TCP_ULP = 31;
  SOL_TLS = 282;
  TLS_TX  = 1;
  TLS_RX  = 2;

function KtlsEnable(fd: Integer): Boolean;
var ulp: AnsiString;
begin
  ulp := 'tls';
  KtlsEnable := PalSetSockOpt(fd, SOL_TCP, TCP_ULP, @ulp[1], 3) = 0;
end;

function KtlsSetAesGcm128(fd: Integer; tx: Boolean; const key, iv: AnsiString): Boolean;
var ci: AnsiString; i, dir: Integer;
begin
  KtlsSetAesGcm128 := False;
  if (Length(key) < 16) or (Length(iv) < 12) then Exit;
  { struct tls12_crypto_info_aes_gcm_128 (40 bytes), native byte order:
    u16 version | u16 cipher_type | iv[8] | key[16] | salt[4] | rec_seq[8] }
  ci := Chr($04) + Chr($03)              { TLS_1_3_VERSION = 0x0304 (LE) }
      + Chr($33) + Chr($00);             { TLS_CIPHER_AES_GCM_128 = 51 (LE) }
  ci := ci + Copy(iv, 5, 8);             { iv  = last 8 bytes of the 12-byte iv }
  ci := ci + Copy(key, 1, 16);           { key = 16-byte traffic key }
  ci := ci + Copy(iv, 1, 4);             { salt = first 4 bytes of the iv }
  for i := 1 to 8 do ci := ci + Chr(0);  { rec_seq = 0 }
  if tx then dir := TLS_TX else dir := TLS_RX;
  KtlsSetAesGcm128 := PalSetSockOpt(fd, SOL_TLS, dir, @ci[1], Length(ci)) = 0;
end;

end.
