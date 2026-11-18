# z486nv: the MiSTer Downloader database

This branch holds only what the MiSTer Downloader and update_all need to install the
z486nv core, the native VGA output fork of z486_MiSTer, and to keep it current. The core,
its sources and its documentation are on the default branch,
[`native-vga`](../native-vga/README.md).

- `db.json` is the database. It lists one file, the core of the current release, which
  the Downloader takes from that release's page.
- `downloader_z486nv.ini` switches it on: copy it to the root of the MiSTer's SD card
  (`/media/fat`), next to `downloader.ini`. From the next run of update_all or of the
  Downloader on, the core is installed in `_Computer` and replaced when a release comes
  out.

The database touches nothing but that one core file. The README of the default branch has
the details.
