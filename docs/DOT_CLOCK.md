# The dot clock: a real pixel clock as the raster's time base

A technical note on the pixel clock introduced in release 14 (`z486nv_20261014`). The
user-facing side, what it changes for each display and the trade-offs, is in the README; the
development history is on branch `exp/dot-clock-master`, every test build in
[`builds/`](../builds/BUILDS.md).

## Status

Verified on hardware (2026-10-14, test build `z486x_dotclk_20261013` build 12 and the release
binary, the same RTL at fitter seed 4):

- **Analog VGA on a CRT:** text, 13h, 12h, 640x480 in 8, 16 and 24 bpp, 800x600 and 1024x768
  (65 MHz) straight and complete, with the PLL locked and the renderer slaved in every mode and
  the output stage never re-centring.
- **15 kHz TV:** the same picture as release 13 in every mode a TV can show; 800x600 lands on the
  dark-green safe raster as before.
- **Direct video** (`direct_video=1`, HDMI-to-VGA dongle on the same CRT): every mode straight. The
  metadata packet the framework sends over HDMI reports pixel repetition 1 with the true width
  in every mode, and 3 in 24bpp where a pixel is three dots. Release 13 reports 3 in text, 4 in
  the 640-dot modes and 2 in 800x600 (see "Why" below).

Not tested by the author: a RetroTINK-4K or a Morph on the direct-video output (the repetition
numbers say it should be pixel-exact now; reports are welcome), and the HDMI scaler's behaviour at
mode switches over a long session (the scaler sees a new input clock at each switch, like it does
on cores that switch their video PLL). No game list was run on the release binary beyond the
owner's usual spot checks. The core sits at 98 % of the device, see "Cost". Release 14 also
carried a fix for a 24bpp bug present since release 7 (the picture sat one pixel right of its
blanking window and the last column was black), and that fix had a slip of its own: it routed
every other mode's blanking through one of the two registers meant for 24bpp, so release 14
cut the first dot of every line in all modes but 24bpp. Release 15 reads the delay line into
one register and takes the pixels and the blanking from it together (the RAM form; a wire read
turned the line into registers and the design no longer fit), measured exact afterwards with a
line of block characters and the DOTMODE ruler in text, 13h, 101h, 112h and 117h. The lesson is
in the testing: a probe for every mode class, not only the one being fixed.

## Why

Every release so far runs the whole video side on the 85 MHz system clock. The VGA block's dot
clock is a fractional enable: a 25.175 MHz dot lasts 3.376 clocks, which in practice is a mix of
3-clock and 4-clock dots; 28.322 MHz is 3.001 clocks, 35.9 MHz 2.37, 65 MHz 1.31. The
consequences, per output:

- **Analog port:** the DAC switches pixels on 85 MHz edges, so dot edges are off by up to 11.8 ns.
  A CRT does not show it below about 36 MHz; in the 65 and 75 MHz modes it shows as uneven
  one-pixel lines.
- **Direct video:** the HDMI clock is the 85 MHz clock and pixels last 3 or 4 clocks. The
  framework tells the scaler one integer repetition count (the length of the first pixel of a
  line, in clocks). A scaler that decimates by it gets 640 x 3.376 / 4 = 540 samples for a
  640-dot mode: issue #1, the RetroTINK-4K picture with a blank band. No profile can fix a
  non-integer ratio.
- **TV output:** the 15 kHz line store hides the 12 ns steps completely; fine as it was.

A real VGA card has a pixel clock synthesiser that is the master of the whole video chain, and
the host side is asynchronous to it. The branch takes that shape as far as this renderer allows.

## The shape

Three pieces, each small, the renderer untouched in principle:

1. **A reconfigurable PLL makes the dot clock** (`rtl/pll_video.v`): a fractional PLL with its VCO
   at 906.331 MHz (M = 18 plus a fractional part per family), output counter C0 divided per
   family. Six families cover every mode the fork shows natively:

   | family | rate | modes | C0 |
   |---|---|---|---|
   | 0 | 25.175861 MHz | 640-dot modes: 13h, 12h, 640x480 in 8 and 16 bpp | /36 |
   | 1 | 28.322843 MHz | 720-dot text | /32 |
   | 2 | 32.518160 MHz | 1024x768 planar | /28 |
   | 3 | 35.892784 MHz | 800x600 | /26 |
   | 4 | 64.985607 MHz | 1024x768 framebuffer, 8 and 16 bpp | /14 |
   | 5 | 75.024065 MHz | 640x480 in 24 bpp, three dots a pixel | /12 |

   The rates are nudged by a few hundred ppm from the nominal values so that a line is a whole
   number of 85 MHz cycles as well as of dots; both clocks come from the same 50 MHz reference.

2. **The renderer keeps its 85 MHz clock, but its pixel enable is slaved to the PLL**
   (`src/soc/dotclk_ce.v`): a Gray-coded counter in the dot-clock domain is sampled at 85 MHz and
   every advance becomes one enable, so the renderer produces exactly one dot per PLL cycle, in
   phase, with no accumulator and no restart trick at hsync. While the PLL is being reprogrammed
   the renderer falls back to its own fractional divider, as before.

3. **An output stage moves the raster into the dot-clock domain** (`src/soc/dot_resync.v`): a
   64-entry FIFO per raster (the primary one and the 15 kHz TV one), written at 85 MHz with one
   entry per dot and a marker on the first dot of each pixel, read at the dot clock. The read side
   pops one entry per clock and raises `CE_PIXEL` on the marked ones: every dot in most modes, one
   in three in 24bpp. The FIFO re-centres itself when empty or nearly full and holds centred while
   the renderer is not slaved, so every mode switch starts from the middle. `CLK_VIDEO` is the PLL
   output, `CE_PIXEL` the marker, so the analog DAC switches on dot boundaries and direct video is
   a standard 640x400@70, 720x400@70 or 800x600@56 timing at the true pixel clock with repetition
   1. The video cleaner, gamma, the mt32-pi overlay and the TV line store stay at 85 MHz in front
   of the FIFOs; the TV raster is sampled per dot into the second FIFO.

The PLL is reprogrammed by the framework's own reconfiguration IP (`sys/pll_cfg`,
`altera_pll_reconfig`), untouched, driven over its Avalon slave by a small table machine
(`src/soc/dot_pll_cfg.v`): per request six writes (waitrequest mode, N bypassed, M, the fractional
K, C0, start), each when the IP is not holding waitrequest, which it does until the sequence is
through and the PLL has relocked. A mode switch therefore goes: the VGA block selects a new family,
the table machine reprograms the PLL (about a millisecond), the renderer runs on its fallback
divider meanwhile, then the enable slaves to the PLL again and the FIFO re-centres. The HDMI
transmitter and the scaler see a new clock at each switch, as they do on cores that switch their
video PLL on the fly.

## Cost

Measured on build 12: 41,123 ALMs, 98 % of the device, of which the reconfiguration IP takes
about 1,120 (see "Lessons" for why it cannot be trimmed); the two FIFOs cost one M10K each and
about 40 ALMs apiece; the enable module 9 ALMs; the PLL is one of the free fractional PLLs. The
HDMI PLL's setup slack is marginal and seed-dependent (+0.3 ns on build 12, -0.3 ns on an earlier
seed), so a seed sweep precedes any release from this branch; clk_sys timing is the usual z486
figure.

## Diagnostics

Two read-only ports exist for checking the state from DOS (for instance with DEBUG's `i 2d8`):

- `2D8h`: bit 0 PLL locked, bit 1 the enable follows the PLL, bits 4:2 the family (table above),
  bit 5 the renderer slaved now, bit 6 reprogramming in progress, bit 7 the output stage running.
- `2D9h`: how many times the output stage has re-centred since power-up. It should stay at 0
  once a mode is on; it counts up by design at mode switches only if something is wrong.

## Lessons, for anyone touching this

- **The framework's reconfiguration IP stays as it is.** Three home-made DPRIO drivers (the last
  two matching the IP's bus cycle for cycle in co-simulation) and a copy of the IP trimmed to one
  output counter all wrote the same register values, verified by read-back, and the PLL ignored
  every one of them on silicon. The one-counter trim is bus-identical in simulation; whatever the
  tools do with it is below what the simulation models and the post-fit netlists show, and the
  Altera atom models are encrypted. Only the untouched IP reconfigures the PLL on the card.
- **Never pin the video PLL.** With `CLK_VIDEO` on the dot clock the video PLL is the HDMI
  transmitter's clock source, and only the PLL at X89_Y1 reaches that clock driver.
- **Gray codes must be registers.** Gray pointers computed by logic from the binary counters and
  sampled by the other clock gave a mode-dependent fault (ragged line starts in text, the scaler
  losing lock), because both clocks share a reference and the sampling phases recur line after
  line. The pointers and their Gray codes are updated together.
- **One FIFO entry per dot, not per pixel.** With one entry per pixel the 24bpp mode (three dots
  a pixel, the renderer restarting its divide-by-three at every hsync, a line not a multiple of
  three) drifted a dot per line and re-centred a hundred times a second. The marker bit carries
  the pixel boundary instead.
- **A RAM read must be unconditional** (`q <= mem[rptr]` in its own always block), or Quartus
  builds the FIFO out of registers.

## Building

It builds like every release (`quartus_sh --flow compile`, a full compile after removing `db/`
and `incremental_db/`). Release 14 is fitter seed 4 of a five-seed sweep (the sweep tool sets the
seed per copy; the checked-in `z486_mister.qsf` carries the profile's default). The testbenches under `tests/`
(`tb_dot_pll_cfg.sv`, `tb_dot_resync.sv`) run with Icarus Verilog and cover the table machine
against the IP and the FIFO through rate switches, a dot-clock stop and a faster renderer.
