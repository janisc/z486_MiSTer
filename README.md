# z486_MiSTer, native VGA output fork

This is a fork of [nand2mario/z486_MiSTer](https://github.com/nand2mario/z486_MiSTer).
The changes were written by an AI (Claude); the goals came from the repository owner,
who tested every build on real hardware. It adds an option to drive a PC VGA CRT monitor from the MiSTer analog output with
the core's own raster instead of the HDMI scaler: 31.5 kHz lines at the mode's
real refresh rate (70 Hz for text and mode 13h, 60 Hz for 640x480), the real dot
clocks, the sync polarity a VGA card uses, and the picture placed after hsync
where a real card puts it, so one monitor adjustment fits every DOS mode.
The 256-colour and hi-colour (15/16-bit) SVGA framebuffer modes are rendered
natively as well; the 24-bit framebuffer mode still falls back to the scaler.

The changes are on branch `native-vga`; `main` tracks upstream. Experiments,
including a parked real dot-clock PLL, are on `exp/*` branches. The rbf files
of every build made along the way, with a description of each, are in
[`builds/`](builds/BUILDS.md). See "Analog VGA output" below for the option.
Nothing here has been submitted upstream.

---

# z486 MiSTer core

z486_MiSTer is an experimental PC core for MiSTer built around the
[z486 CPU](https://github.com/nand2mario/z486), an 80486-class pipelined FPGA
CPU written in SystemVerilog. The processor combines a fast frontend and
hardwired implementations of common instructions with microcoded control for
complex x86 operations. It also includes experimental, incomplete x87 support
sufficient to run TurboQuake.

The core delivers roughly 486DX2-66-class performance. It runs the Doom
timedemo at 29.1 FPS at maximum detail, compared with 21.0 FPS on ao486 using
the same MiSTer setup.

The core uses MiSTer SDRAM for system memory and supports 16, 32, 64, or 128 MB
configurations. Video hardware provides VGA and ET4000-compatible SVGA modes.

## Trying It

z486_MiSTer requires an SDRAM module. The SDRAM XS-D v2.5 module has been
verified to work. It also requires MiSTer main `MiSTer_20260823` or newer;
run `Scripts` → `update` before installing the core.

Download the latest build from the
[releases page](https://github.com/nand2mario/z486_MiSTer/releases), then place
the files as follows:

- `z486_*.rbf` in `/media/fat/_Computer`
- [boot0.rom](verilator/boot0.rom), [boot1.rom](verilator/boot1.rom), and disk
  images (`.vhd`) in `/media/fat/games/Z486`

### Analog VGA output

`Audio & Video` -> `VGA Output` selects what the analog VGA port carries:

- `Scaler` (default): a copy of the HDMI scaler output, at the HDMI mode's
  resolution and refresh rate.
- `Native 31kHz`: the core's own VGA raster with the real 25.175/28.322 MHz dot
  clocks, i.e. 31.5 kHz lines at 70 Hz (mode 13h, text) or 60 Hz (640x480).
  This is the signal a PC CRT monitor expects. 15 kHz TVs cannot sync to it.
  The 8bpp SVGA framebuffer modes are fetched from the framebuffer line by line
  and shown natively; other framebuffer depths fall back to the scaler. In this mode the `VSync` and
  `Border` options are hidden: the raster always runs at its native refresh
  (the 60 Hz retiming would give a 26.9 kHz line rate, below the range of VGA
  monitors) and the real overscan border is always shown. The sync polarity
  follows the VGA Misc Output register like a real card (400-line modes H-/V+,
  350-line H+/V-, 480-line H-/V-), and the picture is placed after hsync where
  a real card puts it, so one monitor preset fits every DOS mode. Set
  `composite_sync=0` in MiSTer.ini for a PC monitor (separate H/V sync).

Independently of the output option, the emulated card now identifies itself
to chip detectors as an ET4000AX (port 3CB reads FF and writes to it are ignored), so SciTech
UniVBE / Display Doctor 5.3a and later install and provide VBE 2.0 (banked).

Development and compatibility discussion is available in the
[MiSTer FPGA forum thread](https://misterfpga.org/viewtopic.php?t=10667).
