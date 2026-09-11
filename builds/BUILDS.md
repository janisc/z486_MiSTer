# z486_MiSTer native-VGA builds

Source: this repository (fork of nand2mario/z486_MiSTer, upstream base `6075a33`
= release z486_20260831). Each folder holds the rbf, the timing report and
`GIT_COMMIT.txt` (the commit the rbf was built from). All builds: Quartus 17.1 Lite,
production profile (85 MHz clk_sys, seed 6). The CPU clock never closes timing in
this design (about -6 ns, all paths inside the CPU); that is upstream's normal state.

On the MiSTer: the current release and the stock core live in `/media/fat/_Computer`,
everything else in `/media/fat/_Computer/_Z486_tests`. MiSTer.ini for a PC CRT needs
`composite_sync=0` (separate H/V sync). The OSD option is Audio & Video -> VGA Output
-> Native 31kHz (default Scaler = upstream behaviour).

Naming rule (MiSTer main matches an MGL `<rbf>` as prefix + `_` or `.`, newest
alphabetical wins): `z486nv_<date>` = releases, picked up by the Z486 MGLs;
`z486x_<tag>_<date>` = experiments, never matched; `z486_<date>` = stock.


Resource cost of the fork (production profile, Quartus 17.1, same seed), measured
against a stock build of upstream `6075a33` on 2026-09-11:

| | stock | fork (`z486x_native_20260911`) | delta |
|---|---|---|---|
| Logic (ALMs) | 38,066 (91 %) | 39,298 (94 %) | +1,232 (+3 % of the device) |
| Registers | 31,565 | 33,314 | +1,749 |
| Block RAM (M10K) | 464 (84 %) | 478 (86 %) | +14 (line buffer 2 x 512 x 64, pixel delay line) |
| DSP blocks | 35 | 39 | +4 (24bpp dot-clock multiply, hi-colour unpacking) |
| clk_sys setup slack | -6.24 ns | -6.49 ns | fitter noise; CPU paths in both |

## Release line (branch `native-vga`)

| Folder / rbf | Commit | Contents | Status |
|---|---|---|---|
| `z486nv_20260910b` | `a85a231` (tag `z486nv_20260910b`) | RELEASE 7: release 6 + native output of the 24bpp framebuffer mode (mode 112h: one byte per dot, three dots per pixel, tripled dot clock for a 31.5 kHz line) so native mode never hands the analog port to the scaler, + horizontal retrace registers take effect at the next line (Copper's per-line hsync wobble no longer drops sync). Same binary as `z486x_latch_20260910`. | on the card as the current release |
| `z486nv_20260910` (now `_Z486_tests/z486x_release6_20260910.rbf`) | `e9a92d3` (tag `z486nv_20260910`) | RELEASE 6: release 5 + native output of the 16bpp (15/16-bit hi-colour) framebuffer modes: the line fetcher unpacks 1555/565 pixels (same OSD format bits as the scaler) into RGB that bypasses the palette; one dot per pixel, two bytes per dot. Same binary as `z486x_hicolor_20260910`. | superseded by z486nv_20260910b |
| `z486nv_20260909c` (now `_Z486_tests/z486x_release5_20260909c.rbf`) | `7c70aaf` (tag `z486nv_20260909c`) | RELEASE 5: release 4 + port 3CB writes ignored. Release 4 latched 3CB writes into the ET4000 segment bits 5:4 while reading FF; the VGA BIOS read-modify-writes 3CB on every mode set, so all CPU accesses to the SVGA framebuffer landed 3 MB above the picture (640x480x256 games black, VRAM reads returned 0). | superseded by z486nv_20260910 |
| `z486nv_20260909b` (now `_Z486_tests/z486x_release4_20260909b.rbf`) | `d0242ae` (tag `z486nv_20260909b`) | RELEASE 4: release 3 + ET4000AX chip identification (port 3CB reads FF) so UniVBE 5.3a/6.7 install with VBE 2.0. Same binary as `z486x_et4k_20260909`. BROKEN: SVGA framebuffer accesses offset by 3 MB (see release 5). | superseded by z486nv_20260909c |
| `z486nv_20260909` (now `_Z486_tests/z486x_release3_20260909.rbf`) | `eaf14c2`+ (tag `z486nv_20260909`) | RELEASE 3: release 2 + native output of the 8bpp SVGA framebuffer modes (svga_linebuf, DDR3 arbiter) + About-screen build date `nv-yymmdd`. | built 2026-09-09, superseded by z486nv_20260909b |
| `z486nv_20260902b` (now `_Z486_tests/z486x_release2_20260902b.rbf`) | `ad14180` (tag `z486nv_20260902b`) | RELEASE: everything below except the PLL. Native output, hsync line lock, real sync polarity, fixed pixel delay (2 chars in 8-dot modes, 3 chars in text), VSync/Border hidden + border forced on in native mode, README. | built 2026-09-02, superseded by z486nv_20260909 |
| `z486nv_20260902_pol` (was `z486nv_20260902.rbf`, now `_Z486_tests/z486x_release1_pol_20260902.rbf`) | `dae4506` (tag `z486nv_20260902`) | Native output + line lock + real sync polarity. Same bits as `z486x_pol_20260902`. | tested OK: monitor shows no polarity flag, DOS modes get their own preset; picture ~2 chars left of a real card |
| `z486x_nopol_20260902` | `a017d8e` | Native output + hsync line lock, polarity still N/N. | tested OK: wobble gone, "looks exactly like DOS on this monitor" |

## Experiments (branches `exp/*`)

| Folder / rbf | Branch / commit | Contents | Status |
|---|---|---|---|
| `z486x_hidac_20260911` | `exp/hicolor-dac` `74490cc` | Always-native build + HiColor RAMDAC modelled on the Sierra SC15025 (hidden command register, extended-register protocol the Tseng BIOS probes and programs; `16/24bit mode` and `16bit format` OSD options removed, pel mask applied) + port 3CB bank bit for the second megabyte (reads back 11h, still an ET4000AX to probes) + native 320x200 hi-colour (halved dot clock: two clocks per dot and pixel) + display start latched at vertical retrace + HDMI framebuffer stride for those modes. Five builds: v1 armed protocol, v2 simplified (broke the BIOS's DAC identification: 16-bit modes as 5:5:5), v3 + 3CB + retrace latch (320x200 half width), v4 Sierra model + dot-clock stepping (320x200 blank: pixel enable stopped in blanking), v5 free-running dot phase (picture squashed into the top half: row pitch wrongly doubled after a misread register dump), v6 pitch = offset x 8 like every other mode. Release 8 candidate. | VBETEST 15/16/24-bit, 16-page flip on the CRT (webcam), Indy, SP, Copper, UniVBE identification |
| `z486x_native_20260911` | `exp/always-native` `a9fcd38` | Release 7 + the analog port is always native: OSD `VGA Output` and `VSync` removed, no scaler request, no 60 Hz retiming; Border stays (applies to both outputs); MiSTer.ini `vga_scaler` / `vsync_adjust` / `direct_video` cover the exceptions (README). Release 8 candidate, on the card as `z486nv_20260911.rbf`. | harness regressions pass; CRT / DAC direct video / 15 kHz ini to be tested |
| `z486x_latch_20260910` | `exp/crtc-line-latch` `a85a231` | 24bpp build + CRTC horizontal retrace start/end/skew latched at the end of each line (writes take effect next line, as on real ISA timing). | tested: harness regressions pass; Copper wobble on the CRT much better, some dark flashing top/bottom in the helicopter part remains |
| `z486x_24bpp_20260910` | `exp/native-24bpp` | Native 24bpp framebuffer output (four builds: 1 dot/px guess, 2:3 mapping guess, 3 dots/px at 3x clock with a per-clock pixel mix, then colour registered per pixel). | tested OK with DISP24 on the native path |
| `z486x_hicolor_20260910` | `exp/native-hicolor` `e9a92d3` | Native 16bpp framebuffer output (first two builds of the branch doubled the dot clock after a DOSBox BIOS mode set; the Windows Tseng driver actually keeps 640 dots per line, two bytes each). | tested OK: Indiana Jones Desktop Adventures (Win 3.1, ET4000 640x480 32K colours) on CRT and HDMI, Steel Panthers 8bpp unchanged |
| `z486x_nolinelock_20260901` (first build) | `71da8d1` | Native output only (OSD option, VGA_SCALER = fb_en, 60 Hz retiming off). | tested: works, but slow horizontal "snake" wobble in text mode/OSD from the 85 MHz fractional dot-clock enable |
| `z486x_pol_20260902` | `exp/sync-polarity` `dae4506` | Real VGA sync polarity via new VGA_HS_POS/VGA_VS_POS ports into sys_top. | accepted, merged into release |
| `z486x_pll_parked_20260902` | `exp/dot-clock-pll` `7439bc1` | Real dot-clock PLL (fractional VCO 906.3 MHz, output divider 8/9 switched by PLL reconfiguration = 2x dot clock), CDC synchronizers, clock groups. | PARKED: HDMI showed vertical grey lines (VGA pipeline likely needs >2 clocks/pixel); benefits invisible on a CRT (0.05% frequency, 1/3-px static jitter) |
| `z486x_hsync_wrongway_20260902` | `exp/sync-delay` `4d3a463` | Sync outputs delayed by 2 chars. WRONG DIRECTION: shortens the back porch. | tested: picture moved left, dark 1-char strip at the left edge (monitor's black-level clamp biting into video) |
| `z486x_vdelay_20260902` | `exp/sync-delay` `f4f75fc` | Pixels + DE delayed by 2 chars instead (sync untouched). | tested: better; text mode still short by ~1 char (needs 3), Keen OK; Keen's cyan overscan border darkened by the clamp = real-hardware quirk of mode 0Dh |
| `z486x_dials_20260902` | `exp/sync-delay` `c1ce4e8` | Same + live OSD dials "DEBUG H delay chars/dots". | used to measure: monitor centre wants ~7.0 us sync-edge-to-picture, standard (VESA/real card) is 5.7 us; front porch limits the delay to 5/4/3 chars before the right edge enters the sync |
| `z486x_svga_20260909` | `exp/native-svga` `c399904` | Native output of the 8bpp SVGA framebuffer modes (640x480x256 etc.): svga_linebuf fetches each scanline from the DDR3 framebuffer a line ahead and injects it at the DAC index; DDR3 port arbitrated with main_memory. On top of the release. | tested: black on CRT and HDMI, OSD alive = CPU stalled (arbiter deadlock) |
| `z486x_svga_20260909b` | `exp/native-svga` `65a62b4` | Same + DDR3 arbiter deadlock fix (first build stalled the CPU on its first framebuffer write: black on CRT and HDMI). | tested OK: SimCity 2000 and Panzer General 640x480x256 native on the CRT, no defects; promoted to release 3 |
| `z486x_et4k_20260909` | `exp/et4000-id` `d0242ae` | Release 3 + port 3CB reads FF so chip detectors (SciTech UniVBE/SDD, svgalib, VGAKIT) identify the card as an ET4000AX instead of falling through to "ET6000, not supported". | tested OK: UniVBE 5.3a and 6.7 now install (ET4000, 1 MB, VBE 2.0 banked); Steel Panthers still black (dynamic difference after mode set, unresolved) |

## Facts learned

- The Tseng BIOS sizes video memory from CRTC 37h (bit 3 RAM chip size, bit 0 bus
  width, plus 32h bit 7): 2 MB on this core, stock included. Chip probes (svgalib,
  VGADOC, SciTech) write 33h to port 3CB and read it back; anything but 33h means
  ET4000AX, so implementing only bit 4 of each bank half keeps the identity and the
  second megabyte.
- The BIOS's DAC probe (7A6Bh) reads Sierra extended register 1 through the
  command-with-bit-4 / index / zero / data sequence on 3C6h; its VBE mode set writes
  extended register 3 = 02h/03h/05h for 15/16/24 bpp and leaves the command at 08h.
  A DAC that answers as a plain HiColor type gets 5:5:5 for the 16-bit modes.
- VBE mode 10Dh (320x200 hi-colour) is 40 characters wide, offset 80 (640-byte rows,
  8 bytes per offset unit like every mode), row scan count 1 for the line doubling,
  and the sequencer's halved dot clock like mode 13h; VBETEST puts its 16 pages on
  64 KB boundaries and sets the display start with an x offset.
- The framework's scaler reads the live framebuffer base per line, so a display-start
  change mid-frame tears on HDMI (stock too); the native path latches it at vsync.
- Debugging recipe that settled the layout questions: MODEDUMP.COM (mode info, 4F06,
  4F07, CRTC/SEQ/ATC/GR dump) plus fbscan's DDR3 dump for the real pitch of the
  picture; a webcam burst of the CRT for anything that flickers.

- The framework normalizes sync polarity and always drives N/N; real polarity needs
  the two new ports (400-line modes H-/V+, 350-line H+/V-, 480-line H-/V-).
- Monitors file all 31.5 kHz/70 Hz/H-/V+ DOS modes under ONE preset, so a constant
  sync-to-picture time across modes (5.7 us) is what makes one adjustment fit all.
- The BIOS blanking budget caps how far the picture can be pushed right: text 5 chars,
  mode 13h 4 chars, mode 0Dh 3 chars; beyond that the right edge enters the sync pulse.
- ET4000 framebuffer modes (256-colour/hi-colour SVGA) have no raster and go to the
  scaler; the runtime hand-over of the analog port to the scaler shows black on the CRT
  (main-side, out of scope). ao486 also hard-wires the scaler on the VGA port.
- Rebuild: `python build_profile.py production` (restores the gitignored PLL files),
  then `quartus_sh --flow compile z486_mister` from `F:\quartus\quartus\bin64`.
