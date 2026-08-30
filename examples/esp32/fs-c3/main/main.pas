{ SPDX-License-Identifier: 0BSD }
program FsProbe;
{ PROBE: does ESP-IDF VFS file I/O actually WORK under Espressif QEMU?

  feature-pal-esp-posix-fd-semantics was blocked twice on "no qemu/IDF runner".
  There is one now. But GPIO turned out inert and ADC hangs, so VFS must be
  MEASURED rather than assumed from CLAUDE.md's "sockets and basic VFS file I/O
  are what work" -- that sentence is about the PAL's refusal list, not about
  what QEMU emulates.

  Exercises exactly the surface the ESP PAL backend uses: fopen/fwrite/fread/
  fseek/fclose over a FAT-on-flash mount. If this works, the PAL's file path is
  reachable under QEMU and the ticket's acceptance is partly attainable here. }

uses platform;

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
function esp_vfs_fat_spiflash_mount_rw_wl(base: PChar; label_: PChar;
                                          cfg: Pointer; wl: Pointer): Integer; external;
function remove(path: PChar): Integer; external;

type
  { esp_vfs_fat_mount_config_t, ILP32: bool+pad, int, size_t, bool, bool+pad }
  TFatCfg = record
    format_if_mount_failed: Byte;
    p0, p1, p2: Byte;
    max_files: Integer;
    allocation_unit_size: Integer;
    disk_status_check_enable: Byte;
    use_one_fat: Byte;
    p3, p4: Byte;
  end;

var
  cfg: TFatCfg;
  wl: Integer;
  h: Integer;
  rc, n, i, bad: Integer;
  buf: array[0..31] of Char;
  base: array[0..15] of Char = ('/','s','p','i','f','l','a','s','h',#0,#0,#0,#0,#0,#0,#0);
  plabel: array[0..7] of Char = ('s','t','o','r','a','g','e',#0);
  path: array[0..23] of Char = ('/','s','p','i','f','l','a','s','h','/','t','.','t','x','t',#0,
                                #0,#0,#0,#0,#0,#0,#0,#0);
  msg: array[0..7] of Char = ('P','X','X','-','V','F','S',#0);
  missing: array[0..23] of Char = ('/','s','p','i','f','l','a','s','h','/','n','o','p','e',#0,
                                   #0,#0,#0,#0,#0,#0,#0,#0,#0);
begin
  cfg.format_if_mount_failed := 1;
  cfg.p0 := 0; cfg.p1 := 0; cfg.p2 := 0;
  cfg.max_files := 4;
  cfg.allocation_unit_size := 0;
  cfg.disk_status_check_enable := 0;
  cfg.use_one_fat := 0;
  cfg.p3 := 0; cfg.p4 := 0;
  wl := -1;

  rc := esp_vfs_fat_spiflash_mount_rw_wl(@base[0], @plabel[0], @cfg, @wl);
  esp_rom_printf('PROBE: fat_mount rc=%d'#10, rc);
  if rc <> 0 then
  begin
    esp_rom_printf('PROBE: VERDICT vfs-mount-failed'#10, 0);
    while True do vTaskDelay(1000);
  end;

  rc := remove(@path[0]);   { ignore result }

  { ---- pin the CURRENT ESP PAL semantics, on target, over a real VFS ---- }

  h := PalOpen(@path[0], PAL_OPEN_CREATE or PAL_OPEN_RDWR, 420);
  if h > 0 then esp_rom_printf('PAL: open-create ok'#10, 0)
           else esp_rom_printf('PAL: open-create FAILED rc=%d'#10, h);

  n := PalWrite(h, @msg[0], 7);
  esp_rom_printf('PAL: write n=%d (want 7)'#10, n);
  rc := PalSeek(h, 0, PAL_SEEK_SET);
  esp_rom_printf('PAL: seek rc=%d'#10, rc);
  for i := 0 to 31 do buf[i] := #0;
  n := PalRead(h, @buf[0], 7);
  esp_rom_printf('PAL: read n=%d (want 7)'#10, n);
  bad := 0;
  for i := 0 to 6 do if buf[i] <> msg[i] then bad := bad + 1;
  esp_rom_printf('PAL: content-mismatches=%d'#10, bad);
  rc := PalClose(h);
  esp_rom_printf('PAL: close rc=%d'#10, rc);

  { The two gaps this ticket names, pinned as they behave TODAY. }
  rc := PalOpen(@path[0], PAL_OPEN_CREATE or PAL_OPEN_EXCL or PAL_OPEN_RDWR, 420);
  esp_rom_printf('PAL: open-EXCL=%d (today: -38 unsupported)'#10, rc);

  rc := PalOpen(@missing[0], PAL_OPEN_READ, 0);
  esp_rom_printf('PAL: open-missing=%d (today: -1, errno collapsed)'#10, rc);

  if (n = 7) and (bad = 0) then
    esp_rom_printf('PAL: VERDICT esp-pal-file-io-WORKS'#10, 0)
  else
    esp_rom_printf('PAL: VERDICT esp-pal-file-io-broken'#10, 0);

  while True do vTaskDelay(1000);
end.
