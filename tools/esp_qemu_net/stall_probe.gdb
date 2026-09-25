# SPDX-License-Identifier: 0BSD
# Read when an ESP chip under QEMU goes silent with a gdbserver armed
# (tools/esp_qemu_mpy_net.sh MPYNET_GDB_PORT, tools/esp_qemu_urequests.sh
# UREQ_GDB_PORT). This file only DEFINES commands; the harness runs each line
# of stall_probe.steps as its own -ex, because a failing command aborts the
# rest of a sourced file but not the next -ex -- the first version lost every
# step after one bad symbol that way.
#
# Plain gdb CLI, no Python: Espressif's gdb is built per Python version and
# none matches this host's (3.14), so the unversioned binary is the no-Python
# one. A Python probe ran here once and printed nothing at all.
#
# Answers "what is it doing" (pc, backtrace, every FreeRTOS task and its saved
# pc), "has a HANDLE run out" (lwIP pcb lists, the socket table), and "is a
# received frame stuck in the emulated NIC" (openeth interrupt registers and rx
# ring: a descriptor with e=0 is a frame the driver has not taken while its rx
# task waits for a notification -- a lost interrupt, not a leak).
set pagination off
set print pretty off

define stall_pcbs
  set $p = $arg0
  set $n = 0
  while $p != 0 && $n < 1000
    if $n < 12
      printf "STALL-GDB   $arg0[%d] state=%d local_port=%d remote_port=%d\n", $n, $p->state, $p->local_port, $p->remote_port
    end
    set $p = $p->next
    set $n = $n + 1
  end
  printf "STALL-GDB list $arg0 len=%d\n", $n
end

define stall_sockets
  set $i = 0
  set $u = 0
  while $i < sizeof(sockets) / sizeof(sockets[0])
    if sockets[$i].conn != 0
      printf "STALL-GDB   socket[%d] conn=%p rcvevent=%d sendevent=%d errevent=%d\n", $i, sockets[$i].conn, sockets[$i].rcvevent, sockets[$i].sendevent, sockets[$i].errevent
      set $u = $u + 1
    end
    set $i = $i + 1
  end
  printf "STALL-GDB sockets used=%d of %d\n", $u, sizeof(sockets) / sizeof(sockets[0])
end

# base 0x600CD000; rx descriptors follow the (1) tx one; e is bit 15.
# CONFIG_ETH_OPENETH_DMA_{TX,RX}_BUFFER_NUM = 1, 4 (IDF defaults, as built).
define stall_openeth
  printf "STALL-GDB openeth moder=0x%x int_source=0x%x int_mask=0x%x\n", *(unsigned int *)0x600CD000, *(unsigned int *)0x600CD004, *(unsigned int *)0x600CD008
  set $i = 0
  while $i < 4
    set $f = *(unsigned short *)(0x600CD408 + 8 * $i)
    printf "STALL-GDB openeth rxdesc[%d] flags=0x%04x e=%d len=%d\n", $i, $f, ($f >> 15) & 1, *(unsigned short *)(0x600CD40A + 8 * $i)
    set $i = $i + 1
  end
end

# One FreeRTOS list: every task on it, with the pc saved in its frame (on
# riscv the first word at pxTopOfStack is mepc; on xtensa it is not, so read
# the name there and ignore the pc).
define stall_tasklist
  set $l = (List_t *) &($arg0)
  set $it = $l->xListEnd.pxNext
  set $n = 0
  while $it != (ListItem_t *) &$l->xListEnd && $n < 32
    set $t = (TCB_t *) $it->pvOwner
    printf "STALL-GDB   task $arg0 %s saved_pc=", $t->pcTaskName
    output/a *(void **) $t->pxTopOfStack
    printf "\n"
    set $it = $it->pxNext
    set $n = $n + 1
  end
end

define stall_ready
  set $pri = 0
  while $pri < sizeof(pxReadyTasksLists) / sizeof(pxReadyTasksLists[0])
    stall_tasklist pxReadyTasksLists[$pri]
    set $pri = $pri + 1
  end
end
