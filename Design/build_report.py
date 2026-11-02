from pathlib import Path
import re
from PIL import Image as PILImage
from reportlab.platypus import SimpleDocTemplate,Paragraph,Spacer,Table,TableStyle,PageBreak,Image,Preformatted
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet,ParagraphStyle
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from pypdf import PdfReader,PdfWriter
root=Path(__file__).resolve().parents[1];out=root/'output/pdf';tmp=root/'tmp/pdfs';wf=root/'Testing/waveforms'
out.mkdir(parents=True,exist_ok=True);tmp.mkdir(parents=True,exist_ok=True)
log=(root/'Testing/documentation_test_results.txt').read_text();assert 'SIMULATION PASSED' in log and '[FAIL]' not in log
checks=log.count('[ OK ]');cycles=int(re.search(r'Cycles until halt\s*:\s*(\d+)',log)[1])
styles=getSampleStyleSheet()
for name,font,size,leading,color in [('BodyX','Helvetica',10.2,14.7,'#273d50'),('HeadX','Helvetica-Bold',22,27,'#12364d'),('SubX','Helvetica-Bold',12,16,'#087e8b'),('CapX','Helvetica',8.8,12,'#48647a'),('CodeX','Courier',7.5,10.5,'#203b50')]:
 styles.add(ParagraphStyle(name=name,fontName=font,fontSize=size,leading=leading,textColor=colors.HexColor(color),spaceAfter=11))
story=[]
def p(s):story.append(Paragraph(s,styles['BodyX']))
def h(s):story.append(Paragraph(s,styles['HeadX']))
def sub(s):story.append(Paragraph(s,styles['SubX']))
def cap(s):story.append(Paragraph(s,styles['CapX']))
def page():story.append(PageBreak())
def code(s):story.append(Preformatted(s,styles['CodeX']))
def table(rows,widths):
 cells=[[Paragraph(str(c),styles['CapX']) for c in r] for r in rows];t=Table(cells,colWidths=widths,hAlign='LEFT')
 t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#e4eff3')),('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),8),('RIGHTPADDING',(0,0),(-1,-1),8),('TOPPADDING',(0,0),(-1,-1),7),('BOTTOMPADDING',(0,0),(-1,-1),3),('LINEBELOW',(0,0),(-1,-1),.35,colors.HexColor('#d6e2e9'))]));story.extend([t,Spacer(1,12)])
def image(path,width=499):
 im=PILImage.open(path);story.append(Image(str(path),width=width,height=width*im.height/im.width))

h('femtoRV32')
sub('Single-Cycle RISC-V Processor')
p('Design, implementation and verification report<br/>2 November 2026')
story.append(Spacer(1,15))
p('<b>Kareem Abdellatif</b><br/><b>Mohamed Aboelfotouh</b><br/><b>Moustafa Fayed</b>')
story.append(Spacer(1,15))
p('A 32-bit educational single-cycle processor with separate instruction and data memories. Normal instructions pass through combinational fetch, decode, execution, memory access and writeback within one clock interval. Architectural state updates on the rising edge. ECALL and EBREAK stop PC advancement in this project execution model.')
table([['Verification snapshot','Fresh run of current sources'],['Directed coverage','40 RV32I + 8 RV32M instructions; FENCE.TSO and PAUSE additionally checked'],['Simulation',f'{checks} passing checks; zero failed checks; {cycles} cycles to ECALL'],['Execution bounds','Main program stops at byte PC 468; separate EBREAK reset test'],['Tools','Icarus Verilog 12.0; Yosys 0.52; Graphviz']], [140,359])
sub('Contents')
p('1. Datapath architecture and block diagram<br/>2. Implementation and control organization<br/>3. Memory and system implementation<br/>4. Verification strategy and results<br/>5-6. Team waveform screenshot and test interpretation<br/>7. Integration issues, assumptions and limitations<br/>8. Reproduction commands<br/>Appendix A. Original team block diagram<br/>Appendix B. Original datapath schematic<br/>Appendix C. Original GTKWave screenshot')
cap('Evidence comes from the current RTL and a fresh simulation. The waveform screenshot is the team-owned existing GTKWave image, reproduced directly from Testing/waveforms/waveform.png. Processor RTL and the main testbench were not modified for documentation.')

page();h('1 / Datapath architecture')
p('The instruction selects source/destination registers, generates an immediate and drives the main control and ALU decoder. The datapath uses two operand muxes, a four-source writeback mux and a dedicated comparator for signed/unsigned branch decisions.')
image(root/'Design/Single-Cycle_Block_Diagram.png')
cap('Figure 1. Original team block diagram, reproduced directly from Design/Single-Cycle_Block_Diagram.png. No blocks, wiring or labels have been redrawn. Appendix A reproduces the same image at a larger page size for zooming; Appendix B contains the existing Design/datapath_schematic.pdf.')
sub('PC routing and writeback')
code('pcPlus4    = pcValue + 4\njumpTarget = pcValue + immGenOut\njalrTarget = (readData1 + immGenOut) & ~1\npcInput    = isJalr ? jalrTarget :\n             (isJal || takeBranch) ? jumpTarget : pcPlus4')
p('JAL/JALR write PC+4 to rd. LUI writes the upper immediate directly. AUIPC selects the current PC as ALU input A and the immediate as input B. The PC register is enabled by ~halt. Branch immediates are already byte-scaled by ImmGen; no additional shift is applied.')

page();h('2 / Implementation')
table([['Module','Responsibility'],['datapath.v','Connects fetch, register file, operand muxes, ALU, memory, PC and writeback routing.'],['control_unit.v / defines.vh','Safe control defaults, opcode classes and shared ALU/writeback constants.'],['alu_unit.v / ALU.v','funct3/funct7 decoding; 5-bit ALU selection covers base operations and eight RV32M operations.'],['ImmGen.v / BranchUnit.v','I/S/B/U/J immediates; six signed/unsigned branch conditions.'],['RegFile.v','Combinational read ports and rising-edge writes. x0 is constant, without writable storage.'],['InstMem.v / DataMem.v','128 instruction words and 64 data words, initialized with the directed program and test data.'],['N_bit_register.v / DFlipFlop.v / mux2x1.v','Structural load-enabled registers with asynchronous reset.']], [164,335])
sub('Control encoding')
table([['Signal','Meaning'],['aluOp[1:0]','00: address/add; 01: branch subtraction; 10: register/RV32M; 11: immediate ALU.'],['memToReg[1:0]','00: ALU; 01: memory; 10: PC+4; 11: immediate.'],['aluSrcA / aluSource','Select PC vs rs1, and immediate vs rs2, respectively.'],['branch / isJal / isJalr','Select branch comparison and jump routing.']], [164,335])
sub('RV32M arithmetic')
p('High-product multiplication distinguishes signed-signed, signed-unsigned and unsigned-unsigned operands. Division/remainder explicitly handle zero divisors and INT_MIN / -1 overflow. DIV/DIVU by zero return FFFFFFFF; REM/REMU by zero return the dividend. Signed overflow returns INT_MIN for DIV and zero for REM. These operators are combinational; timing closure has not been measured.')

page();h('3 / Memory and system implementation')
p('The processor supports byte, halfword and word memory accesses, together with system and synchronization instructions. This section describes memory lane selection, extension/masking and system control in the integrated team design.')
sub('Byte and halfword loads')
p('DataMem selects mem[addr[7:2]]. addr[1:0] selects a byte; addr[1] selects the lower or upper halfword. LB/LH repeat the selected sign bit. LBU/LHU zero-fill the upper bits. The organization is little-endian.')
table([['Operation','Selected value / address','Expected load'],['LB','B2 at byte 20','FFFFFFB2'],['LB','7C at byte 23','0000007C'],['LBU','B2 at byte 20','000000B2'],['LH','F1B2 at byte 20','FFFFF1B2'],['LH','7C8A at byte 22','00007C8A'],['LHU','F1B2 at byte 20','0000F1B2']], [95,214,190])
sub('Partial-word stores')
p('SB replaces one byte with dataIn[7:0]. SH replaces the selected halfword with dataIn[15:0]. Unaddressed bytes retain their old values. Four SB operations build 0x0AFB140A in mem[6]; two SH operations build 0x0014FFFB in mem[7]. LW reads both words back. The source word mem[5] remains 0x7C8AF1B2.')
sub('System and synchronization')
p('FENCE/FENCE.TSO/PAUSE leave side-effect controls disabled and advance normally. SYSTEM decoding recognizes ECALL/EBREAK from funct3, rd, rs1 and upper immediate fields and asserts halt. Neither instruction writes registers or memory. A CSRRW encoding is checked to ensure it does not incorrectly halt; CSR execution itself is unsupported.')

page();h('4 / Verification and results')
p('The testbench uses a 20 ns clock period. A rising-edge monitor records the instruction index and independent expected values, waits 1 ns for state updates, then checks the next PC and register/memory result. Negative-edge logging produces a cycle trace. Transient results are saved before later instructions reuse the registers.')
table([['Test family','Observed result'],['Main program',f'{cycles} cycles until ECALL; PC remains 468 for five additional rising edges.'],['Branch / control flow','Score 70; trap count 0. All six branch conditions, an unsigned not-taken case, jump links and skipped traps pass.'],['Loads / stores','Sign/zero extension, all byte lanes, both halfword positions and LW readback pass.'],['Base ALU / upper immediate','Register ALU, immediate ALU/shifts, LUI, AUIPC, JAL and JALR checks pass.'],['RV32M','Eight operations tested for (-1,-1), (-20,7), (-20,0) and (INT_MIN,-1).'],['Synchronization / SYSTEM','FENCE/FENCE.TSO/PAUSE decode and execution checks pass; ECALL and separate EBREAK halt tests pass.'],['Coverage words','RV32I low word FFFFFFFF; RV32I upper byte FF; RV32M byte FF.']], [143,356])
sub('Fresh run summary')
code(f'Passing [ OK ] checks: {checks}\nFailed [FAIL] checks:  0\nCycles until halt:     {cycles}\nECALL byte PC:         468\nSIMULATION PASSED:\nAll 40 RV32I + 8 RV32M instructions checked!')
p('Evidence: Testing/documentation_test_results.txt and Testing/datapath.vcd. Yosys hierarchy elaboration and RTL schematic generation also complete successfully; the log is Testing/documentation_yosys.log.')
cap('The base count includes FENCE/ECALL/EBREAK. FENCE.TSO and PAUSE share the FENCE coverage class and also have separate decode checks. Set coverage bits establish directed instruction coverage, not exhaustive ISA compliance, formal proof or physical timing closure.')

page();h('5 / Team waveform screenshot')
p('The following is the existing GTKWave screenshot saved by the team in Testing/waveforms/waveform.png. It is reproduced without redrawing traces or changing signal values. Appendix C provides the same screenshot on a larger page for zooming.')
image(wf/'waveform.png')
cap('Figure 2. Original GTKWave screenshot of Testing/datapath.vcd. The visible window covers approximately 0-930 ns. The signal panel includes the PC, instruction, ALU inputs/output, load/store controls, writeback and branch decision. GTKWave displays several buses in decimal; narrow bus values are abbreviated in the original screenshot.')
sub('Visible load/store behavior')
p('In the visible load sequence, dataMemoryOut and regWriteData include -78 (LB of 0xB2), 124 (LB of 0x7C), 178 and 241 (LBU). LH/LHU results follow. memRead asserts for loads. The subsequent store sequence asserts memWrite while aluOutput addresses the selected byte and halfword lanes. These observations are backed by the exact result checks in the simulation log.')
sub('Visible control flow')
p('The early PC sequence skips trap instructions after taken branches. takeBranch pulses align with branch decisions. The screenshot also shows normal PC progression through the synchronization instructions, followed by the subsequent arithmetic/store operations.')

page();h('6 / Interpreting the project evidence')
p('The screenshot is an overview of the early program. Its visible range does not show the final ECALL or the separate EBREAK phase. Those outcomes are established by the saved self-checking simulation results and by the complete VCD, rather than being inferred from an unseen part of the image.')
table([['Evidence','What it establishes'],['Original GTKWave screenshot','Early PC/branch behavior, memory-read/write controls, ALU activity and register writeback in the displayed time range.'],['documentation_test_results.txt','Exact load/store expected values, branch score 70, trap count 0, all instruction coverage checks and final PASS.'],['datapath.vcd','Complete captured signal trace, including later RV32M execution, ECALL halt and the separate EBREAK test.'],['Original block diagram','The team-owned proposed datapath structure, routing and signal labels.'],['Original datapath schematic','Existing Yosys module-level connectivity, preserved as a vector PDF.']], [155,344])
sub('ECALL and EBREAK checks')
p('The main program reaches byte PC 468 with instruction 0x00000073. halt asserts and pcLoad clears. Five additional rising edges leave the PC unchanged. The testbench then disables its main monitor, asserts reset and places 0x00100073 at instruction word zero. After reset release, five rising edges leave the PC at zero with halt asserted and no register write.')
sub('Memory results checked in the log')
code('LB  byte 0:        FFFFFFB2\nLBU byte 0:        000000B2\nLH  lower half:    FFFFF1B2\nLHU lower half:    0000F1B2\nSB word readback:  0AFB140A\nSH word readback:  0014FFFB')
cap('The figures in this revision are taken from the team-owned saved artifacts. No new datapath layout, substitute schematic or reconstructed waveform is included.')

page();h('7 / Issues and solutions')
table([['Issue','Resolution in the integrated implementation'],['Duplicate net / control widths','Keep one two-bit cu_memToReg and an explicit two-bit cu_aluOp; compare the full ten-bit side-effect control vector.'],['Unknown module types','Compile all RTL files together from Verilog/ so dependencies and defines.vh resolve.'],['Instruction-test gaps','Add SUB, AND, OR and JAL cases; check individual results and next PC as well as final state.'],['Reused destination registers','Save transient LB/SLT/SLTU/SLTI values at the relevant instruction boundary.'],['Writes to register zero','Generate writable registers only for x1-x31; assign d_reg[0] to constant zero.'],['RV32M corner cases','Explicit divide-by-zero and signed-overflow handling supplies deterministic results.']], [150,349])
sub('Assumptions and known limitations')
p('Memory is little-endian: 512 instruction bytes and 256 data bytes. High address bits are discarded and therefore alias. Aligned halfword/word accesses and 32-bit instruction alignment are assumed; cross-word accesses and misalignment traps are absent.')
p('The processor has no CSRs, interrupts, privilege modes, virtual memory or illegal-instruction trap. Decoders use inst[6:2] and do not fully validate every encoding. Unsupported SYSTEM operations are effectively ignored. Compressed, atomic and floating-point instructions are absent.')
p('FENCE/FENCE.TSO/PAUSE are NOPs in the single-hart, unbuffered memory model. ECALL/EBREAK stop the PC rather than invoking a handler. Data memory initializes once and is not cleared by CPU reset.')
p('The board wrapper is commented out. FPGA resource use, clock frequency, timing closure and hardware operation are not demonstrated. Combinational RV32M division may impose a long critical path. The top exposes only clock/reset and is observed through internal simulation signals.')

page();h('8 / Reproduce the evidence')
p('Run from the Verilog directory in WSL. Icarus compiles/simulates the design. Yosys elaborates the RTL and Graphviz renders the schematic. The additional capture module only observes signals.')
code('cd "/mnt/d/New folder/architecure-project/Verilog"\n\niverilog -g2012 -Wall -s datapath_tb -s waveform_capture \\\n  -o ../Testing/waveform_sim.out *.v \\\n  ../Testing/waveform_capture.v\nvvp ../Testing/waveform_sim.out \\\n  | tee ../Testing/documentation_test_results.txt')
p('The following Bash source-list variable keeps the Yosys command readable without changing the module hierarchy:')
code('rtl="datapath.v DataMem.v InstMem.v RegFile.v"\nrtl="$rtl Nbit_decoder.v N_bit_register.v DFlipFlop.v"\nrtl="$rtl mux2x1.v ImmGen.v control_unit.v alu_unit.v"\nrtl="$rtl ALU.v BranchUnit.v"\n\nyosys -p "read_verilog $rtl; hierarchy -check -top datapath;\nproc; show -format dot \\\n-prefix ../Design/report_datapath_schematic datapath"\n\ndot -Tpdf ../Design/report_datapath_schematic.dot \\\n  -o ../Design/report_datapath_schematic.pdf\n# Optional viewer, if installed:\ngtkwave ../Testing/datapath.vcd')
sub('Regenerate the document figures')
p('Design/build_report.py assembles the existing team diagrams, waveform screenshot and verified project text using ReportLab, Pillow and pypdf. It does not redraw the datapath or waveform. Design/build_readmes.py regenerates the project README files.')
sub('Appendices / Original project diagrams')
p('Appendix A reproduces the existing Single-Cycle_Block_Diagram.png without redrawing it. Appendix B directly includes the existing datapath_schematic.pdf as a vector page. Both are taken from the team Design folder. Appendix C reproduces the original GTKWave screenshot from Testing/waveforms/waveform.png. Use PDF zoom to read the wide drawings. The schematic describes RTL hierarchy, not a routed gate-level implementation.')
cap('Included source artifacts: Design/Single-Cycle_Block_Diagram.png (also described in Design/diagram.md) and Design/datapath_schematic.pdf (with Design/datapath_schematic.svg as its companion). The original images and source files are unchanged. No substitute diagram is used.')

def footer(c,doc):
 w,hh=A4;c.setStrokeColor(colors.HexColor('#d6e2e9'));c.line(48,42,w-48,42);c.setFont('Helvetica',8);c.setFillColor(colors.HexColor('#48647a'));c.drawString(48,29,'femtoRV32 | Design & verification | 2 November 2026');c.drawRightString(w-48,29,str(doc.page))
body=tmp/'report_body.pdf'
SimpleDocTemplate(str(body),pagesize=A4,leftMargin=48,rightMargin=48,topMargin=48,bottomMargin=57,title='femtoRV32 Design and Implementation',author='Kareem Abdellatif; Mohamed Aboelfotouh; Moustafa Fayed').build(story,onFirstPage=footer,onLaterPages=footer)
# Embed the team-owned original PNG, keeping its aspect ratio and all original pixels.
original=root/'Design/Single-Cycle_Block_Diagram.png'
im=PILImage.open(original);w=2048;hh=w*im.height/im.width
original_page=tmp/'original_block_diagram.pdf'
c=canvas.Canvas(str(original_page),pagesize=(w,hh));c.drawImage(str(original),0,0,width=w,height=hh);c.showPage();c.save()
screenshot=root/'Testing/waveforms/waveform.png'
im=PILImage.open(screenshot);sw=1440;sh=sw*im.height/im.width
screenshot_page=tmp/'original_waveform.pdf'
c=canvas.Canvas(str(screenshot_page),pagesize=(sw,sh));c.drawImage(str(screenshot),0,0,width=sw,height=sh);c.showPage();c.save()
writer=PdfWriter();writer.append(str(body));writer.append(str(original_page));writer.append(str(root/'Design/datapath_schematic.pdf'));writer.append(str(screenshot_page));writer.add_metadata({'/Title':'femtoRV32 - Design, Implementation and Verification','/Author':'Kareem Abdellatif; Mohamed Aboelfotouh; Moustafa Fayed'})
with (out/'femtoRV32_Design_Report.pdf').open('wb') as f:writer.write(f)
print('Created',len(writer.pages),'pages;',checks,'passing checks;',cycles,'cycles')
