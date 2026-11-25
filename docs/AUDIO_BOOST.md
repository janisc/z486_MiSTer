# Audio Boost: why it made games quieter, and the fix

A technical note. The fix is commit `3dc274c` on the branch `exp/audio-boost-dc`; stock z486 and
ao486 have the same code and the same fault.

## The symptom

With Audio Boost at 2x or 4x, The Secret of Monkey Island with MT-32 music gets quieter instead
of louder, and loud passages crack. Title scene, recorded at the MiSTer's analog output, the
recording's own noise removed, change against the same core with Audio Boost off (2026-11-25):

| Core | 2x | 4x |
|---|---:|---:|
| stock z486 `z486_20261012` | -13.0 dB | about -18 dB |
| ao486 nightly of 2026-11-21 | -12.2 dB | about -17 dB |
| this tree with the fix | **+5.9 dB** | **+11.9 dB** |

The 4x figures of the two unfixed cores are rough, because the music is then only a few dB above
the noise of the recording. With Audio Boost off, all of them are equally loud.

## Cause 1: a constant offset in the mix

The Sound Blaster DSP (`sound_dsp.v`) holds its last sample for ever. `MONKEY.EXE` leaves it at
full scale. A real card's output is AC-coupled, so nobody hears it there, and here the MiSTer
framework's DC blocker takes it out of the output. But that blocker comes after the core's own
mixer and Audio Boost, and inside the core the offset is a constant -4 dBFS: full scale at the
SB16 mixer's default voice volume, 20676 of 32768.

This was confirmed with a level meter in the core: in complete silence, after leaving the game,
the DSP reads 0.0 dBFS RMS with every sample at full scale, all other sources read nothing, and
the mix is a constant -4.0 dBFS.

Two things follow:

- On one side of the waveform the mix clips 8.7 dB earlier, even with Audio Boost off.
- Audio Boost (`acompr`) is a compressor. It amplifies by 2 (or 4) up to a knee at 14044 (or 7400)
  and has a slope of only 1/4 (or 1/8) above it. The offset puts everything above the knee, so the
  music gets the slope instead of the gain: -12.0 dB at 2x and -18.1 dB at 4x, as measured.

## Cause 2: the compressor wraps

The curve of `acompr` reaches 32768..32771 at the top of its range, which wraps in 16 bits. Run
over all 65,536 inputs, 5 values at 2x and 41 at 4x (|input| >= 32744) come out with the opposite
sign. A mix that clips sits exactly there, so clipping becomes loud cracks.

## The fix

- `mix_dc_block`: a first-order high-pass at 3.7 Hz on the sum of all sources, before Audio Boost.
  It does what the coupling capacitors of a real card do. A 30-bit accumulator follows the offset
  at 48 kHz; the output is the mix minus the offset, saturated to 16 bits.
- The sum of the sources is 19 bits wide instead of 17, so it cannot wrap before it is clipped.
- `acompr` saturates its result.

`tests/tb_audio_mix.sv` checks both modules: music passes unchanged, with and without the offset,
bass and the corner frequency are right, the sum saturates, and every input of Audio Boost keeps
its sign and never falls. The old `acompr` fails it.
