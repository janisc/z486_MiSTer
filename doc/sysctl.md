# CPU speed and a core/version-aware SYSCTL

The OSD offers Full, 56, 30, 15, 6, 5, 4 and 3 MHz-equivalent execution rates. The CPU and peripherals retain their physical clocks; a registered execution throttle limits CPU progress. These are not calibrated historical CPU models. Old OSD configurations retain their meanings: status bits 9:8 are unchanged, and formerly unused bit 10 extends the menu to eight choices.

The unmodified ao486 SYSCTL continues to select Full/56/30/15 and restore OSD ownership with `SYSCTL MENU`. It cannot parse the four new speeds. Do not pass `SYSCTL SYS 6` to the old binary: an unknown speed currently falls back to Full.

## Detection before extending the utility

Do not infer capabilities from CPUID, benchmark speed or the name of a BIOS. Identify the core **and capability ABI revision** through read-only I/O ports:

| Port | Byte | Meaning |
| --- | --- | --- |
| `888Ah` | `5Ah` (`Z`) | Core signature |
| `888Bh` | `34h` (`4`) | Core signature |
| `888Ch` | `38h` (`8`) | Core signature |
| `888Dh` | `36h` (`6`) | Core signature |
| `888Eh` | `01h` | Capability ABI revision 1 |
| `888Fh` | `FFh` | Supported speed selectors, one bit per selector |

These registers are implemented alongside the eight-speed OSD change. Earlier z486 releases and ao486 do not implement this signature. The revision describes this protocol, not a date-based project release; future compatible releases keep revision 1. An incompatible layout needs a new revision.

An updated utility should use byte reads to verify all four signature bytes, then require a supported ABI revision and speed-mask bit before writing an extended selector. Unknown signatures or unsupported revisions use the legacy four-speed interface only. Never probe by writing configuration registers. The all-ones value of an unimplemented port is not a positive detection.

## Backward-compatible control word

The write remains `OUTW 8888h, A100h | control`, low byte first. Writing the low byte stages it; writing `A1h` to `8889h` commits it. Other high bytes do not commit. Reads of `8888h` return the committed byte; `8889h` reads as `A1h`. Capability-port writes have no effect.

| Selector (`control[2:0]`) | Rate | Old ao486 encoding? |
| ---: | --- | --- |
| 0 | Full (`90` in legacy SYSCTL terminology) | Yes |
| 1 | 15 MHz | Yes |
| 2 | 30 MHz | Yes |
| 3 | 56 MHz | Yes |
| 4 | 6 MHz | No |
| 5 | 5 MHz | No |
| 6 | 4 MHz | No |
| 7 | 3 MHz | No |

Bit 7 selects software control; clearing it restores the OSD selection. Bits 4 and 5 remain the legacy L1/L2-disable fields, not extra speed bits or FPU controls. They are stored but currently ignored by z486; the OSD L1 switch is independent. Bits 3 and 6 are reserved and should be zero.

## Suggested SYSCTL changes (not yet implemented in the DOS utility)

1. Detect the signature, supported ABI revision and speed mask above.
2. Keep the existing ao486 argument syntax and four speed encodings.
3. Accept `6`, `5`, `4`, `3` (and their `MHz` forms) only when positively supported. Reject unsupported/unknown speeds instead of silently choosing Full.
4. Preserve `SYS`, `MENU`, `L1+/-` and `L2+/-` syntax. Do not misreport the z486 cache fields as functional until their implementation is added.
5. Show detected capabilities separately from the configured rate; do not claim a project release number based solely on the capability ABI. When bit 7 is clear, report "OSD controlled": the committed control byte does not reveal the OSD's current rate. "Full" is not necessarily 90 MHz.
6. Regression-test ao486, an older four-speed z486, this eight-speed revision, absent/all-ones signatures, and unknown future ABI revisions. On supported hardware, test all rates, live transitions and SYSCTL-to-OSD handoff.

## RTL regression commands

`make -C tests test-speed` checks the throttle at 50/65/85 MHz and exercises the control ABI through the real byte-sequential I/O adapter.

For a whole-system check, build `tests/obj_dir/sysctl_probe.img` with `make -C tests obj_dir/sysctl_probe.img`. Run the simulator with that floppy, `--headless --no-ide --floppy ../tests/obj_dir/sysctl_probe.img --end 150000000 --stop-on-text SYSCTL_PROBE_OK`. The boot sector checks the signature and ABI, runs all eight software-selected speeds and verifies BIOS timer IRQ progress, then tests legacy speed selection and return to OSD control. An explicit `--cpu-speed 6` or `--cpu-speed 3` also checks the low-speed OSD path from reset.
