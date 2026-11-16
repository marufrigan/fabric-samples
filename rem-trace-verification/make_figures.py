import json, sys, re
from PIL import Image, ImageDraw, ImageFont
EV=sys.argv[1]; OUT=sys.argv[2]
MONO='/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'; MONOB='/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'
W=1560; FS=24; PAD=30; LH=34
f=ImageFont.truetype(MONO,FS); fb=ImageFont.truetype(MONOB,FS)
COLS=int((W-2*PAD)/f.getlength('M'))
OPTS="-o 127.0.0.1:6050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA -C mychannel -n remtrace --peerAddresses 127.0.0.1:7051 --tlsRootCertFiles $ORG1_CA --peerAddresses 127.0.0.1:7055 --tlsRootCertFiles $ORG2_CA --waitForEvent"
def parse(name):
    blocks=[]; cur=None
    for ln in open(f'{EV}/{name}').read().split('\n'):
        if ln.startswith('# identity:'): cur={'id':ln[12:].strip(),'cmd':None,'out':[]}; blocks.append(cur)
        elif ln.startswith('$ ') and cur is not None and cur['cmd'] is None: cur['cmd']=ln[2:]
        elif cur is not None and ln.strip(): cur['out'].append(ln.rstrip())
    return blocks
def wrap(s,indent='    '):
    out=[]
    for ln in s.split('\n'):
        lead=len(ln)-len(ln.lstrip())
        while len(ln)>COLS:
            cut=max(ln.rfind(' ',0,COLS), ln.rfind(',',0,COLS-1)+1, ln.rfind('/',0,COLS-1)+1)
            if cut<=lead+len(indent)+8: cut=COLS
            out.append(ln[:cut].rstrip()); ln=' '*lead+indent+ln[cut:].lstrip()
        out.append(ln)
    return out
def render(name,items):
    lines=[]
    for k,t in items:
        for ln in wrap(('$ '+t) if k=='cmd' else t): lines.append((k,ln))
        if k=='out': lines.append(('gap',''))
    if lines[-1][0]=='gap': lines=lines[:-1]
    H=2*PAD+LH*len(lines)
    im=Image.new('RGB',(W,H),'white'); d=ImageDraw.Draw(im); y=PAD
    for k,ln in lines:
        if k=='cmd': d.rectangle([8,y-4,W-8,y+LH-4],fill=(228,228,228))
        y+=LH
    y=PAD
    for k,ln in lines:
        d.text((PAD,y),ln,font=fb if k=='cmd' else f,fill=(0,0,0) if k!='note' else (60,60,60)); y+=LH
    d.rectangle([0,0,W-1,H-1],outline=(0,0,0),width=4)
    im.save(f'{OUT}/{name}.png',dpi=(300,300)); print(name,im.size)
def full(c): return c.replace(' --tls',' \\\n    --tls').replace(' --peerAddresses',' \\\n    --peerAddresses').replace(' --waitForEvent',' \\\n    --waitForEvent')
def short(c): return c.replace(OPTS,'[...]')
def pj(s): return json.dumps(json.loads(s),indent=2)
def ident(b): return ('note','# identity: '+b['id'])
def items(b,cmd=short,out=None):
    o='\n'.join(b['out']) if out is None else out
    return [ident(b),('cmd',cmd(b['cmd'])),('out',o)]

B=parse('01_lifecycle.txt'); render('fig_deploy',[x for b in B for x in items(b)[1:]])
B=parse('03_register_lineage.txt')
render('fig_register',items(B[0],cmd=full)+items(B[4]))
B=parse('04_query_batch.txt'); render('fig_querybatch',items(B[0],out=pj(B[0]['out'][0])))
B=parse('05_trace_to_origin.txt'); t=json.loads(B[0]['out'][0])
keys=['batchID','parentBatchID','owner','materialType','country','propertiesHash','complianceFlag','timestamp','creatorMSP']
g=lambda o,ks: ', '.join(f'"{k}":{json.dumps(o[k])}' for k in ks)
rows=[' {'+g(o,keys[:3])+',\n  '+g(o,keys[3:5])+',\n  '+g(o,keys[5:6])+',\n  '+g(o,keys[6:])+'}'+(',' if i<len(t)-1 else '') for i,o in enumerate(t)]
render('fig_trace',items(B[0],out='[\n'+'\n'.join(rows)+'\n]'))
B=parse('06_compliance.txt'); render('fig_compliance',items(B[0],out=pj(B[0]['out'][0]))+items(B[1],out=pj(B[1]['out'][0]))[1:])
B=parse('08_negative.txt'); it=[]
for b in B: it+=items(b)
render('fig_negative',it)
B=parse('10_restricted_compliance.txt'); render('fig_restricted',items(B[1],out=pj(B[1]['out'][0]))+items(B[2],out=pj(B[2]['out'][0]))[1:])
B=parse('11_certificate.txt'); N=parse('12_certificate_negative.txt')
sel=lambda s,ks: json.dumps({k:json.loads(s)[k] for k in ks})
vk=['batchID','certificateID','isValid','checks','message']
render('fig_certificate',items(B[0],out='\n'.join(x for x in B[0]['out'] if 'committed' in x)+'\nChaincode invoke successful. result: status:200')
   +items(B[1],out=sel(B[1]['out'][0],vk+['certificateHash']))+items(N[0])+items(N[3],out=sel(N[3]['out'][0],vk))+items(N[5],out=sel(N[5]['out'][0],vk))[1:])
B=parse('13_transfer.txt'); Hh=parse('14_history_after_transfer.txt'); hist=json.loads(Hh[0]['out'][0])
it=[]
for b_ in B: it+=[ident(b_),('cmd',short(b_['cmd'])),('out','\n'.join(b_['out']))]
render('fig_transfer',it)
def pv(v):
    o={k:v[k] for k in ('batchID','owner','custodianMSP','previousOwner','transferTimestamp') if k in v}
    if 'pendingTransfer' in v: o['pendingTransfer']={k:v['pendingTransfer'][k] for k in ('newOwner','newOwnerMSP','offeredByMSP')}
    return o
proj=[{'txId':x['txId'],'timestamp':x['timestamp'],'isDelete':x['isDelete'],'value':pv(x['value'])} for x in hist]
render('fig_history',items(Hh[0],out=json.dumps(proj,indent=1)))
G=parse('02_governance.txt'); it=[]
it+=items(G[0],out='\n'.join(x for x in G[0]['out'] if 'committed' in x)+'\nChaincode invoke successful. result: status:200')
it+=items(G[1],out=json.dumps({k:json.loads(G[1]['out'][0])[k] for k in ('regulatorMSP','setByMSP','updatedAt')}))
for g in G[2:]: it+=items(g)
render('fig_governance',it)
render('fig_integrity',[('out',open(f'{EV}/15_evidence_integrity.txt').read().strip())])
