# Gravis UltraSound on z486: how it is hosted

A technical note for anyone who wants the same in another z486 tree, the stock core included.
The user-facing side is in the README FAQ.

## Credit

The Gravis UltraSound here is xolod79's work: the GF1 chip model `gf1.v` and the register glue
come from the GUS branch of his ao486_MiSTer fork
(https://github.com/xolod79/ao486_MiSTer, commit `98374e4`; since merged into MiSTer-devel's
ao486). `src/soc/sound/gus/gf1.v` is his file, unchanged. What this tree adds is a different
way of giving the chip its sample memory, so that it fits a core whose SDRAM is taken.

## The problem

In ao486 the main memory is the HPS DDR3, and the GUS owns the SDRAM module for its megabyte of
sample memory, through a dedicated controller that answers within a few clocks. In z486 the
SDRAM is the main memory. The FPGA's block RAM is no way out either: the DE10-Nano build has
about 85 KB of it left, and a GUS needs 256 KB at the very least.

## The idea

The GF1 model is a single synchronous block on the system clock. Its own 9.8784 MHz chip clock
is not a clock in the FPGA sense: it is an input signal that the model samples, and all of the
chip's sequencing (the voice slots, the DRAM cycles) advances on the levels of that signal. The
wrapper generates it.

The model asks for sample memory at two fixed phases of the chip clock: one for the CPU side
(peek, poke, DMA) and one for the voice being played, the latter in every voice slot. It then
expects the data some phases later.

So the wrapper holds the chip clock from the moment the model raises its memory request until
the memory has answered, and delivers the transitions it withheld afterwards at a faster rate.
For the chip, the memory answers instantly. For the listener, the chip still makes its nominal
number of clock transitions per second, because none is lost, only postponed by a fraction of a
microsecond. The memory can then be anything with a request and an acknowledge: a shared port,
a slow bus, memory behind an arbiter.

In numbers, at 85 MHz: a chip clock level nominally lasts 4.3 system clocks. A level may be as
short as two system clocks while catching up (the model runs with shorter ones in ao486 at 30
MHz). One voice slot is sixteen chip clocks, about 138 system clocks, with one voice access and
at most one CPU access, so there is room to repay a memory latency of some tens of clocks per
slot. Longer stalls are carried over: up to 255 transitions (about 13 microseconds) are
remembered.

### One trap: accesses while the clock is held

While the chip clock is held, the model's phase signals stay as they are, and neighbouring phases
of its ring overlap by design. One such pair is the phase that ends a CPU access to the sample
memory and the phase of the voice's memory cycle, which follows it. Held there for as long as the
memory takes, the model answers a new CPU access to the DRAM port (3x7) with the end condition of
the previous one: a peek returns the previous byte and a poke is not written. With a DDR3 read of
a dozen clocks no CPU is fast enough to get there. With the port taken for a few hundred clocks
it happens once per video line: that is what the line fetcher of an SVGA framebuffer mode does
in this fork. Voice register accesses are not affected (the model latches their register number
and data before the overlap).

So the wrapper passes an I/O strobe on to the model only while the model is outside its memory
cycles (`dram_access` low) and holds the bus with `io_wait` until then. The access then starts
in the phase after the memory cycle, which is where the real chip would see it.

## The pieces

| File | Role |
|---|---|
| `src/soc/sound/gus/gf1.v` | xolod79's GF1 model, unchanged |
| `src/soc/sound/gus/gus.sv` | Wrapper: register glue as in ao486's `gus.v`, the chip clock generator with hold and repay, and the memory port |
| `src/soc/sound/gus/gus_ddr.sv` | The megabyte in the HPS DDR3: single 64-bit beats, the last word read is kept |
| `src/soc/sound/gus/gus_spram.v` | The small block RAM the model instantiates for its voice state (`spram`), in Verilog |
| `tests/tb_gus.sv`, `tests/gus_sim_prep.py` | Testbench, and a script that makes a simulation copy of `gf1.v` with all registers starting at zero |

### The memory port of `gus.sv`

```
mem_req    held, with everything below stable, until mem_ack
mem_we     write
mem_word   16-bit access: both bytes at mem_addr (even); otherwise one byte, taken from mem_wdata[7:0]
mem_addr   20 bits, byte address within the megabyte
mem_wdata  16 bits
mem_rdata  the 16-bit word that contains the addressed byte (low byte = even address), valid with mem_ack
mem_ack    one clock
```

This is the whole contract. Any memory that honours it will do. With `enable` low the wrapper
makes no requests at all.

### The DDR3 side

`gus_ddr.sv` maps byte `a` of the megabyte to the 64-bit word at `BASE + a[19:3]`, byte lane
`a[2:0]`. `BASE` is word address `{4'h3, 8'hE0, 17'd0}`, byte address 3E00_0000h, below the SVGA
framebuffer at 3F80_0000h. Requests are registered when a transfer starts, so the model's
address logic is not on the port's paths. Reads and writes are held until the port accepts them
(Avalon-MM waitrequest). The word last read is kept and written through, so repeated reads
within the same eight bytes, which is what idle voices do, cost no bus cycle.

In this fork the DDR3 port already had two masters, the CPU's SVGA aperture path in
`main_memory` and the line fetcher of the native video output. The GUS is the third. The
fetcher wins while it owns the port, then the GUS for one beat, then `main_memory`; the GUS only
starts when nothing is in flight, and `main_memory` sees busy while the GUS is active.

### What else changed

- `src/iobus_adapter.sv`: an `io_wait` input. The GF1 stretches some I/O cycles (it serves a
  peek or a voice register read at the right phase of its clock), and the adapter had no way to
  wait. The byte's wait state is now held while `io_wait` is high. Tied to zero without the GUS.
- `src/system.sv`: registered select for 240h-24Fh and 340h-34Fh, the read data mux, DMA
  channel 7 (the controller had the channel, unconnected), `interrupt[7]`, the DDR3 mux, the two
  instances in a generate block under the `ENABLE_GUS` parameter.
- `z486_mister.sv`: OSD option `Gravis UltraSound` (status[51], default Off), the GUS added to
  the audio mix, `ENABLE_GUS(1'b1)`.

Resources as in ao486: `ULTRASND=240,7,7,7,7`. The Sound Blaster stays at 220h, IRQ 5, DMA 1/5.

## Doing the same in the stock z486

The stock core has one DDR3 master after boot, the SVGA aperture path of `main_memory`. To add
the GUS there:

1. Take the four files of `src/soc/sound/gus/` and the `io_wait` change to `iobus_adapter.sv`.
2. Wire `gus` and `gus_ddr` in `system.sv` as here, with a two-way mux on the DDR3 port instead
   of the three-way one: the GUS when `gus_active`, otherwise `main_memory`; `start_ok` is "no
   `main_memory` transfer in flight", and `main_memory` sees busy while `gus_active`.
3. `main_memory`'s aperture read must hold its request until the port accepts it. In the stock
   core it samples busy in one cycle and pulses the read in the next, which loses the read when
   another master, or the bridge itself, makes the port busy in between. This fork fixed that
   when it added its second master; the same fix is in upstream pull request #97.
4. Add the OSD option, the mix term and `ENABLE_GUS` in the top level.

Nothing in the GUS path depends on this fork's video work.

## Cost and timing (DE10-Nano, Quartus 17.1, 85 MHz)

| | without GUS | with GUS |
|---|---|---|
| ALMs | 38,034 (91 %) | 39,276 (94 %) |
| M10K blocks | 485 | 489 |
| DSP blocks | 41 | 42 |

The GF1 model alone synthesises to about 2,800 logic cells. The worst path inside the GUS logic
misses the 85 MHz period by about 1.2 ns at the slow corner: from the chip clock register into
the model's audio accumulators, a path the model has in ao486 as well, there against a 90 MHz
clock. The core's CPU paths miss by several nanoseconds in every build, with or without the GUS.

## What was tested

Simulation (`tests/tb_gus.sv`, Icarus Verilog), against a memory model with random waitrequest
(0 to 60 %) and random read latency (1 to 40 clocks):

- pokes and peeks of twelve addresses across the megabyte read back correctly, and the bytes sit
  where the chip's address says;
- a 16-word DMA upload on a 16-bit channel completes with the terminal count interrupt and the
  right bytes;
- the chip clock makes 19,757,985 transitions per second against a nominal 19,756,800 while the
  memory is slow;
- accesses in quick succession (a tight read-back, a poke followed at once by a peek, a tight
  upload) with fourteen voices playing and with the port taken away for 600 of every 2700 clocks,
  and a 200-word DMA upload on that busy port: no error. Without the wait described under "One
  trap" the first three fail.

Hardware (DE10-Nano, the Future Crew demo disk with Gravis's software and `ULTRASND=240,7,7,7,7`):

- a small test program reads the four 256 KB banks back distinct (1 MB), uploads 32 words over
  DMA channel 7 with every byte right, and receives the interrupt on IRQ 7;
- Second Reality with its Gravis UltraSound option plays through, with sound;
- Gravis's ULTRAMOD plays; PLAYMIDI and PLAYFILE behave as on the ao486 GUS core;
- the card together with an SVGA framebuffer mode: a stress program runs fourteen voices from
  different places of the card's memory, sets VBE mode 101h and for twenty seconds reads picture
  memory, card memory and voice registers back while the picture is shown. No mismatch (15 million
  picture bytes, 2 to 6 million card bytes per run), and the picture is bit-identical with and
  without the voices. A 4 KB DMA upload is correct with the SVGA mode on screen. This is the test
  that found the trap: before the wait was added, about 1.6 % of the card memory reads were wrong
  there.

## Known gaps

- The resources are fixed: 240h, IRQ 7, DMA 7. ao486 moves the GUS to IRQ 5 when the Sound
  Blaster is switched to IRQ 7; this tree does not yet.
- No recording: the card's inputs are not connected.
- The GUS audio crosses from the system clock to the audio clock like the other sound sources
  of the core, without a synchroniser.
- The voices read memory in every slot. With the single kept word, a busy tune costs on the
  order of a million single-beat DDR3 reads per second. A small direct-mapped cache in
  `gus_ddr.sv` would cut that several times.
- No game that uses an SVGA mode and the GUS at the same time has been tried; the stress program
  stands in for one.
