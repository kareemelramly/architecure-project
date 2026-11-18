#!/usr/bin/env python3
"""Mutation test: breaks pipeline.v on purpose in several ways and checks that
the test suite catches every break. Run from Verilog/:
    python3 ../Testing/mutation_test.py
Needs iverilog. Each mutant must FAIL at least one program."""
import glob, os, re, subprocess, sys, tempfile

MUTANTS = {
    "no forwarding (rs1)":   ("assign ID_Rs1Data  = (ID_ForwardA) ? MEM_FwdData : ID_ReadData1;",
                              "assign ID_Rs1Data  = ID_ReadData1;"),
    "no forwarding (rs2)":   ("assign ID_Rs2Data  = (ID_ForwardB) ? MEM_FwdData : ID_ReadData2;",
                              "assign ID_Rs2Data  = ID_ReadData2;"),
    "no load forwarding":    ("assign MEM_FwdData = (EX_MEM_WbFromMem) ? memPortDataOut : EX_MEM_Result;",
                              "assign MEM_FwdData = EX_MEM_Result;"),
    "branch not taken in ID":("assign IF_PcLoad = (isC0 | (isC1 & ID_PcSrc)) & ~haltState;",
                              "assign IF_PcLoad = isC0 & ~haltState;"),
    "RF written in C1":      ("assign WB_RegWriteEn = MEM_WB_RegWrite & isC0;",
                              "assign WB_RegWriteEn = MEM_WB_RegWrite & isC1;"),
    "EBREAK does not halt":  ("assign ID_HaltSet = isC1 & ID_HaltValid;",
                              "assign ID_HaltSet = 1'b0;"),
    "JALR bit 0 kept":       ("{ID_JalrSum[31:1], 1'b0}", "ID_JalrSum"),
    "MEM_WB in C0":          (".load(isC1),\n        .flush(1'b0),\n        .D(MEM_WB_In),",
                              ".load(isC0),\n        .flush(1'b0),\n        .D(MEM_WB_In),"),
}

PROGS = ["../Testing/programs/full_test.hex"]

def run(src_dir, prog):
    rtl = [os.path.join(src_dir, f) for f in sorted(os.listdir(src_dir))
           if f.endswith(".v") and not f.endswith("_tb.v")
           and f not in ("datapath_board_pipelined.v", "SevenSegDecimal8.v",
                         "Debounce.v")]
    out = os.path.join(src_dir, "sim.out")
    subprocess.run(["iverilog", "-g2012", "-I", src_dir, "-s", "pipeline_tb",
                    "-Ppipeline_tb.VERBOSE=0",
                    "-Ppipeline_tb.MAX_CYCLES=3000",
                    '-Ppipeline_tb.PROG="%s"' % os.path.abspath(prog),
                    "-o", out, os.path.join(src_dir, "pipeline_tb.v")] + rtl,
                   check=True, capture_output=True)
    res = subprocess.run(["vvp", "-n", out], capture_output=True, text=True)
    return "TEST PASSED" in res.stdout

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
