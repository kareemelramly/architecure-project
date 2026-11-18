# Mutation test for the 5-stage pipeline. Run it on a COPY of Verilog/ (it edits files, then restores them).
# Usage: cp -r Verilog /tmp/mut && python3 Testing/mutation_test.py /tmp/mut
import subprocess, shutil, os, sys
os.chdir(sys.argv[1] if len(sys.argv) > 1 else '.')
P, H = 'pipeline.v', 'HazardUnit.v'
M = [
 (P,"EX forward rs1 from EX_MEM off","(forwardA == 2'b10) ? EX_MEM_Result :","1'b0 ? EX_MEM_Result :"),
 (P,"EX forward rs1 from MEM_WB off","(forwardA == 2'b01) ? regWriteData  :","1'b0 ? regWriteData  :"),
 (P,"EX forward rs2 from EX_MEM off","(forwardB == 2'b10) ? EX_MEM_Result :","1'b0 ? EX_MEM_Result :"),
 (P,"EX forward rs2 from MEM_WB off","(forwardB == 2'b01) ? regWriteData  :","1'b0 ? regWriteData  :"),
 (P,"ID forward rs1 from EX_MEM off","(idForwardA == 2'b10) ? EX_MEM_Result :","1'b0 ? EX_MEM_Result :"),
 (P,"ID forward rs2 from EX_MEM off","(idForwardB == 2'b10) ? EX_MEM_Result :","1'b0 ? EX_MEM_Result :"),
 (P,"ID forward rs1 from MEM_WB off","(idForwardA == 2'b01) ? regWriteData  : readData1","readData1"),
 (P,"ID forward also forwards loads","assign exMemFwdEn = EX_MEM_RegWrite & ~EX_MEM_WbFromMem;","assign exMemFwdEn = EX_MEM_RegWrite;"),
 (H,"no load-use stall","assign loadUseStall = idExMemRead && matchEx;","assign loadUseStall = 1'b0;"),
 (H,"no branch stall","assign branchStall  = readsInId &&","assign branchStall  = 1'b0 && readsInId &&"),
 (P,"IF_ID not flushed on redirect","assign ifIdFlush = advance & (redirect | haltNow);","assign ifIdFlush = advance & haltNow;"),
 (P,"halt ignores stall","assign haltNow = haltLatch | (idHalt & ~stall);","assign haltNow = haltLatch | idHalt;"),
 (P,"JALR target bit 0 kept","((idRs1Val + immGenOut) & ~32'd1)","(idRs1Val + immGenOut)"),
 (P,"RegFile writes at end of C1","assign regWriteEn = MEM_WB_RegWrite & isFetch;","assign regWriteEn = MEM_WB_RegWrite & advance;"),
 (P,"PC ignores stall","assign pcLoad = advance & (redirect | (~stall & ~haltNow));","assign pcLoad = advance & (redirect | ~haltNow);"),
 (P,"predictor updated with wrong PC",".updatePC(IF_ID_PC)",".updatePC(pcValue)"),
 (P,"redirect compared with PC+4","(idActualNextPC != IF_ID_PredNextPC)","(idActualNextPC != IF_ID_PC + 32'd4)"),
 (P,"store data not forwarded","exResult, fwdRs2, ID_EX_Inst[14:12]","exResult, ID_EX_RegR2, ID_EX_Inst[14:12]"),
 (P,"load data replaced by address","assign regWriteData = (MEM_WB_WbFromMem) ? MEM_WB_MemOut : MEM_WB_Result;","assign regWriteData = MEM_WB_Result;"),
]
for f in (P, H): shutil.copy(f, '/tmp/'+f+'.orig')
srcs=[f for f in os.listdir('.') if f.endswith('.v') and '_tb' not in f and 'datapath_board' not in f and not f.startswith(('Four_','Nbit_mux','Nbit_shift'))]
try:
  for f,name,a,b in M:
    s=open(f).read(); assert s.count(a)==1,name
    open(f,'w').write(s.replace(a,b))
    subprocess.run(['iverilog','-g2012','-s','pipeline_tb','-o','/tmp/mm.out','pipeline_tb.v']+srcs,capture_output=True,text=True)
    try: o=subprocess.run(['vvp','/tmp/mm.out','+stopfail'],capture_output=True,text=True,timeout=120).stdout
    except subprocess.TimeoutExpired: o='__TIMEOUT__'
    det = 'ALL ' not in o or '[FAIL]' in o or '__TIMEOUT__' in o
    print('%-36s %s'%(name,'DETECTED' if det else 'SURVIVED'),flush=True)
    shutil.copy('/tmp/'+f+'.orig',f)
finally:
  for f in (P,H): shutil.copy('/tmp/'+f+'.orig',f)
