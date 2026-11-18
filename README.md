# z486_MiSTer, native VGA output fork

This is a fork of [nand2mario/z486_MiSTer](https://github.com/nand2mario/z486_MiSTer).
The changes were written by an AI (Claude); the goals came from the repository owner,
who tested every build on real hardware. It changes what the MiSTer analog output
carries: the core's own raster instead of the scaler's fixed-mode picture, for two
kinds of display.

- **A VGA CRT monitor** gets 31.5 kHz lines at each mode's real refresh rate, the real
  dot clocks, the sync polarity a VGA card uses, and the picture placed after hsync
  where a real card puts it, so one monitor adjustment fits every DOS mode. The SVGA
  framebuffer modes (256-colour, 15/16-bit and 24-bit) are rendered natively as well,
  up to 1024x768, so the analog port never hands over to the scaler.
- **A 15 kHz TV or arcade monitor** gets a real 15 kHz raster (`Analog output: TV 15kHz`
  in the OSD): the scan-doubled 320x200 and 320x240 modes come out
  as true 240p, text and the 640-wide modes as every other row or as two interlaced
  fields, the 70 Hz modes padded to 60 Hz for sets that lock to 60 only, with the
  picture size and position adjustable from the OSD. Modes the set cannot show are
  blanked rather than sent.

HDMI works as on every core in both cases and shows the same picture through the
scaler. The raster is timed by a real pixel clock from a reconfigurable PLL, so both
outputs and direct video get exact pixel timing in every mode. The quick start below
has the setup for each display, the FAQ what works and what does not.

The core also carries, as an experiment and off by default, a
**Gravis UltraSound**: xolod79's GF1 model from ao486 with its sample memory in the
HPS DDR3, since z486 keeps its main memory in the SDRAM. The FAQ has the settings
and [docs/GUS.md](docs/GUS.md) the how.

## Quick start

Copy `z486nv_<date>.rbf` from the [Releases page](../../releases) to
`/media/fat/_Computer`. The boot ROMs, the disk images, the SDRAM module and the MiSTer
main version are the stock core's (the upstream README at the end has them). Then, by
display:

| Display | MiSTer.ini | OSD |
|---|---|---|
| VGA monitor on the analog port | `composite_sync=0` | nothing to set |
| 15 kHz TV or arcade monitor on the analog port | `composite_sync=1` if the set wants its sync on one line, as SCART sets do | Audio & Video: `Analog output` to `TV 15kHz` |
| HDMI | nothing; `vsync_adjust=0` or `1` if the display refuses 70 Hz | nothing to set |
| Direct video (a DAC or a scaler on the HDMI connector) | `direct_video=1`, and `composite_sync=0` for a VGA monitor behind it | nothing to set |

The analog port and HDMI work at the same time. The FAQ has the reasons and the details
for each display, and how update_all can install the core and keep it current.

## What is new in release 17

Where the picture sits against the sync pulse on the analog output. A CRT sets its
black level in the short gap after the horizontal sync, and in the 320-pixel EGA and
CGA modes and in 40-column text the core left only 0.68 us there, where a real card
leaves 1.27 us. A monitor that samples for longer than that takes the left edge of the
picture for black, and whole colours drop out or dim with whatever the game draws
there. That is the likely cause of issue #2 (Jill of the Jungle in EGA without its
blue, Commander Keen losing red as its map scrolled). Other monitors never showed the
fault, the test monitor here among them, so the word of a monitor that did is still to
come; HDMI was not affected. Every mode was in fact a little early: 7 dots in the
640-dot graphics modes, 8 in text, 15 and 17 in the 40-column modes, because the raster
opens its picture window one character before the line wrap and the delay that stands
in for a real card's pixel pipeline did not count that. Now the picture starts 144 dots
after the sync's leading edge in every graphics mode and 162 in text, as IBM's register
sets intend, and the 24-bit mode moved 8 pixels left to its real place beside the other
640x480 modes. On a CRT every mode sits about 3 mm further right than before, the
320-pixel EGA and CGA modes twice that, so the monitor's horizontal position may want
one touch; EGA 320x200 games now line up with mode 13h games. The picture through the
HDMI scaler is unchanged, and so is the TV output, which cuts the picture out of the
raster and places it by its own timing. Nothing in the settings resets.
`tests/tb_vga_porch.sv` checks the sync width, the gaps and the picture window for
each BIOS mode.

Also new: update_all and the MiSTer Downloader can install the core and keep it current,
through a database of the fork's own; the FAQ says how to switch that on.

What the earlier releases changed is in [CHANGELOG.md](CHANGELOG.md).

## Where things are

The changes are on branch `native-vga`; `main` tracks upstream. Experiments live on
`exp/*` branches; the pixel clock's development history is `exp/dot-clock-master`.
The rbf of the current release is attached to the [Releases page](../../releases); what
each release changed is in [CHANGELOG.md](CHANGELOG.md); the rbf files of every build
made along the way, with a description of each, are in [`builds/`](builds/BUILDS.md).
Branch `db` carries nothing but the MiSTer Downloader's database of the fork and its ini
file. Nothing here has been submitted upstream. The upstream README, as it is in the
version this fork is built on, follows at the end of this file after the thanks.

## FAQ

**Where do I get the core and how do I install it?**
Download `z486nv_<date>.rbf` from the [Releases page](../../releases) and copy it to
`/media/fat/_Computer`, next to the stock core if you keep one. Everything else is
the stock core's: the boot ROMs and disk images in `/media/fat/games/Z486`, the SDRAM
module, the MiSTer main version (see the upstream README at the end). Every build
made along the way, with notes, is in [`builds/`](builds/BUILDS.md).

**Can update_all or the MiSTer Downloader install and update it?**
Yes, from release 17 on, through a database of the fork's own; the core is not part of
the MiSTer distribution or of update_all's lists. Put a file named
`downloader_z486nv.ini` into the root of the SD card (`/media/fat`), next to
`downloader.ini`, with these three lines:

```ini
[z486nv]
db_url = https://raw.githubusercontent.com/janisc/z486_MiSTer/db/db.json
filter = z486nv
```

The file is also [on the `db` branch](../../blob/db/downloader_z486nv.ini), ready to copy.
From then on every run of update_all or of the Downloader installs the current
`z486nv_<date>.rbf` in `_Computer` and removes the one it installed before. That one file
is all the database touches: no ROMs, no disk images, no settings, and nothing of the
stock core, which keeps coming from upstream. A core you copied in by hand under an older
date is not removed, so delete it once. The `filter` line keeps a download filter of your
own, if you have set one, from skipping this core. Drop-in files like this are read by
Downloader 2.4 (March 2026) and newer; the same three lines at the end of `downloader.ini`
do the same. To leave, delete the ini file and the core.

**I use a VGA monitor. What do I need?**
Connect it to the analog output and make sure MiSTer.ini has `composite_sync=0`.
Nothing else. The core puts real VGA timing on that port, 31.5 kHz with separate
horizontal and vertical sync, which is what any VGA monitor from 1987 on accepts;
the framework's composite sync option would merge the two syncs, and many PC
monitors do not take that. There is no multisync requirement and no OSD setting.

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
scaled: 200 rows are 200 TV lines, a little less than the 240 a TV shows, so there is a
black band above and below the picture. `Fill` shows every fifth scanline twice, so
200 rows become 240 lines and fill the screen, the same 1.2 stretch the scaler gives
but with sharp lines; the SVGA framebuffer modes are left at native size. The picture
is centred in the standard 240-line window; sets differ in their own centring, so
`TV H-position` and `TV V-position` nudge it in steps of half a microsecond and four
lines. The TV options only appear in the menu while the analog output is set to TV. With `Fill` the outermost lines fall into the set's overscan.
`TV hi-res modes` decides what happens to text and the
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
overscan.

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

**How do I tell the fork from the stock core, and can I keep both?**
The builds are named `z486nv_<date>` (nv for native video) so they sit next to the
stock `z486_<date>.rbf` in `_Computer`; load whichever you want. Both report the same
core name to MiSTer, so they share `config/Z486.CFG` (OSD settings, boot order, the
mounted images), the `games/Z486` folder and the `[z486]` section of MiSTer.ini. The
OSD's bottom line shows `nv-yymmdd` on this fork and, from z486 20261012 on, `vyymmdd`
on the stock core, which is how you tell which one is loaded.

**Do I need UniVBE?**
Not for games that use the BIOS's VBE 1.2 modes, which includes the 15/16/24-bit
hi-colour ones. Games that require VBE 2.0 need SciTech UniVBE or Display Doctor
5.3a or later; those identify the card as an ET4000 and install. If you install a
new core build over an old UniVBE setup, run UVCONFIG once: it caches what it
detected, including the RAMDAC.

**Is there a Gravis UltraSound?**
Yes, as an experiment, since release 11, and off by default. Switch `Gravis
UltraSound` to `On` on the OSD's Audio & Video page and the card is there at the
usual place: port 240h, IRQ 7, DMA 7, 1 MB of sample memory, so
`SET ULTRASND=240,7,7,7,7` in AUTOEXEC.BAT. The Sound Blaster stays at 220h, IRQ 5,
DMA 1 and 5, so one disk can serve both. The card is xolod79's GF1 model from the GUS
branch of ao486_MiSTer, unchanged; what is new is where its memory lives, in the HPS
DDR3, because the SDRAM is z486's main memory ([docs/GUS.md](docs/GUS.md) explains
how, and how to do the same in the stock core). Gravis's own software (ULTRINIT, the
patch set for MIDI, the players) is not included; the old-software archives carry it,
and the Future Crew demo disk of the 0MHz collection comes with a set. The resources
are fixed: a program that insists on another IRQ, another DMA channel or an 8-bit DMA
channel should be pointed at the Sound Blaster instead. Not tried yet: a game that
uses an SVGA mode and the GUS at the same time; the fork's own test program for that
combination is clean.

**Some settings disappeared from the Audio & Video menu. Why?**
Compared with the stock core, three options are gone and two are added. Gone are
`VSync`, which retimed the raster to 60 Hz and has no place when the analog port
carries the real timing, and `16/24bit mode` and `16bit format`, which asked the
user to guess the pixel format of the hi-colour modes. Added are `Analog output`
and `Gravis UltraSound`. The emulated RAMDAC now has the command register
the BIOS and the Windows driver program, so the format is whatever they set, as on
a real card. `Border` stays and applies to both outputs; since release 13 it is off by
default, as upstream and ao486 have it. The aim was to remove
combinations that did not make sense, not functionality; if something you need is
missing, open an issue.

**Which modes do not work on the CRT?**
A full VBETEST sweep of every VBE mode found these limits. 1280x1024 loses the CRT: this
BIOS runs it interlaced from a 36 MHz clock, below 30 kHz (HDMI shows it). 1024x768 in 8 and
15/16 bit works at 60 Hz (48 kHz): the core gives the ET4000's clock index 2 the 65 MHz a
real 1024x768 board has, for these framebuffer modes only. Since release 14 those 65 MHz
pixels are exact; before, their widths alternated between one and two clocks of the core's
85 MHz, which showed as stair steps on one-pixel lines. The 16-colour
modes above 64 KB per plane, 1024x768 and 1280x1024, stay at 32.5 MHz (below 30 kHz) and
also repeat the picture vertically: the legacy VGA memory is four 64 KB planes, as in stock
and ao486. 800x600 in 24 bit is beyond the analog port at the core's 85 MHz. UniVBE's own
640x350 and 640x400 15-bit modes program a halved dot clock and run at 15.7 kHz; the BIOS's
15-bit modes are fine. Everything at 320x200, 640x400, 640x480 and 800x600 in 8, 15 and 16
bit, and 640x480 in 24 bit, works on both outputs. One VBETEST screen is off by design: its
24-bit horizontal scroll walks a 1360-pixel-wide buffer sideways by single pixels, which
three bytes per pixel and a start address counted in four-byte units cannot express; the
CRT snaps to 2.67-pixel steps and HDMI shows the window displaced. No program scrolls a
banked 24-bit buffer that way.

**What else is known not to work?**
The video limits of the fork are in the entry above. What the tests have turned up
beyond them shows on the stock core as well:

- Apache page-faults at startup on every z486, stock included, while ao486 runs it.
- Aladdin stops with an XMS allocation error, the same on the stock core.
- Beneath a Steel Sky wants `RAM Size` at 16 MB. With more memory it ended in a General
  Protection Fault when it was last tried, on release 12, a matter noted in upstream's
  release notes.

When a program misbehaves, `CPU Pipeline: Compatible` on the OSD's Hardware page is the
first thing to try; the page also has switches for the L1 cache and the x87. On the
fork's side: the core fills 98 % of the FPGA, about a thousand logic cells of that for
reprogramming the pixel clock, so there is little room for more. The Gravis UltraSound
has fixed resources and has not been tried together with an SVGA game (see its entry).
And the fault of issue #2 never showed on the test monitor, so release 17's cure for it
rests on measurement, not yet on a monitor that showed it.

**Which z486 is this built on?**
Release 17 is built on z486 20261025 (nand2mario main `c1b99f3`), as releases 15 and 16
are; it was upstream's current version on the day of the release. From upstream come,
among much else, the x87 with real transcendentals, the shared folder with DOS through
MISTERFS, CPU speeds down to 3 MHz-equivalent for speed-sensitive software and the game
fixes of every version up to that one; the upstream README at the end describes the
core itself. The fork changes the video path and adds the sound card; the CPU is
upstream's, unchanged. Which upstream version each release was built on, and what came
with it, is in [CHANGELOG.md](CHANGELOG.md).

**How is it tested?**
Every release binary is tried on real hardware before it goes out: a VGA CRT on the
analog port and an HDMI display, and for the changes that touch them a 15 kHz TV and an
HDMI-to-VGA adapter on direct video. Around that there are four kinds of checks:

- The fork's own DOS test programs: register and mode dumps, retrace counters, edge
  blocks and a pixel ruler that are measured column by column on a capture in every
  mode class, VRAM banking, a resident INT 10h logger, memory and DMA read-back tests
  for the Gravis UltraSound. They and the debug floppy are described in
  [`builds/BUILDS.md`](builds/BUILDS.md).
- SciTech's VBETEST in every colour depth, including 16-page 320x200 hi-colour page
  flipping, as the regression suite for the SVGA framebuffer modes.
- An automatic boot check: a script loads launcher after launcher from a 349-title
  collection and takes screenshots until the picture holds still. Since release 17 it
  also photographs the CRT for every title and compares each end screen with the
  previous release's. A release gets a part of the collection, a few dozen titles, not
  all of it.
- Simulation where the right answer is a number: `tests/tb_vga_porch.sv` holds the sync
  width, the gaps and the picture window of each BIOS mode against a real card's, and a
  camera then measures the picture's place on the CRT.

Run by hand on the CRT at one release or another: DOS text modes, Doom, Commander Keen
1 and 2 (EGA), SimCity 2000 and Panzer General (640x480x256), Steel Panthers, Indiana
Jones Desktop Adventures under Windows 3.1 (640x480 hi-colour), Scorched Earth 1.5 at
1024x768, Descent, Lemmings, Full Throttle, Day of the Tentacle, Alone in the Dark 1 and
2, BattleTech, Crusader: No Regret, Beneath a Steel Sky, and the demos Copper (per-line
raster tricks), Legend, Demoded and Second Reality, the last three with the Gravis
UltraSound as well. What each release was checked with is in
[CHANGELOG.md](CHANGELOG.md). No release is run through every game, so reports are
welcome.

**How do I report a problem?**
Open an issue on this repository. What helps most:

- the release, as the OSD's bottom line shows it (`nv-yymmdd`);
- the display and how it is connected: analog port, HDMI or direct video, and the model
  of the monitor or TV;
- the program, and its video mode if you know it;
- the video settings of your MiSTer.ini (`composite_sync`, `vsync_adjust`,
  `vga_scaler`, `direct_video`) and the OSD's `Analog output`;
- a photo of the screen, which says more than a description.

If you can, try the same on the stock core (`z486_<date>.rbf`). A fault that is there
too comes with what the fork inherits, and upstream is the place for it
([nand2mario/z486_MiSTer](https://github.com/nand2mario/z486_MiSTer), or the forum
thread linked in the upstream README below); one that only the fork shows is ours.

**Will this go into z486 or ao486?**
Maybe. This started as an experiment and we are happy with the result, but more
testing by more people is needed first. Do not wait for pull requests: the code is
here under the same terms as the files it lives in (the ao486 BSD licence for the
video code, Apache 2.0 for the z486 CPU), so if you want it somewhere, take it
there.

## How it works

The analog VGA port always carries the core's own raster: the real 25.175 and
28.322 MHz dot clocks (tripled for the 24bpp mode), 31.5 kHz lines at 70 Hz
(mode 13h, text) or 60 Hz (640x480), the sync polarity a VGA card uses
(400-line modes H-/V+, 350-line H+/V-, 480-line H-/V-), and the picture placed
after hsync where a real card puts it: 144 dots after the sync's leading edge in
every graphics mode and 162 in text, checked for each BIOS mode by
`tests/tb_vga_porch.sv`. The SVGA framebuffer modes (8, 16 and
24bpp) are fetched from the DDR3 framebuffer line by line and shown the same way,
so the port never hands over to the scaler. The only OSD switch is `Analog
output`, which chooses the raster the port carries; the HDMI output is always the
scaler, and the exceptions in the FAQ are MiSTer.ini settings handled by the
framework. The `Border` option shows or hides the overscan border on both outputs (the framework
blanks the analog picture with the same signal the scaler crops to).

The raster is timed by a real pixel clock. A reconfigurable PLL
generates each mode's rate (25.175, 28.322, 32.5, 35.9 and 65 MHz, 75 MHz for 24-bit
colour, each nudged by a few hundred ppm so that a line is a whole number of cycles
of both clocks); the renderer keeps the 85 MHz system clock with its pixel enable
slaved to the PLL's edges, and a small FIFO per raster re-times pixels and syncs
into the pixel-clock domain, so the DAC switches on dot boundaries and the HDMI
direct-video stream is a standard timing with repetition 1. The PLL is reprogrammed
at each mode switch by the framework's reconfiguration block.
[docs/DOT_CLOCK.md](docs/DOT_CLOCK.md) has the pieces, the measurements and the
lessons; why it replaced the counter of the first thirteen releases, and what it
costs, is in [CHANGELOG.md](CHANGELOG.md) under release 14.

In TV mode a line store (`src/soc/vga_tv15.sv`) sits between the raster and the
analog port. Every VGA line lasts 31.8 us whatever the mode, so the store captures
one line in two and plays it out over the time of two at half the dot rate: a
15.73 kHz line with TV sync widths (4.7 us sync, picture from 11.3 us after it). The
scan-doubled modes lose nothing, since each row was drawn twice; the other modes
lose every other row, or are shown as two fields when `Interlace` is selected. The
output vsync is placed from the measured frame so the picture sits centred in the
240 visible lines. With `TV frame rate` at `60 Hz` the CRTC pads the 70 Hz modes
with blank lines below the picture until the frame lasts a 60 Hz frame time, so no
frame is dropped or repeated; `Fill` makes the CRTC hold every fifth display
scanline for one more line, so 200 rows become 240. Anything the store cannot
convert (a line period off 31.8 us by more than 5 %, a frame outside 400 to 560
lines, no sync) switches the port to a self-timed 15.73 kHz, 60 Hz raster in dark
green on the first bad line, so the set never receives an out-of-range signal. The
scaler keeps the 31 kHz raster, and the OSD is mixed in after the conversion, so it
stays usable on the TV.

The emulated card identifies itself to chip detectors as an ET4000AX: port 3CB
implements only the bank bit for the second megabyte and reads back 11h for the
usual 33h probe, so SciTech UniVBE / Display Doctor 5.3a and later install and
provide VBE 2.0 (banked), while the 2 MB the BIOS reports are really usable (VBE
modes above 1 MB, the sixteen pages of 320x200 hi-colour). The RAMDAC is modelled
on the HiColor DAC the Tseng BIOS probes for, an SGS-Thomson STG1700-family part
(hidden command register behind four reads of 3C6h, indexed registers through the
same port; earlier versions of this text named a Sierra SC15025, which reaches its
extended registers through 3C7h and 3C8h), so the 15-bit or 16-bit
pixel format of the hi-colour modes is whatever the BIOS or the driver programmed.
The pel mask is applied to the pixels like a real DAC does. The 320x200 hi-colour
modes (halved dot clock, like mode 13h) are shown natively too, and a display-start
change takes effect at the next vertical retrace as on a real CRTC, so page
flipping is tear-free on the analog output. SciTech's VBETEST (in the SDD 5.3a
package) exercises all of this and is the fork's regression suite for the SVGA
framebuffer modes.

The Gravis UltraSound is xolod79's GF1 model (`src/soc/sound/gus/gf1.v`, unchanged)
with a new wrapper around it. The model treats the chip's 9.88 MHz clock as a signal
it samples, so the wrapper generates that clock and holds it while the sample memory
answers; the memory can then be anything with a request and an acknowledge, here a
third master on the DDR3 port next to the framebuffer paths. The chip never notices
the slower memory, and the held clock is repaid afterwards, so the pitch stays right.
One consequence of the held clock (an access from the CPU has to wait for the chip's
memory cycle), the memory port, the cost and the tests are in
[docs/GUS.md](docs/GUS.md), which also says how to put the same into the stock core.

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
- **xolod79** for the Gravis UltraSound: the GF1 chip model and its register glue
  come from the GUS branch of his ao486_MiSTer fork (since merged into MiSTer-devel's
  ao486), and the GF1 file is his, unchanged.
- SciTech's VBETEST, the DOSBox-X project and the CRT Terminator SCROLL tool did the
  measuring and the reference work during testing.

---

> **The original README.** Everything below is nand2mario's README of the upstream
> core, as it is in the version this fork is built on, unchanged.

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

## Shared folders and CPU speed

[MISTERFS](doc/misterfs.md) shares `/media/fat/games/Z486/shared` with DOS using the current ao486 driver. If using EMM386, reserve `CE00-CFFF` before loading the driver.

The OSD offers Full, 56, 30, 15, 6, 5, 4 and 3 MHz-equivalent execution rates. Existing four-speed SYSCTL commands remain compatible; use the OSD for the four new rates. The [SYSCTL interface](doc/sysctl.md) documents core/version detection for future utility updates.
