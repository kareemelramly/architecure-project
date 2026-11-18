"""Builds Design/Pipelined_5Stage_Block_Diagram.svg (then rsvg-convert -> png/pdf)."""
S = []
a = S.append
a('''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 880" font-family="Inter, Helvetica, Arial, sans-serif" font-size="13">
<defs>
<marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#1f2937"/></marker>
<marker id="ab" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#1d4ed8"/></marker>
<marker id="ao" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#b45309"/></marker>
<marker id="ag" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#059669"/></marker>
<style>
.blk{fill:#fff;stroke:#1e3a8a;stroke-width:1.6}.reg{fill:#dbeafe;stroke:#1e3a8a;stroke-width:1.8}
.mux{fill:#f1f5f9;stroke:#1e3a8a;stroke-width:1.4}.mem{fill:#fff7ed;stroke:#ea580c;stroke-width:2}
.b4{fill:#ecfdf5;stroke:#059669;stroke-width:1.6}.b3{fill:#fef3c7;stroke:#b45309;stroke-width:1.6}
.w{stroke:#1f2937;stroke-width:1.4;fill:none}.f{stroke:#1d4ed8;stroke-width:1.6;fill:none;stroke-dasharray:6 3}
.o{stroke:#b45309;stroke-width:1.4;fill:none;stroke-dasharray:4 3}.g{stroke:#059669;stroke-width:1.5;fill:none;stroke-dasharray:4 3}
.s{fill:#64748b;font-size:11px}.h{fill:#1e3a8a;font-weight:700;font-size:16px}.hb{font-weight:600}
</style></defs>
<rect width="1600" height="880" fill="#fff"/>
<text x="20" y="30" class="h" font-size="20">femtoRV32 MS3: 5-stage pipeline (IF, ID, EX, MEM, WB), one single-ported memory, one slot every 2 cycles (C0, C1)</text>
''')
bands = [(15,290,'IF (C0)'),(335,370,'ID (C1)'),(735,310,'EX (C0)'),(1075,210,'MEM (C1)'),(1315,270,'WB (C0)')]
for i,(x,w,t) in enumerate(bands):
    a(f'<rect x="{x}" y="60" width="{w}" height="700" fill="{"#f8fafc" if i%2==0 else "#fff"}" stroke="#cbd5e1"/>')
    a(f'<text x="{x+10}" y="84" class="h">{t}</text>')
a('<g transform="translate(0,40)">')
def box(x,y,w,h,cls,t1,t2=None,t3=None):
    a(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" class="{cls}"/>')
    ty=y+h/2+(4 if not t2 else -4 if not t3 else -9)
    a(f'<text x="{x+w/2}" y="{ty}" text-anchor="middle" class="hb">{t1}</text>')
    if t2: a(f'<text x="{x+w/2}" y="{ty+15}" text-anchor="middle" class="s">{t2}</text>')
    if t3: a(f'<text x="{x+w/2}" y="{ty+28}" text-anchor="middle" class="s">{t3}</text>')
def mux(x,y,w,h,label):
    a(f'<polygon points="{x},{y} {x+w},{y+10} {x+w},{y+h-10} {x},{y+h}" class="mux"/>')
    a(f'<text x="{x+w/2}" y="{y-5}" text-anchor="middle" class="s">{label}</text>')
def path(d,c='w',m='a'): a(f'<path d="{d}" class="{c}" marker-end="url(#{m})"/>')
def txt(x,y,t,anchor='start'): a(f'<text x="{x}" y="{y}" class="s" text-anchor="{anchor}">{t}</text>')
def bar(x,t):
    a(f'<rect x="{x}" y="55" width="20" height="490" class="reg"/>')
    a(f'<text transform="translate({x+14},300) rotate(-90)" text-anchor="middle" class="hb" font-size="12">{t}</text>')
bar(310,'IF_ID (load end of C1, flush on redirect or halt)')
bar(710,'ID_EX (load end of C1, flush on stall)')
bar(1050,'EX_MEM (load end of C0)')
bar(1290,'MEM_WB (load end of C1)')
# IF
box(35,75,70,56,'reg','PC','load end C1')
box(130,65,50,26,'blk','+4')
box(125,160,160,60,'b3','Branch predictor','16-entry BTB + 2-bit BHT','Bonus 3 (BP_ENABLE)')
mux(205,55,25,70,'pred'); mux(250,55,25,70,'next PC')
path('M105,95 H118 V74 H130'); path('M180,78 H192 V70 H205'.replace('V70','V70'))
path('M118,95 V175 H125')
path('M200,160 V110 H205','o','ao')
path('M230,90 H250')
path('M275,90 H292 V30 H22 V100 H35')
# memory strip
a('<rect x="40" y="560" width="1260" height="52" class="mem"/>')
a('<text x="670" y="582" text-anchor="middle" class="hb">Unified memory: one port, byte addressable (Verilog UnifiedMem)</text>')
a('<text x="670" y="600" text-anchor="middle" class="s">address mux: C0 = PC (fetch), C1 = EX_MEM result (load / store). The two never collide, so there is no structural hazard, but every slot takes 2 cycles.</text>')
path('M70,131 V560'); txt(76,520,'C0: PC')
path('M320,560 V545'); txt(326,552,'instruction, captured in instLatch at end of C0')
path('M1060,545 V560'); a('<text x="1046" y="556" class="s" text-anchor="end">C1: address, store data</text>')
path('M1300,560 V545'); a('<text x="1286" y="556" class="s" text-anchor="end">load data (end of C1)</text>')
# ID
box(360,60,110,40,'blk','Control unit','EBREAK = halt')
box(360,150,130,70,'blk','RegFile','read in C1','write end of C0 + debug port')
box(520,120,100,36,'blk','ImmGen')
path('M330,80 H360'); path('M330,185 H360'); path('M330,138 H520')
path('M470,80 H710'); path('M620,138 H710'); path('M490,175 H710'); path('M490,205 H710')
txt(560,72,'control signals')
a('<rect x="350" y="245" width="345" height="190" fill="#ecfdf5" stroke="#059669" stroke-width="1.4" rx="6"/>')
a('<text x="360" y="262" class="hb" fill="#059669" style="fill:#059669">Bonus 4: branches and jumps resolve in ID</text>')
box(360,300,150,52,'b4','HazardUnit','load-use and branch stalls')
box(520,275,170,44,'b4','ID forwarding','EX_MEM result, regWriteData')
box(520,345,170,60,'b4','Branch comparator','+ JAL / JALR target')
path('M490,190 H505 V297 H520'); path('M595,319 V345')
path('M690,375 H702 V18 H262 V57','g','ag'); txt(420,12,'redirect: PC = resolved target, IF_ID flushed (1 slot lost if mispredicted)')
path('M430,352 V520 H710','g','ag'); txt(440,512,'stall: hold PC and IF_ID, bubble into ID_EX')
path('M595,405 V470 H150 V205 H125','o','ao'); txt(300,462,'BP update (resolved branch, in ID)')
# EX
mux(760,110,24,60,'fwdA'); mux(760,220,24,60,'fwdB')
mux(820,110,24,60,'PC / rs1'); mux(820,220,24,60,'imm / rs2')
box(890,90,100,180,'blk','ALU','RV32I + M')
box(890,300,100,34,'blk','ALU control')
mux(1000,150,24,70,'result')
path('M730,130 H760'); path('M730,240 H760')
path('M784,140 H820'); path('M784,250 H820'); path('M844,140 H890'); path('M844,250 H890')
path('M940,300 V270'); path('M990,185 H1000'); path('M1024,185 H1050')
path('M800,250 V360 H1050'); txt(900,352,'store data (forwarded rs2)')
a('<path d="M745,480 V130 M745,130 H760 M745,240 H760" class="f"/>')
a('<path d="M752,130 H760 M752,240 H760" class="f" marker-end="url(#ab)"/>')
path('M1050,400 H745','f','ab'); path('M1440,250 V480 H745','f','ab')
txt(760,472,'EX forwarding: EX_MEM result or regWriteData (MEM_WB)')
# MEM
box(1100,150,160,70,'blk','MEM stage (C1)','load / store use the','memory port below')
path('M1070,185 H1100'); path('M1260,185 H1290')
# WB
mux(1380,130,26,80,'WB mux'); path('M1310,150 H1380'); path('M1310,190 H1380')
txt(1318,144,'mem data'); txt(1318,204,'ALU result')
path('M1406,170 H1440 V250','w','a'); txt(1412,160,'regWriteData')
a('<path d="M1440,170 H1500 V655 H20 V235 H380 V220" class="w" marker-end="url(#a)"/>')
txt(900,648,'write rd at end of C0, before the ID read of the next C1: distance 3 or more needs no forwarding')
a('</g>')
# legend
a('''<g transform="translate(20,810)"><rect width="1560" height="56" fill="#fff" stroke="#cbd5e1"/>
<rect x="14" y="10" width="22" height="14" class="reg"/><text x="44" y="22">pipeline register / latch</text>
<rect x="230" y="10" width="22" height="14" class="mem"/><text x="260" y="22">shared memory port</text>
<path d="M440,17 H480" class="f"/><text x="490" y="22">EX forwarding</text>
<path d="M620,17 H660" class="g"/><text x="670" y="22">Bonus 4 (ID resolution, stall)</text>
<path d="M880,17 H920" class="o"/><text x="930" y="22">Bonus 3 (predictor update)</text>
<text x="14" y="44" class="s">One slot = 2 clock cycles. PC, IF_ID, ID_EX, MEM_WB load at the end of C1; instLatch, EX_MEM and the RegFile write happen at the end of C0. Latency of one instruction = 5 slots = 10 cycles.</text></g></svg>''')
open('Pipelined_5Stage_Block_Diagram.svg','w').write('\n'.join(S))
