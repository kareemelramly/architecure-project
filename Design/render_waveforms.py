from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import math
root=Path(__file__).resolve().parents[1]; out=root/'Testing/waveforms';out.mkdir(exist_ok=True)
code={};width={};events={};time=0
for line in (root/'Testing/datapath.vcd').read_text().splitlines():
 if line.startswith('$var'):
  a=line.split();code[a[4]]=a[3];width[a[3]]=int(a[2]);events.setdefault(a[3],[])
 elif line.startswith('#'):time=int(line[1:])/1000
 elif line.startswith('b'):
  value,k=line[1:].split();events.setdefault(k,[]).append((time,value))
 elif line and line[0] in '01xz':events.setdefault(line[1:],[]).append((time,line[0]))
def integer(v):
 try:return int(v,2)
 except:return None
def at(name,t):
 value='x'
 for tm,v in events[code[name]]:
  if tm>t:break
  value=v
 return value
def pc(v):return next(t for t,b in events[code['pcValue']] if integer(b)==v)
font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',22);small=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',19);titlefont=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',30)
def wave(file,title,start,end,names):
 W=1880;H=155+80*len(names);L=235;R=W-30
 img=Image.new('RGB',(W,H),'#f7fafc');d=ImageDraw.Draw(img)
 d.text((25,18),title,font=titlefont,fill='#153149');d.text((25,60),'Actual Icarus VCD | buses: hexadecimal | time: ns',font=small,fill='#48647a')
 x=lambda t:L+(t-start)/(end-start)*(R-L)
 for k in range(9):
  t=start+(end-start)*k/8;xp=x(t);d.line((xp,115,xp,H-35),fill='#dbe5eb');d.text((xp-25,H-29),f'{t:g}',font=small,fill='#48647a')
 for n,name in enumerate(names):
  y=130+n*80;d.text((20,y+10),name,font=font,fill='#153149');k=code[name];bits=width[k]
  values=[(start,at(name,start))]+[(t,v) for t,v in events[k] if start<t<end]+[(end,None)]
  values=sorted(dict(values).items())
  clean=[]
  for pair in values:
   if not clean or pair[1]!=clean[-1][1] or pair[0]==end:clean.append(pair)
  values=clean
  for j in range(len(values)-1):
   a,v=values[j];b=values[j+1][0];xa,xb=x(a),x(b);col='#087e8b' if integer(v) is not None else '#b34d4d'
   if bits==1:
    yy=y+45-(25 if v=='1' else 0);d.line((xa,yy,xb,yy),fill=col,width=3)
    if j:d.line((xa,y+20,xa,y+45),fill=col,width=2)
   else:
    for yy in [y+15,y+49]:d.line((xa+4,yy,xb-4,yy),fill=col,width=2);d.line((xa,y+32,xa+4,yy),fill=col,width=2);d.line((xb-4,yy,xb,y+32),fill=col,width=2)
    val=integer(v);label=f'{val:0{math.ceil(bits/4)}X}' if val is not None else 'X';bb=d.textbbox((0,0),label,font=small);tw=bb[2]-bb[0]
    if xb-xa>tw+10:d.text(((xa+xb-tw)/2,y+20),label,font=small,fill='#153149')
 img.save(out/file)
wave('loads.png','Load extension: LB / LBU / LH / LHU',pc(108),pc(140),['clk','pcValue','memRead','aluOutput','dataMemoryOut','regWriteData'])
wave('stores.png','Partial writes: SB / SH and LW readback',pc(140),pc(172),['clk','pcValue','memWrite','aluOutput','readData2','dataMemoryOut'])
wave('synchronization.png','FENCE / FENCE.TSO / PAUSE: sequential execution',pc(172),pc(192),['clk','pcValue','instMemoryOut','memWrite','regWrite','halt'])
wave('halt.png','ECALL: PC freezes while the clock continues',pc(468)-40,pc(468)+100,['clk','pcValue','instMemoryOut','halt','pcLoad','regWrite'])
print('Four actual VCD waveform images created.')
