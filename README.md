# z486_MiSTer, native VGA output fork

This is a fork of [nand2mario/z486_MiSTer](https://github.com/nand2mario/z486_MiSTer).
The changes were written by an AI (Claude); the goals came from the repository owner,
who tested every build on real hardware. It makes the MiSTer analog output drive a
PC VGA CRT monitor with the core's own raster instead of the HDMI scaler: 31.5 kHz
lines at the mode's real refresh rate, the real dot clocks, the sync polarity a VGA
card uses, and the picture placed after hsync where a real card puts it, so one
monitor adjustment fits every DOS mode. The SVGA framebuffer modes (256-colour,
15/16-bit and 24-bit) are rendered natively as well, so the analog port never hands
over to the scaler.

The changes are on branch `native-vga`; `main` tracks upstream. Experiments,
including a parked real dot-clock PLL, are on `exp/*` branches. The rbf files of
every build made along the way, with a description of each, are in
[`builds/`](builds/BUILDS.md). Nothing here has been submitted upstream. The rbf of
the current release is attached to the [Releases page](../../releases). The upstream
README, unchanged, follows at the end of this file after the thanks.

## FAQ

**Where do I get the core and how do I install it?**
Download `z486nv_<date>.rbf` from the [Releases page](../../releases) and copy it to
`/media/fat/_Computer`, next to the stock core if you keep one. Everything else is
the stock core's: the boot ROMs and disk images in `/media/fat/games/Z486`, the SDRAM
module, the MiSTer main version (see the upstream README at the end). Every build
made along the way, with notes, is in [`builds/`](builds/BUILDS.md).

**I use a VGA monitor. What do I need?**
Connect it to the analog output and make sure MiSTer.ini has `composite_sync=0`.
Nothing else. The core puts real VGA timing on that port, 31.5 kHz with separate
horizontal and vertical sync, which is what any VGA monitor from 1987 on accepts;
the framework's composite sync option would merge the two syncs, and a PC monitor
does not take that. There is no multisync requirement and no OSD setting.

**Can I use HDMI instead of, or together with, the VGA output?**
Yes, both are always on. HDMI carries the scaler picture as on every core, the
analog port the raster. The one catch is that the raster now has its real refresh
rate: 70 Hz in the 400-line DOS modes, 54 Hz in the BIOS's 800x600 modes (a 36 MHz
clock, as on a real card of that class). The stock core's VSync option retimed
everything to 60 Hz for HDMI; that option is gone. With `vsync_adjust=2` the HDMI
output follows the real rate, and some TVs and monitors refuse 70 Hz. If HDMI stays
blank, set `vsync_adjust=0` (the MiSTer default) or `1`; the scaler then
frame-converts to 60 Hz. The analog output is not affected. A different
thing is an HDMI picture that goes black while the OSD still draws: that was a bug in
the framework's scaler after many video-mode changes, fixed upstream in August 2026 and
carried in this core since release 9b (`z486nv_20260913b`).

**The stock core has a VSync option with 60 Hz and Variable. It is gone here and my
HDMI display shows no picture. Why, and what can I do?**
That option retimed the core's own dot clock to make the raster 60 Hz. That gives
a 27 kHz line rate, which no VGA monitor accepts, so it has no place when the
analog port carries the real timing. `vsync_adjust=0` in MiSTer.ini gives the HDMI
output the same fixed 60 Hz, by frame conversion in the scaler, and the CRT keeps
its real 70 Hz.

**I want to play DOS games on a 15 kHz TV or arcade monitor. How?**
Set `Analog output` to `TV 15kHz` in the OSD's Audio & Video page, and keep
`composite_sync=1` in MiSTer.ini if the set wants sync on the H line, as SCART sets
do. The core then makes a real 15 kHz raster out of the VGA picture: every VGA line
lasts 31.8 us whatever the mode, so one line played out over the time of two is a
15.73 kHz line, and one line in two is shown. The 320x200, 320x240 and EGA 200-line
modes, which VGA scans twice, come out complete as true 240p: Doom, the LucasArts and
Sierra adventures, Keen. Text and the 640x400 and 640x480 modes lose every other row
and are readable rather than pretty. With `TV picture` at `Native size` nothing is
scaled: 200 rows are 200 TV lines, a little less than a console's 240, so there is a
black band above and below the picture. `Fill` shows every fifth scanline twice, so
200 rows become 240 lines and fill the screen, the same 1.2 stretch the scaler gives
but with sharp lines; the SVGA framebuffer modes are left at native size. The picture
is centred in the standard 240-line window; sets differ in their own centring, so
`TV H-position` and `TV V-position` nudge it in steps of half a microsecond and four
lines. The TV options only appear in the menu while the analog output is set to TV. With `Fill` the outermost lines fall into the set's overscan
as they do with a console. `TV hi-res modes` decides what happens to text and the
640x400 and 640x480 modes: `Line drop` shows every other row progressively,
`Interlace` shows all of them as two fields, the way a TV shows 480i, sharp but with
the flicker that goes with it; the 200-row modes stay 240p either way. HDMI keeps the
normal 31 kHz picture at the same time (with `Fill` it shows the stretched frame too).

VGA's 200- and 400-line modes run at 70 Hz and consumer TVs lock to 50 or 60 Hz only.
With the default `TV frame rate` of `60 Hz` the core pads those frames to 60 Hz;
software that paces itself on the vertical retrace then runs at 60 instead of 70, as
it did with the stock core's old VSync 60Hz option. Arcade monitors and PVMs that take
70 Hz can use `Native`. Modes the set cannot show, 800x600 and up and UniVBE's 35 Hz
modes, turn the screen dark green until the software returns to a supported mode; the
OSD still works on it. A few characters cut off at the left and right are the set's
overscan, as with any console.

The scaler is the alternative if you want the screen filled: it scales the picture to
240 lines and frame-converts 70 Hz to 60 with a dropped frame now and then:

```ini
[z486]
vga_scaler=1
vsync_adjust=0
video_mode=1440,32,124,120,240,4,3,15,27000
```

Then set Aspect ratio to Full Screen in the OSD's video settings, otherwise the
framework fits the 4:3 picture into the wide frame as a narrow strip. The pixel
clock is 27 MHz with 1440 dots rather than 13.5 MHz with 720 because the HDMI PLL
cannot synthesise 13.5 MHz exactly; at 27 MHz it is exact and the TV sees identical
sync.

**I use a DAC on the HDMI connector (direct video). What do I need?**
`direct_video=1` in that ini, as for any core; the framework routes the raster to
the HDMI pins. For a VGA monitor on the DAC add `composite_sync=0`. If the same
ini serves other cores, `forced_scandoubler=1` keeps them at 31 kHz too; this core
ignores it, its raster is never below 31 kHz.

**Do I need UniVBE?**
Not for games that use the BIOS's VBE 1.2 modes, which includes the 15/16/24-bit
hi-colour ones. Games that require VBE 2.0 need SciTech UniVBE or Display Doctor
5.3a or later; those identify the card as an ET4000 and install. If you install a
new core build over an old UniVBE setup, run UVCONFIG once: it caches what it
detected, including the RAMDAC.

**Some settings disappeared from the Audio & Video menu. Why?**
Compared with the stock core, three options are gone: `VSync`, which retimed the
raster to 60 Hz and has no place when the analog port carries the real timing, and
`16/24bit mode` and `16bit format`, which asked the user to guess the pixel format
of the hi-colour modes. The emulated RAMDAC now has the command register
the BIOS and the Windows driver program, so the format is whatever they set, as on
a real card. `Border` stays and applies to both outputs. The aim was to remove
combinations that did not make sense, not functionality; if something you need is
missing, open an issue.

**Which games and demos have been tested?**
On the CRT: DOS text modes, Doom, Commander Keen (EGA), SimCity 2000 and Panzer
General (640x480x256), Steel Panthers, Indiana Jones Desktop Adventures under
Windows 3.1 (640x480 hi-colour), Scorched Earth 1.5 at 1024x768 (256 colours), the demos Copper (per-line raster tricks) and
Legend, and SciTech's VBETEST in every colour depth including 16-page 320x200
hi-colour page flipping. The test tools (register dumps, retrace counters, VRAM
banking, a resident INT 10h logger) and the debug floppy are described in
[`builds/BUILDS.md`](builds/BUILDS.md).

**Which modes do not work on the CRT?**
A full VBETEST sweep of every VBE mode found these limits. 1280x1024 loses the CRT: this
BIOS runs it interlaced from a 36 MHz clock, below 30 kHz (HDMI shows it). 1024x768 in 8 and
15/16 bit works at 60 Hz (48 kHz): the core gives the ET4000's clock index 2 the 65 MHz a
real 1024x768 board has, for these framebuffer modes only. At that rate the pixel widths
alternate between one and two clocks of the core's 85 MHz, which shows as stair steps on
one-pixel lines and not at all on game graphics (Scorched Earth at 1024x768). The 16-colour
modes above 64 KB per plane, 1024x768 and 1280x1024, stay at 32.5 MHz (below 30 kHz) and
also repeat the picture vertically: the legacy VGA memory is four 64 KB planes, as in stock
and ao486. 800x600 in 24 bit is beyond the analog port at the core's 85 MHz. UniVBE's own
640x350 and 640x400 15-bit modes program a halved dot clock and run at 15.7 kHz; the BIOS's
15-bit modes are fine. Everything at 320x200, 640x400, 640x480 and 800x600 in 8, 15 and 16
bit, and 640x480 in 24 bit, works on both outputs.

**Will this go into z486 or ao486?**
Maybe. This started as an experiment and we are happy with the result, but more
testing by more people is needed first. Do not wait for pull requests: the code is
here under the same terms as the files it lives in (the ao486 BSD licence for the
video code, Apache 2.0 for the z486 CPU), so if you want it somewhere, take it
there.

The builds are named `z486nv_<date>` (nv for native video) so they sit next to the
stock `z486_<date>.rbf` in `_Computer`; load whichever you want. Both report the same
core name to MiSTer, so they share `config/Z486.CFG` (OSD settings, boot order, the
mounted images), the `games/Z486` folder and the `[z486]` section of MiSTer.ini. The
OSD's bottom line shows `nv-yymmdd` on this fork and nothing on the stock core, which
is how you tell which one is loaded.

## How it works

The analog VGA port always carries the core's own raster: the real 25.175 and
28.322 MHz dot clocks (tripled for the 24bpp mode), 31.5 kHz lines at 70 Hz
(mode 13h, text) or 60 Hz (640x480), the sync polarity a VGA card uses
(400-line modes H-/V+, 350-line H+/V-, 480-line H-/V-), and the picture placed
after hsync where a real card puts it. The SVGA framebuffer modes (8, 16 and
24bpp) are fetched from the DDR3 framebuffer line by line and shown the same way,
so the port never hands over to the scaler. There is no OSD switch: the HDMI
output is always the scaler, the analog output always the raster, and the
exceptions in the FAQ are MiSTer.ini settings handled by the framework. The
`Border` option shows or hides the overscan border on both outputs (the framework
blanks the analog picture with the same signal the scaler crops to).

The emulated card identifies itself to chip detectors as an ET4000AX: port 3CB
implements only the bank bit for the second megabyte and reads back 11h for the
usual 33h probe, so SciTech UniVBE / Display Doctor 5.3a and later install and
provide VBE 2.0 (banked), while the 2 MB the BIOS reports are really usable (VBE
modes above 1 MB, the sixteen pages of 320x200 hi-colour). The RAMDAC is modelled
on the Sierra SC15025 HiColor DAC the Tseng BIOS probes for (hidden command
register behind four reads of 3C6h, extended registers), so the 15-bit or 16-bit
pixel format of the hi-colour modes is whatever the BIOS or the driver programmed.
The pel mask is applied to the pixels like a real DAC does. The 320x200 hi-colour
modes (halved dot clock, like mode 13h) are shown natively too, and a display-start
change takes effect at the next vertical retrace as on a real CRTC, so page
flipping is tear-free on the analog output. SciTech's VBETEST (in the SDD 5.3a
package) exercises all of this and is the fork's regression suite for the SVGA
framebuffer modes.

## Thanks

This fork exists because of other people's work:

- **nand2mario** for the z486 CPU and the z486_MiSTer core, the platform all of this
  runs on, and for keeping it moving.
- **Aleksander Osman** for ao486, whose VGA and ET4000 model (`src/soc/vga.v`) is
  what the native output extends.
- **Alexey Melnikov (sorgelig)** and the MiSTer-devel contributors for the MiSTer
  framework, the analog output path and the scaler integration, and **Till Harbaum**
  for the origins of the HPS interface.
- **TEMLIB** for the ascal scaler, including the August 2026 fix this fork carries.
- SciTech's VBETEST, the DOSBox-X project and the CRT Terminator SCROLL tool did the
  measuring and the reference work during testing.

---

> **The original README.** Everything below is nand2mario's README of the upstream
> core as it was when forked, kept unchanged.

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

Development and compatibility discussion is available in the
[MiSTer FPGA forum thread](https://misterfpga.org/viewtopic.php?t=10667).
