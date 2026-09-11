# z486_MiSTer, native VGA output fork

This is a fork of [nand2mario/z486_MiSTer](https://github.com/nand2mario/z486_MiSTer).
The changes were written by an AI (Claude); the goals came from the repository owner,
who tested every build on real hardware. It makes the MiSTer analog output drive
a PC VGA CRT monitor with the core's own raster instead of the HDMI scaler: 31.5 kHz lines at the mode's
real refresh rate (70 Hz for text and mode 13h, 60 Hz for 640x480), the real dot
clocks, the sync polarity a VGA card uses, and the picture placed after hsync
where a real card puts it, so one monitor adjustment fits every DOS mode.
The SVGA framebuffer modes (256-colour, 15/16-bit and 24-bit) are rendered
natively as well, so the analog port never hands over to the scaler.

The changes are on branch `native-vga`; `main` tracks upstream. Experiments,
including a parked real dot-clock PLL, are on `exp/*` branches. The rbf files
of every build made along the way, with a description of each, are in
[`builds/`](builds/BUILDS.md). See "Analog VGA output" below for the details
and the MiSTer.ini settings.
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

The analog VGA port always carries the core's own raster: the real 25.175 and
28.322 MHz dot clocks (tripled for the 24bpp mode), 31.5 kHz lines at 70 Hz
(mode 13h, text) or 60 Hz (640x480), the sync polarity a VGA card uses
(400-line modes H-/V+, 350-line H+/V-, 480-line H-/V-), and the picture placed
after hsync where a real card puts it, so one monitor preset fits every DOS
mode. The SVGA framebuffer modes (8, 16 and 24bpp) are fetched from the
framebuffer line by line and shown the same way. This is the signal a PC CRT
monitor expects; 15 kHz TVs cannot sync to it. There is no OSD switch for it:
the HDMI output is always the scaler, the analog output always the raster, and
the exceptions are MiSTer.ini settings handled by the framework:

- A PC monitor needs separate syncs: `composite_sync=0`.
- HDMI at a fixed 60 Hz for displays that dislike 70 Hz: `vsync_adjust=0`
  (the MiSTer default). The 70 Hz raster is frame-converted by the scaler; the
  analog output is unaffected.
- The scaler picture on the analog port instead of the raster (a 15 kHz TV, or
  a VGA monitor that should show the HDMI mode): `vga_scaler=1`, together with a
  `video_mode` the display accepts. Example for a 15 kHz TV that takes NTSC
  timing (720x240 at 60 Hz, the 13.5 MHz "SD" pixel clock the HDMI transmitter
  supports; untested at the time of writing):

  ```ini
  [z486]
  vga_scaler=1
  vsync_adjust=0
  video_mode=720,16,62,60,240,4,3,15,13500
  ```

- A DAC on the HDMI connector instead of the analog board: `direct_video=1`.
  The framework routes the same raster to the HDMI pins (the sync polarity is
  then the framework's normalised one).

The `Border` option shows or hides the overscan border on both outputs (the
framework blanks the analog picture with the same signal the scaler crops to).
`forced_scandoubler` has no effect: the raster is never below 31 kHz.

The emulated card identifies itself
to chip detectors as an ET4000AX (port 3CB reads FF and writes to it are ignored), so SciTech
UniVBE / Display Doctor 5.3a and later install and provide VBE 2.0 (banked). Its
RAMDAC now has the hidden command register of a HiColor DAC (unlocked by four
reads of 3C6h), so the 15-bit or 16-bit pixel format of the hi-colour modes is
whatever the BIOS or the driver programmed there, as on a real card; the stock
`16/24bit mode` and `16bit format` options are gone. The pel mask is applied to
the pixels like a real DAC does.

Development and compatibility discussion is available in the
[MiSTer FPGA forum thread](https://misterfpga.org/viewtopic.php?t=10667).
