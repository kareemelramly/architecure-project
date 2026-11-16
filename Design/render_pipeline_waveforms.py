"""Render the MS3 pipeline waveforms (Testing/waveforms/wave_*.vcd) to PNG.
Usage (from the repo root): python3 Design/render_pipeline_waveforms.py"""
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

root = Path(__file__).resolve().parents[1]
wdir = root / "Testing" / "waveforms"

def parse(path):
    ids, vals, t = {}, {}, 0
    for line in path.read_text().splitlines():
        p = line.split()
        if not p:
            continue
        if p[0] == "$var":
            ids[p[3]] = p[4]
            vals.setdefault(p[4], [])
        elif p[0].startswith("#"):
            t = int(p[0][1:])
        elif p[0][0] == "b" and len(p) == 2 and p[1] in ids:
            vals[ids[p[1]]].append((t, p[0][1:]))
        elif p[0][0] in "01xz" and p[0][1:] in ids:
            vals[ids[p[0][1:]]].append((t, p[0][0]))
    return vals

def toint(v):
    try:
        return int(v, 2)
    except ValueError:
        return None

def disasm(w):
    if w is None:
        return "x"
    if w == 0:
        return "bubble"
    op = w & 0x7F
    rd, f3, rs1, rs2 = (w >> 7) & 31, (w >> 12) & 7, (w >> 15) & 31, (w >> 20) & 31
    imm = (w >> 20) - (4096 if w >> 31 else 0)
    if op == 0x13:
        return f"addi x{rd},x{rs1},{imm}"
    if op == 0x03:
        return f"lw x{rd},{imm}(x{rs1})"
    if op == 0x63:
        return ("beq" if f3 == 0 else "bne") + f" x{rs1},x{rs2}"
    if w == 0x00100073:
        return "ebreak"
    return f"{w:08x}"

ROWS = [("clk", "bit"), ("phase", "bit"), ("pcValue", "hex"), ("idInst", "inst"),
        ("ID_EX_Inst", "inst"), ("stall", "bit"), ("redirect", "bit"),
        ("squash", "bit"), ("predictTakenEff", "bit"), ("regWriteEn", "bit"),
        ("MEM_WB_Rd", "dec"), ("regWriteData", "hex"), ("haltLatch", "bit")]

def render(vcd, title, out, tmax):
    v = parse(vcd)
    rows = [r for r in ROWS if r[0] in v and v[r[0]]]
    ph = v["phase"] + [(tmax, None)]
    c1 = [(t0, t1) for (t0, a), (t1, _) in zip(ph, ph[1:]) if a == "1"]
    fig, ax = plt.subplots(figsize=(17, 0.55 * len(rows) + 1.2))
    for i, (name, kind) in enumerate(rows):
        y = (len(rows) - 1 - i) * 1.0
        ch = [c for c in v[name] if c[0] <= tmax] + [(tmax, None)]
        for (t0, a), (t1, _) in zip(ch, ch[1:]):
            if t1 <= t0:
                continue
            if kind == "bit":
                lvl = 0.7 if a == "1" else 0.1
                ax.plot([t0, t1], [y + lvl] * 2, color="#1d4ed8", lw=1.4)
                ax.plot([t1, t1], [y + 0.1, y + 0.7], color="#1d4ed8", lw=0.6)
                if name in ("stall", "redirect", "squash") and a == "1":
                    # shade only C1 (phase = 1): the value used at the end of the slot
                    for p0, p1 in c1:
                        lo, hi = max(t0, p0), min(t1, p1)
                        if hi > lo:
                            ax.axvspan(lo, hi, color="#fde68a", alpha=0.35, lw=0)
            else:
                ax.fill_between([t0, t1], y + 0.1, y + 0.7, color="#eff6ff", ec="#1e3a8a", lw=0.8)
                n = toint(a)
                txt = disasm(n) if kind == "inst" else ("x" if n is None else (str(n) if kind == "dec" else f"{n:x}"))
                if t1 - t0 >= 18000:
                    ax.text((t0 + t1) / 2, y + 0.4, txt, ha="center", va="center", fontsize=7.2)
        ax.text(-1500, y + 0.4, name, ha="right", va="center", fontsize=9, color="#1f2937")
    ax.set_xlim(0, tmax)
    ax.set_ylim(-0.2, len(rows))
    ax.set_yticks([])
    ax.set_xticks(range(0, tmax + 1, 20000))
    ax.set_xticklabels([str(t // 1000) for t in range(0, tmax + 1, 20000)], fontsize=8)
    ax.set_xlabel("time (ns); one slot = C0 + C1 = 20 ns; shading = stall / redirect / squash during C1, when PC and ID_EX load", fontsize=9)
    ax.set_title(title, fontsize=11, color="#1e3a8a", loc="left")
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    plt.close(fig)

cases = [("wave_id.vcd", "BRANCH_IN_ID = 1: lw directly before beq stalls one slot; branches redirect with no squash; EBREAK halts", "wave_branch_in_id.png"),
         ("wave_ex_nobp.vcd", "BRANCH_IN_ID = 0, BP off: every taken branch squashes the Stage 0 instruction (1-slot penalty)", "wave_ex_no_predictor.png"),
         ("wave_ex_bp.vcd", "BRANCH_IN_ID = 0, BP on: after the first iteration the taken branches are predicted (no squash)", "wave_ex_predictor.png")]
for vcd, title, out in cases:
    render(wdir / vcd, title, wdir / out, 440000)
    print("wrote", out)
