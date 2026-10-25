#!/usr/bin/env python3
"""Prepare an isolated DOS/MISTERFS integration test; never edit source media.

Run the printed simulator command, then use --verify to check host results.
Requires mtools, a DOS 7.1 image, and a current unmodified MISTERFS driver.
"""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, default=ROOT / "build/misterfs/integration")
    parser.add_argument("--disk", type=Path, help="DOS 7.1 raw disk; first FAT partition at LBA 63")
    drivers = parser.add_mutually_exclusive_group()
    drivers.add_argument("--driver", type=Path, help="current unmodified ao486 MISTERFS.EXE")
    drivers.add_argument("--floppy", type=Path, help="extract driver from an installation floppy instead")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    work = args.work.resolve()
    shared = work / "shared/MFSTEST"
    payload = bytes((i * 73 + (i >> 8) * 19) & 255 for i in range(131085))
    if args.verify:
        for name in ("BACK.BIN", "RENAMED.BIN"):
            assert (shared / name).read_bytes() == payload, f"bad round-trip: {name}"
        assert (shared / "PASS.TXT").read_text().strip() == "MISTERFS PASS"
        assert not (shared / "OLD.BIN").exists(), "rename did not remove old name"
        assert not (shared / "SUBDIR").exists(), "directory cleanup failed"
        print("MISTERFS integration PASS: 131085-byte binary round-trip, rename, mkdir, delete, rmdir")
        return
    if not args.disk or not (args.driver or args.floppy):
        parser.error("preparation requires --disk and either --driver or --floppy")
    # Refuse to overwrite a previous run (or an accidentally selected real disk).
    work.mkdir(parents=True, exist_ok=False)
    shared.mkdir(parents=True)
    (shared / "INPUT.BIN").write_bytes(payload)
    disk = work / "dos.img"
    run("cp", "--reflink=auto", str(args.disk.resolve()), str(disk))
    target = str(disk) + "@@32256"  # DOS 7.1 image: first partition at LBA 63.
    config = run("mtype", "-i", target, "::CONFIG.SYS").decode("ascii")
    config = config.replace("C:\\DOS\\EMM386.EXE", "C:\\DOS\\EMM386.EXE X=CE00-CFFF")
    (work / "CONFIG.SYS").write_bytes(config.encode("ascii"))
    driver = (run("mtype", "-i", str(args.floppy.resolve()), "::MISTERFS.EXE")
              if args.floppy else
              args.driver.read_bytes())
    (work / "MISTERFS.EXE").write_bytes(driver)
    batch = r"""@ECHO OFF
SET PATH=C:\DOS
C:\MISTERFS.EXE E /Q
IF ERRORLEVEL 1 GOTO FAIL
DIR E:\MFSTEST
COPY /B E:\MFSTEST\INPUT.BIN C:\STAGED.BIN
IF ERRORLEVEL 1 GOTO FAIL
COPY /B C:\STAGED.BIN E:\MFSTEST\BACK.BIN
IF ERRORLEVEL 1 GOTO FAIL
COPY /B C:\STAGED.BIN E:\MFSTEST\OLD.BIN
IF ERRORLEVEL 1 GOTO FAIL
REN E:\MFSTEST\OLD.BIN RENAMED.BIN
IF ERRORLEVEL 1 GOTO FAIL
MD E:\MFSTEST\SUBDIR
IF ERRORLEVEL 1 GOTO FAIL
COPY /B C:\STAGED.BIN E:\MFSTEST\SUBDIR\TEMP.BIN
IF ERRORLEVEL 1 GOTO FAIL
DEL E:\MFSTEST\SUBDIR\TEMP.BIN
RD E:\MFSTEST\SUBDIR
IF ERRORLEVEL 1 GOTO FAIL
ECHO MISTERFS PASS>E:\MFSTEST\PASS.TXT
ECHO MISTERFS TEST DONE
GOTO END
:FAIL
ECHO MISTERFS TEST FAILED
:END
"""
    (work / "AUTOEXEC.BAT").write_bytes(batch.replace("\n", "\r\n").encode("ascii"))
    for name in ("CONFIG.SYS", "AUTOEXEC.BAT", "MISTERFS.EXE"):
        run("mcopy", "-o", "-i", target, str(work / name), "::" + name)
    print(f"Prepared {work}; source media unchanged.")
    print("From verilator/:")
    print(f"./obj_dir_misterfs/Vz486_mister_sim --headless --no-audio-clock "
          f"--disk {disk} --shared-dir {work / 'shared'} "
          '--rtc "2026-10-25 12:00:00" --stop-on-text "MISTERFS TEST DONE"')


if __name__ == "__main__":
    main()
