# MISTERFS: differences from ao486

Use the current ao486 `MISTERFS.EXE` and Main_MiSTer's existing shared-folder service; no replacement MiSTer binary is needed.

- The default host folder is `/media/fat/games/Z486/shared`, instead of `games/ao486/shared`. Main_MiSTer's `shared_folder` override still applies.
- The mailbox and DOS commands are unchanged. Follow the [ao486 setup guide](https://www.jamesfmackenzie.com/howto/how-to-setup-mister-fpga-ao486-core-part-2-sharing-files-with-misterfs-mister-fs/), including its memory-manager exclusions.

Use the [current ao486 driver](https://github.com/MiSTer-devel/ao486_MiSTer/blob/master/releases/drv/misterfs.exe), not the obsolete 2020 installation-floppy version.
