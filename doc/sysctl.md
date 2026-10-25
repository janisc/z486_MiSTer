# CPU speed / SYSCTL: differences from ao486

- The OSD adds 6/5/4/3 MHz-equivalent rates to Full/56/30/15. These throttle execution, not peripheral clocks; old saved OSD settings retain their meanings.
- Existing ao486 SYSCTL commands still select the original four rates, and `SYSCTL MENU` restores OSD control. Use the OSD for the new rates: the current DOS utility does not support them. Do not pass an unsupported rate to the old utility; it falls back to Full.
- Software can identify z486 through byte reads at `888Ah–888Dh` returning `Z486`, `888Eh` returning capability ABI revision `1`, and `888Fh` returning speed-mask `FFh`. Check the signature, supported ABI and mask before using extended selectors; unknown cores must retain the four-speed fallback.
- The existing `OUTW 8888h, A100h | control` protocol is unchanged. With software control enabled (bit 7), selectors `0/1/2/3` still mean Full/15/30/56; selectors `4/5/6/7` add 6/5/4/3. Bit 2 extends the selector; it is not a cache bit.
- Legacy cache-control bits 4/5 are stored but ignored by z486; use the OSD L1-cache switch instead.
