# Shared folders with MISTERFS

MISTERFS exposes a MiSTer directory as a DOS network drive. The core uses the existing Main_MiSTer filesystem service and the unmodified ao486 DOS driver; no replacement MiSTer executable is needed.

## Setup

1. Create `/media/fat/games/Z486/shared` on MiSTer and put files there.
2. Copy the current [ao486 MISTERFS.EXE](https://github.com/MiSTer-devel/ao486_MiSTer/blob/master/releases/drv/misterfs.exe) to the DOS disk. The older 2020 installation-floppy driver lacks the directory-search token protocol introduced in Main_MiSTer in March 2022; it can mount but directory listing and copying fail.
3. If using EMM386, reserve the mailbox in `CONFIG.SYS`, preserving any other options:

   ```dos
   DEVICE=C:\DOS\EMM386.EXE X=CE00-CFFF
   ```

   For another memory manager, exclude the same segment range with its equivalent option. Reboot DOS after changing this setting.
4. Choose an unused drive letter and run:

   ```dos
   MISTERFS E /Q
   DIR E:
   ```

Add the driver command to `AUTOEXEC.BAT` if desired. Use DOS-compatible 8.3 filenames. Copy programs to the guest disk before running them when possible. Main_MiSTer's optional `shared_folder` configuration overrides the default path.

The [ao486 shared-folder guide](https://www.jamesfmackenzie.com/howto/how-to-setup-mister-fpga-ao486-core-part-2-sharing-files-with-misterfs-mister-fs/) also applies, with `games/Z486/shared` replacing `games/ao486/shared`.

## Hardware contract

Guest physical addresses `000CE000h–000CFFFFh` map to host DDR addresses `300CE000h–300CFFFFh`. Before activation, reads return all ones and writes are ignored. The stock driver's word write of `A345h` at `CE000h` enables the live window until the next core reset. The activation write itself reaches DDR.

Both L1 caches treat this physical range as uncacheable, including paged aliases. Data reads wait for earlier posted stores to drain; mailbox writes cannot coalesce. Only these 8 KiB bypass UMA ROM write protection. Address decoding follows translation and A20 masking, without adding an issue-stage TLB path.

`main_memory.sv` serializes accesses through the existing framebuffer DDR port, preserving byte enables and returning every response beat for instruction reads. The MiSTer top level and simulation wrapper enable the feature; CPU and other-platform defaults remain disabled. The request/acknowledgement format is unchanged from ao486 and Main_MiSTer.

## Regression tests

From the repository root:

```sh
make -C src/z486/tests test-shared-mailbox
make -C tests test-misterfs
```

The cache tests cover host updates, physical aliases, ordering, non-coalescing activation, ROM boundaries and uncached instruction reads. The DDR tests cover activation, busy backpressure, byte lanes, bursts and reset/re-enable, alongside the existing SVGA tests.

The whole-system simulator optionally links the actual Main_MiSTer `x86_share.cpp` for end-to-end tests. Supply a Main_MiSTer checkout at build time:

```sh
make -C verilator OBJ_DIR=obj_dir_misterfs SIM_CLOCK_HZ=50000000 MISTERFS_MAIN=<Main_MiSTer-checkout>
python3 tests/prepare_misterfs_test.py --disk <dos71-raw-image> --driver <MISTERFS.EXE>
```

The preparation script requires mtools and a DOS 7.1 raw image whose first FAT partition starts at LBA 63. It clones the image, installs the driver and test batch, prepares an isolated host directory and prints the simulator command. The source image is never modified. Only the explicitly exported `--shared-dir` is writable by the guest.

After the guest prints `MISTERFS TEST DONE`, run:

```sh
python3 tests/prepare_misterfs_test.py --verify
```

This checks a 131085-byte binary round-trip, rename, nested-directory creation, deletion and removal. For board testing, give the generated raw disk a `.vhd` extension to match the IDE file selector. Do not reuse a previous run's output directory, since its renamed file would already exist.

Simulator snapshots do not preserve the host service's open file handles. Run shared-folder tests from reset rather than restoring an active transfer.
