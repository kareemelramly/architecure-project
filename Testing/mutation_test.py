#!/usr/bin/env python3
"""Mutation test: breaks pipeline.v on purpose in several ways and checks that
the test suite catches every break. Run from Verilog/:
    python3 ../Testing/mutation_test.py
Needs iverilog. Each mutant must FAIL at least one program."""
import glob, os, re, subprocess, sys, tempfile

MUTANTS = {
    "no forwarding (rs1)":      ("assign fwdRs1 = (forwardA) ? regWriteData : ID_EX_RegR1;",
                                 "assign fwdRs1 = ID_EX_RegR1;"),
    "no forwarding (rs2)":      ("assign fwdRs2 = (forwardB) ? regWriteData : ID_EX_RegR2;",
                                 "assign fwdRs2 = ID_EX_RegR2;"),
    "no wrong-path flush":      ("assign ifIdFlush = isC0 & (pcSrc | haltLatch);",
                                 "assign ifIdFlush = isC0 & haltLatch;"),
    "RF written in C1":         ("assign regWriteEn = MEM_WB_RegWrite & isC0;",
                                 "assign regWriteEn = MEM_WB_RegWrite & isC1;"),
    "EBREAK does not halt":     ("assign pcLoad = isC0 & ~haltLatch;",
                                 "assign pcLoad = isC0;"),
    "JALR bit 0 kept":          ("{aluOutput[31:1], 1'b0}", "aluOutput"),
    "MEM_WB in C0":             (".load(isC1),\n        .flush(1'b0),\n        .D(memWbIn),",
                                 ".load(isC0),\n        .flush(1'b0),\n        .D(memWbIn),"),
}

PROGS = (["../Testing/programs/%s.hex" % p for p in
          ("all_instr", "hazards", "nops_halt", "timing")] +
         sorted(glob.glob("../Testing/compliance/*.hex")))

def run(src_dir, prog):
    rtl = [os.path.join(src_dir, f) for f in sorted(os.listdir(src_dir))
           if f.endswith(".v") and not f.endswith("_tb.v")
           and f not in ("datapath_board_pipelined.v", "SevenSegDecimal8.v",
                         "Debounce.v")]
    timing = "1" if prog.endswith("timing.hex") else "0"
    out = os.path.join(src_dir, "sim.out")
    subprocess.run(["iverilog", "-g2012", "-I", src_dir, "-s", "pipeline_tb",
                    "-Ppipeline_tb.ADDR_BITS=13",
                    "-Ppipeline_tb.MAX_CYCLES=6000",
                    "-Ppipeline_tb.CHECK_TIMING=" + timing,
                    '-Ppipeline_tb.PROG="%s"' % os.path.abspath(prog),
                    "-o", out, "pipeline_tb.v"] + rtl, check=True)
    res = subprocess.run(["vvp", "-n", out], capture_output=True, text=True)
    return "PASS" in res.stdout

def main():
    caught = 0
    for name, (old, new) in MUTANTS.items():
        with tempfile.TemporaryDirectory() as tmp:
            for f in os.listdir("."):
                if f.endswith((".v", ".vh")):
                    text = open(f).read()
                    if f == "pipeline.v":
                        assert old in text, name
                        text = text.replace(old, new)
                    open(os.path.join(tmp, f), "w").write(text)
            # stop at the first program that catches the mutant
            failed = next((p for p in PROGS if not run(tmp, p)), None)
        ok = failed is not None
        caught += ok
        print("%-24s %s %s" % (name, "CAUGHT by" if ok else "MISSED",
                               os.path.basename(failed or "")))
    print("%d / %d mutants caught" % (caught, len(MUTANTS)))
    sys.exit(0 if caught == len(MUTANTS) else 1)

if __name__ == "__main__":
    main()
