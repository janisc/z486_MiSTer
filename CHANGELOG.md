# Changelog

What each release of the native VGA output fork changed, newest first. How things are
now is in the [README](README.md); every build, the releases included, is described
with its commit, its timing and its test notes in [builds/BUILDS.md](builds/BUILDS.md).
Releases are tagged `z486nv_<date>`. From 9b on the binaries are attached to the
[Releases page](../../releases); all of them are in [`builds/`](builds/BUILDS.md),
where the table at the top says which folder holds which release.

The entries of releases 14 to 17 are the README's own, from the time each was the
current release. Those of releases 1 to 13 are short summaries of the rows in
`builds/BUILDS.md`, with what the README said about them at the time.

## Release 17, `z486nv_20261118` (2026-11-18)

Built on z486 20261025.

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

Two things beside the core. update_all and the MiSTer Downloader can now install it
and keep it current, through a database of the fork's own on branch `db`; the README's
FAQ says how to switch that on. And the README was reorganised: a quick start by
display, the present state of testing and of known problems, how to report a problem;
the history of the releases moved into this file.

How it was checked: by a self-checking simulation of each BIOS mode, and on the
release binary by comparing HDMI screenshots with release 16 pixel for pixel in every
mode class, by measuring the picture's place on a VGA CRT with a camera, and by the
automatic boot check over 28 titles, each with a camera shot of the CRT and its end
screen compared with release 16's (all 42 on the first build of the fix). The fault of
issue #2 itself does not show on the test monitor. The database was tried with
Downloader 2.4 against a scratch folder: a first install, an update that replaces the
core, and both again under a user's own download filter.

## Release 16, `z486nv_20261027` (2026-10-27)

Built on z486 20261025.

One line, in the Gravis UltraSound. A DMA transfer from the card's memory to the PC
(the direction a program uses to read samples back; uploads go the other way and were
always right) came back garbled, every value repeated about six times and the stream
behind. The card model raised its read request for the whole of its clock slot
instead of once at the slot's edge, as the write side already did, so it answered each
request several times over. The fix is xolod79's, from ao486 (ao486_MiSTer PR #237);
the fork's GUS is otherwise unchanged. A read-back test (4 KB written through the
card's memory port, fetched back by DMA, compared) goes from 4,081 bytes wrong of
4,096 to none. Everything else is release 15: the same z486 20261025 underneath, the
same video path, nothing in the settings resets.

## Release 15, `z486nv_20261026` (2026-10-26)

Built on z486 20261025.

Two things. The cut dot of release 14: the window that gates the picture opened one
dot after the pixels in every mode but 24-bit colour, so the first pixel column was
missing and the last column black, on the analog port, the TV and HDMI alike (in
text: one-pixel left stems on M, P and R in the first column). The blanking is back
with its pixels, measured column by column in text, 13h, 640x480, 24-bit and
1024x768. And z486 20261025 underneath, all of it upstream's work: a shared folder
with DOS through MISTERFS (`/media/fat/games/Z486/shared` as a DOS drive: the
current ao486 `MISTERFS.EXE` on the DOS disk, `X=CE00-CFFF` on the EMM386 line,
`MISTERFS E /Q`; MiSTer main 20260823 or newer), four lower CPU speeds in the OSD (6,
5, 4 and 3 MHz-equivalent) for speed-sensitive software, and fixes for Might and Magic
II's speaker music, Fistfight's false "INI file corrupt" error, Dragonsphere's intro
music, Discworld II's movie-audio clicks and the x87's rounding status bit. Nothing
in the settings resets.

How it was checked: release 15 added the probe that would have caught release 14's cut
dot (a line of block characters and a pixel ruler, measured column by column on the
capture in every mode class) and was spot-checked by hand; the game list was not run,
so reports are welcome.

## Release 14, `z486nv_20261014` (2026-10-14)

Built on z486 20261012.

Until release 13 the picture was timed by the core's single 85 MHz clock, with a
counter standing in for each mode's pixel clock: a 25.175 MHz pixel lasted three
clocks or four, 3.376 on average. That was the simpler way to build it, and it had
its merits: one clock domain, nothing to reprogram, and for the modes most games use
a CRT does not show a 12 ns wobble on a 40 ns pixel. It stopped being good enough in
two places. Scalers that take the raw raster over HDMI (direct video) are told the
pixel rate as a whole number of clocks, so a 640-pixel mode came out 540 pixels wide
on a RetroTINK-4K, with a blank band. And in the high-resolution and high-colour
modes, where a pixel is only one or two clocks long, the approximation showed as
uneven pixel widths. With what the earlier releases had taught, the proper way got
another go: a reconfigurable PLL generates the real pixel clock of every mode, the
renderer follows it, and the output stage puts every pixel edge on that clock. What
it changes for you: direct-video scalers get a standard timing at the true pixel
clock with the repetition count at 1, so a RetroTINK-4K samples the picture pixel
for pixel (none was at hand here; the owner of a RetroTINK-4K Pro who had reported
the blank band confirmed on release 14 that it is gone, issue #1); the analog port
is exact in every mode, where the old step
was 30 % of a pixel in the 320- and 640-wide modes, 42 % at 800x600, 76 % at 1024x768
and 89 % in 24-bit colour; the TV output is cut from the same exact raster. The
trade-offs, said plainly: it is a big change to the video path, so there may be bugs
the tests did not reach, and an issue with the mode and a photo is the best help;
and the clock reprogramming costs about a thousand logic cells, so the core is at
98 % of the chip with no idea yet of how to make that smaller.
[docs/DOT_CLOCK.md](docs/DOT_CLOCK.md) has the engineering. Release 14 itself shipped
with a one-dot cut at the left of every line in all modes but 24-bit (a slip in its
24-bit fix, not the clock); release 15 corrects it, see its entry above.

Besides the pixel clock, a 24-bit fix: the picture sat one pixel to the right of its
window and the last column was black, since release 7.

How it was checked: with the fork's own test programs in every mode on a VGA CRT, a 15
kHz TV and an HDMI-to-VGA adapter, not through the game list; it still shipped a
one-dot cut that the owner's eye caught in FastDoom's startup text.

## Release 13, `z486nv_20261013` (2026-10-13)

Built on z486 20261012.

Everything new in it was upstream's work. The CPU gained real x87 transcendentals
(FSINCOS, FPREM1, FXTRACT and FYL2XP1 were no-ops before), FST ST(i), FFREEP and FBLD,
hardware breakpoints, a faster memory path and a set of game fixes (SHLD/SHRD with
16-bit operands, the TSS access flag, MOV to the debug registers, the AC flag on
interrupt entry). Around it: critical-word-first SDRAM bursts, one-cycle chain-4 dword
writes to the VGA, the SVGA linear framebuffer at 248 MB where UniVBE looks for it,
coprocessor errors on IRQ 13 with IGNNE# at port F0h (made for Wolfenstein 3D's FPU
check under EMM386), no CMOS coprocessor with the x87 switched off, and two more
joystick types (CH Flightstick Pro, Thrustmaster FCS).

Four settings read differently after this release, because their bits moved or changed
meaning: `Analog output`, the `TV` options and `Gravis UltraSound` come back at their
defaults (VGA 31 kHz, GUS off), and `Border` is off by default now, so a saved `No`
shows as `Yes` once; set them again, the rest of `Z486.CFG` is kept.

The settings moved because the fork's own OSD options went to the top of the status
word (bits 117 to 127): upstream's wider `Joystick Type` had taken the bits of `TV
H-position`.

How it was checked: an automatic boot check instead of the game list: a script loads
launcher after launcher from a 349-title collection and photographs the screen until
it holds still. Of the first 37, all started except Aladdin (an XMS allocation error,
the same on the stock core) and Apache (its disk image had its drivers commented out;
with that repaired it page-faults on every z486, stock included, while ao486 runs it,
a matter for upstream). The usual list of games was then launched by hand on the
release binary.

## Release 12, `z486nv_20261007` (2026-10-07)

Built on z486 20261006.

Release 11 on a new upstream version, nothing changed in the fork's own parts. From
upstream: a CPU with protection and fault fixes for Windows 95 and games, XADD,
CMPXCHG, INVD and WBINVD and Intel's DIV flags; a `Scale` option for the HDMI scaler;
fast IDE reads; the RTC's CMOS shadow registers kept over a core reset. New on the OSD
with this version: the Hardware page's switches for the CPU's fast paths, L1 cache and
x87 (`CPU Pipeline: Compatible` is the one to try when a program misbehaves) and the
`RAM Size` order that gives a fresh configuration 64 MB.

How it was checked: spot checks rather than a run through the list: Alone in the Dark
2, Crusader: No Regret and Second Reality with the Sound Blaster run now, Beneath a
Steel Sky with `RAM Size` at 16 MB, and the titles tried from the list ran as before.
Beneath a Steel Sky wants `RAM Size` at 16 MB; with more memory it ended in a General
Protection Fault, a matter noted in upstream's release notes.

## Release 11, `z486nv_20261004` (2026-10-04, published 2026-10-06)

Built on z486 20261003.

Release 10 on a new upstream version (a new CPU with a faster integer pipeline and
x87; smaller DMA, PIT and joystick logic), `Fill` for the SVGA framebuffer modes on
the TV output, and the Gravis UltraSound, experimental and off by default: xolod79's
GF1 model with its sample memory in the HPS DDR3, at 240h, IRQ 7 and DMA 7 with 1 MB
([docs/GUS.md](docs/GUS.md)).

How it was checked: the regression list was run again: Doom, Descent, Lemmings, Full
Throttle, Day of the Tentacle, Commander Keen 2, Alone in the Dark, BattleTech,
SimCity 2000, Copper, Legend, Demoded and Indiana Jones Desktop Adventures run; with
the Gravis UltraSound, Second Reality, Legend and Demoded.

## Release 10, `z486nv_20260918` (2026-09-18)

Built on z486 20260831, like every release before it.

The 15 kHz TV output on the analog port: the OSD's `Analog output` with `VGA 31kHz`
(the default) and `TV 15kHz`, and in TV mode `TV frame rate`, `TV picture`, `TV
H-position`, `TV V-position` and `TV hi-res modes`. The scan-doubled modes come out as
true 240p, the 70 Hz modes are padded to 60 Hz frames, `Fill` repeats every fifth
line, modes a TV cannot show get a self-timed dark green raster, and HDMI keeps the 31
kHz picture.

## Release 9b, `z486nv_20260913b` (2026-09-13)

`sys/ascal.vhd` synced to upstream Template_MiSTer, where the scaler's output state is
reset at every vertical sync. Before, the HDMI picture could stay black with the OSD
still drawn after a run of video-mode changes, until the core was loaded again.

## Release 9, `z486nv_20260913` (2026-09-13)

24-bit colour: the pixel phase restarts at the first dot of every line (static zigzag
edges and wavy text in 640x480x24 on the CRT). The ET4000's clock index 2 is 65 MHz in
the framebuffer modes, so 1024x768 in 8, 15 and 16 bit runs at 48.4 kHz and 60 Hz on
the CRT; the planar 16-colour modes keep 32.5 MHz. The line buffer's read path fixed
for one-clock pixels (spikes at 1024x768), and the HDMI framebuffer width for 24-bit
colour taken from the line stride.

## Release 8, `z486nv_20260911` (2026-09-11)

The analog port is always native: the OSD's `VGA Output` and `VSync` options are gone,
and MiSTer.ini's `vga_scaler`, `vsync_adjust` and `direct_video` cover the exceptions.
A HiColor RAMDAC with the command register the BIOS and the drivers program, so the
`16/24bit mode` and `16bit format` options are gone too, and the pel mask is applied.
Port 3CB's bank bit for the second megabyte, with the card still an ET4000AX to
probes; 320x200 hi-colour shown natively; the display start latched at the vertical
retrace.

## Release 7, `z486nv_20260910b` (2026-09-10)

Native output of the 24-bit framebuffer mode (mode 112h: one byte per dot, three dots
per pixel, a tripled dot clock for a 31.5 kHz line), so the analog port never hands
over to the scaler. Horizontal retrace registers take effect at the next line, so
Copper's per-line hsync wobble no longer drops the sync.

## Release 6, `z486nv_20260910` (2026-09-10)

Native output of the 15- and 16-bit hi-colour framebuffer modes.

## Release 5, `z486nv_20260909c` (2026-09-09)

Writes to port 3CB ignored. Release 4 latched them into the ET4000's segment bits, and
since the VGA BIOS rewrites 3CB on every mode set, all CPU accesses to the SVGA
framebuffer landed 3 MB above the picture: 640x480x256 games stayed black.

## Release 4, `z486nv_20260909b` (2026-09-09)

ET4000AX chip identification through port 3CB, so UniVBE 5.3a and 6.7 install with VBE
2.0. Broken for SVGA framebuffer programs, see release 5.

## Release 3, `z486nv_20260909` (2026-09-09)

Native output of the 8-bit SVGA framebuffer modes (640x480x256 and the like), and the
build date `nv-yymmdd` in the OSD.

## Release 2, `z486nv_20260902b` (2026-09-02)

Release 1 with a fixed pixel delay that moves the picture towards where a real card
has it (two characters in the 8-dot modes, three in text), and the first README.

## Release 1, `z486nv_20260902` (2026-09-02)

Native output of the standard VGA modes on the analog port, as an OSD option beside
the scaler, with the horizontal sync locked to the line and the real sync polarity.
The picture sat about two characters left of a real card's.
