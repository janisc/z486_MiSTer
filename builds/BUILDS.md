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

## Release line (branch `native-vga`)

| Folder / rbf | Commit | Contents | Status |
|---|---|---|---|
| `z486nv_20260909` | `eaf14c2`+ (tag `z486nv_20260909`) | RELEASE 3: release 2 + native output of the 8bpp SVGA framebuffer modes (svga_linebuf, DDR3 arbiter) + About-screen build date `nv-yymmdd`. | built 2026-09-09, on the card as the current release |
| `z486nv_20260902b` (now `_Z486_tests/z486x_release2_20260902b.rbf`) | `ad14180` (tag `z486nv_20260902b`) | RELEASE: everything below except the PLL. Native output, hsync line lock, real sync polarity, fixed pixel delay (2 chars in 8-dot modes, 3 chars in text), VSync/Border hidden + border forced on in native mode, README. | built 2026-09-02, superseded by z486nv_20260909 |
| `z486nv_20260902_pol` (was `z486nv_20260902.rbf`, now `_Z486_tests/z486x_release1_pol_20260902.rbf`) | `dae4506` (tag `z486nv_20260902`) | Native output + line lock + real sync polarity. Same bits as `z486x_pol_20260902`. | tested OK: monitor shows no polarity flag, DOS modes get their own preset; picture ~2 chars left of a real card |
| `z486x_nopol_20260902` | `a017d8e` | Native output + hsync line lock, polarity still N/N. | tested OK: wobble gone, "looks exactly like DOS on this monitor" |

## Experiments (branches `exp/*`)

| Folder / rbf | Branch / commit | Contents | Status |
|---|---|---|---|
| `z486x_nolinelock_20260901` (first build) | `71da8d1` | Native output only (OSD option, VGA_SCALER = fb_en, 60 Hz retiming off). | tested: works, but slow horizontal "snake" wobble in text mode/OSD from the 85 MHz fractional dot-clock enable |
| `z486x_pol_20260902` | `exp/sync-polarity` `dae4506` | Real VGA sync polarity via new VGA_HS_POS/VGA_VS_POS ports into sys_top. | accepted, merged into release |
| `z486x_pll_parked_20260902` | `exp/dot-clock-pll` `7439bc1` | Real dot-clock PLL (fractional VCO 906.3 MHz, output divider 8/9 switched by PLL reconfiguration = 2x dot clock), CDC synchronizers, clock groups. | PARKED: HDMI showed vertical grey lines (VGA pipeline likely needs >2 clocks/pixel); benefits invisible on a CRT (0.05% frequency, 1/3-px static jitter) |
| `z486x_hsync_wrongway_20260902` | `exp/sync-delay` `4d3a463` | Sync outputs delayed by 2 chars. WRONG DIRECTION: shortens the back porch. | tested: picture moved left, dark 1-char strip at the left edge (monitor's black-level clamp biting into video) |
| `z486x_vdelay_20260902` | `exp/sync-delay` `f4f75fc` | Pixels + DE delayed by 2 chars instead (sync untouched). | tested: better; text mode still short by ~1 char (needs 3), Keen OK; Keen's cyan overscan border darkened by the clamp = real-hardware quirk of mode 0Dh |
| `z486x_dials_20260902` | `exp/sync-delay` `c1ce4e8` | Same + live OSD dials "DEBUG H delay chars/dots". | used to measure: monitor centre wants ~7.0 us sync-edge-to-picture, standard (VESA/real card) is 5.7 us; front porch limits the delay to 5/4/3 chars before the right edge enters the sync |
| `z486x_svga_20260909` | `exp/native-svga` `c399904` | Native output of the 8bpp SVGA framebuffer modes (640x480x256 etc.): svga_linebuf fetches each scanline from the DDR3 framebuffer a line ahead and injects it at the DAC index; DDR3 port arbitrated with main_memory. On top of the release. | tested: black on CRT and HDMI, OSD alive = CPU stalled (arbiter deadlock) |
| `z486x_svga_20260909b` | `exp/native-svga` `65a62b4` | Same + DDR3 arbiter deadlock fix (first build stalled the CPU on its first framebuffer write: black on CRT and HDMI). | tested OK: SimCity 2000 and Panzer General 640x480x256 native on the CRT, no defects; promoted to release 3 |

## Facts learned

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
