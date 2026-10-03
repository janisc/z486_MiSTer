"""Make a simulation copy of the GF1 model in which every register starts at zero.

The model relies on the FPGA's power-up state (all registers zero); a Verilog simulator starts
them at X, and the phase ring never leaves X. The copy gets initial values on every reg, and
loops for the register arrays. Usage: gus_sim_prep.py <gf1.v> <out.v>
"""
import re, sys

src, dst = sys.argv[1], sys.argv[2]
out, arrays = [], []
decl = re.compile(r"^(\s*)(output\s+)?reg\b\s*(\[[^\]]+\])?\s*(.*?)\s*([;,])\s*(//.*)?$")
for line in open(src, encoding="utf-8", errors="replace").read().splitlines():
    m = decl.match(line)
    if not m:
        out.append(line)
        continue
    indent, outp, width, names, term, comment = m.groups()
    parts = []
    for n in [p.strip() for p in names.split(",")]:
        a = re.match(r"^(\w+)\s*\[(\d+):(\d+)\]$", n)
        if a:
            arrays.append((a.group(1), int(a.group(2)), int(a.group(3))))
            parts.append(n)
        else:
            parts.append(n if "=" in n else n + " = 0")
    out.append(f"{indent}{outp or ''}reg {width or ''} {', '.join(parts)}{term}")

text = "\n".join(out)
init = ["", "\t// simulation only: FPGA power-up state", "\tinteger sim_i;", "\tinitial begin"]
for name, lo, hi in arrays:
    lo, hi = min(lo, hi), max(lo, hi)
    init.append(f"\t\tfor (sim_i = {lo}; sim_i <= {hi}; sim_i = sim_i + 1) {name}[sim_i] = 0;")
init.append("\tend")
k = text.rindex("endmodule")
open(dst, "w", encoding="utf-8", newline="\n").write(text[:k] + "\n".join(init) + "\n\n" + text[k:] + "\n")
print(f"{dst}: {len(arrays)} arrays initialised")
