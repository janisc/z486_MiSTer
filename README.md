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
  SVGA modes rendered through the MiSTer framebuffer have no real-time raster
  and fall back to the scaler automatically. The 60 Hz VSync option is ignored
  in this mode because its 26.9 kHz line rate is below the range of VGA
  monitors. Sync polarity is always negative on both lines (a framework
  property), which multisync monitors accept.

Development and compatibility discussion is available in the
[MiSTer FPGA forum thread](https://misterfpga.org/viewtopic.php?t=10667).
