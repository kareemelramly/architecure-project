# Mutation test for pipeline.v. Run it on a COPY of Verilog/ (it edits pipeline.v, then restores it).
# Usage: cp -r Verilog /tmp/mut && python3 Testing/mutation_test.py /tmp/mut
import subprocess, shutil, os, sys
os.chdir(sys.argv[1] if len(sys.argv) > 1 else '.')  # a COPY of Verilog/
src=open('pipeline.v').read()
M=[("EX forward rs1 off","assign fwdRs1 = (forwardA == 2'b01) ? regWriteData : ID_EX_RegR1;","assign fwdRs1 = ID_EX_RegR1;"),
("EX forward rs2 off","assign fwdRs2 = (forwardB == 2'b01) ? regWriteData : ID_EX_RegR2;","assign fwdRs2 = ID_EX_RegR2;"),
("ID forward rs1 off","assign idRs1Val = (idForwardA == 2'b10) ? EX_MEM_Result : readData1;","assign idRs1Val = readData1;"),
("ID forward rs2 off","assign idRs2Val = (idForwardB == 2'b10) ? EX_MEM_Result : readData2;","assign idRs2Val = readData2;"),
("ID forward loads too","assign exMemFwdEn = EX_MEM_RegWrite & ~EX_MEM_WbFromMem;","assign exMemFwdEn = EX_MEM_RegWrite;"),
("no load->branch stall","assign stall = (ID_MODE) ? hazardStall : 1'b0;","assign stall = 1'b0;"),
("no squash flush","assign idExFlush = advance & (stall | squash);","assign idExFlush = advance & stall;"),
("wrong-path halt sticks","assign haltNow = haltLatch | (idHalt & ~stall & ~squash);","assign haltNow = haltLatch | (idHalt & ~stall);"),
("ID jalr bit0 kept","((idRs1Val + immGenOut) & ~32'd1)","(idRs1Val + immGenOut)"),
("EX jalr bit0 kept","((fwdRs1 + ID_EX_Imm) & ~32'd1)","(fwdRs1 + ID_EX_Imm)"),
("RegFile writes end of C1","assign regWriteEn = MEM_WB_RegWrite & isFetch;","assign regWriteEn = MEM_WB_RegWrite & advance;"),
("EX_MEM loads end of C1",".load(isFetch),\n        .flush(1'b0),\n        .D({ID_EX_RegWrite",".load(advance),\n        .flush(1'b0),\n        .D({ID_EX_RegWrite"),
("PC ignores stall","assign pcLoad = advance & (redirect | (~stall & ~haltNow));","assign pcLoad = advance & (redirect | ~haltNow);"),
("EX BP update wrong PC",": ID_EX_PC;\n",": pcValue;\n"),
("EX redirect vs PC+4","exIsCtrlFlow & (exActualNextPC != ID_EX_PredNextPC)","exIsCtrlFlow & (exActualNextPC != ID_EX_PC + 32'd4)"),
("ID redirect vs PC+4","idIsCtrlFlow & ~stall & (idActualNextPC != predNextPC)","idIsCtrlFlow & ~stall & (idActualNextPC != pcPlus4)"),
("store data unforwarded","exResult, fwdRs2, ID_EX_Inst[14:12]","exResult, ID_EX_RegR2, ID_EX_Inst[14:12]"),
("MEM_WB load data from result","assign regWriteData = (MEM_WB_WbFromMem) ? MEM_WB_MemOut : MEM_WB_Result;","assign regWriteData = MEM_WB_Result;"),
]
shutil.copy('pipeline.v','/tmp/pipeline.orig')
srcs=[f for f in os.listdir('.') if f.endswith('.v') and '_tb' not in f and 'datapath_board' not in f]
res=[]
try:
  for name,a,b in M:
    assert src.count(a)==1,name
    open('pipeline.v','w').write(src.replace(a,b))
    det=[]
    for m in (1,0):
        r=subprocess.run(['iverilog','-g2012','-Ppipeline_tb.BRANCH_IN_ID=%d'%m,'-s','pipeline_tb','-o','/tmp/mm.out','pipeline_tb.v']+srcs,capture_output=True,text=True)
        try: o=subprocess.run(['vvp','/tmp/mm.out','+stopfail'],capture_output=True,text=True,timeout=120).stdout
        except subprocess.TimeoutExpired: o='__TIMEOUT__'
        if 'ALL ' not in o or '[FAIL]' in o or '__TIMEOUT__' in o: det.append('ID' if m else 'EX')
    res.append((name,det)); print('%-30s %s'%(name, 'DETECTED by '+'+'.join(det) if det else 'SURVIVED'),flush=True)
finally:
  shutil.copy('/tmp/pipeline.orig','pipeline.v')
