{ SPDX-License-Identifier: 0BSD }
unit qemueth;
{ NilPy face of tools/esp_qemu_net/qemueth/qemueth.c:
    import 'qemueth.pas' as qemueth
    qemueth.up(20000)   # 0 = the interface has slirp's lease; host is 10.0.2.2 }
interface
function up(timeout_ms: Integer): Integer;
implementation
function pxx_qemu_eth_up(timeout_ms: Integer): Integer; cdecl; external;
function up(timeout_ms: Integer): Integer;
begin
  Result := pxx_qemu_eth_up(timeout_ms);
end;
end.
