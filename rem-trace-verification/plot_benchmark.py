import sys, matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
rows=[[c.strip() for c in l.strip().strip('|').split('|')] for l in open(sys.argv[1]) if l.strip()][1:]
R=[(r[0].split(' @ ')[0], int(r[0].split('@')[1].split()[0]), float(r[3]), float(r[4]), float(r[6]), float(r[7])) for r in rows]
w=[r for r in R if r[0]=='registerBatch']
plt.rcParams.update({'font.family':'DejaVu Serif','font.size':9})
fig,ax=plt.subplots(1,2,figsize=(6.6,2.7),dpi=300)
x=[r[1] for r in w]
ax[0].plot(x,x,'--',color='0.55',lw=1,label='Ideal (throughput = target rate)')
ax[0].plot(x,[r[5] for r in w],'-o',color='k',lw=1.4,ms=5,label='registerBatch()')
for r in w: ax[0].annotate(f'{r[5]:.1f}',(r[1],r[5]),textcoords='offset points',xytext=(6,-9),fontsize=8)
ax[0].set_ylim(0,108)
ax[0].set_xlabel('Target send rate (TPS)'); ax[0].set_ylabel('Throughput (TPS)'); ax[0].set_title('(a) Write throughput',fontsize=9)
ax[0].legend(frameon=False,fontsize=7.5,loc='upper left')
ax[1].plot(x,[r[4] for r in w],'-o',color='k',lw=1.4,ms=5,label='Average latency')
ax[1].plot(x,[r[3] for r in w],':s',color='0.35',lw=1.2,ms=4.5,label='Maximum latency')
ax[1].annotate(f'avg {w[-1][4]:.2f} s',(w[-1][1],w[-1][4]),textcoords='offset points',xytext=(-6,4),fontsize=8,ha='right')
ax[1].annotate(f'avg {w[2][4]:.2f} s',(w[2][1],w[2][4]),textcoords='offset points',xytext=(0,-13),fontsize=8,ha='center')
ax[1].set_ylim(-0.6,5.8)
ax[1].set_xlabel('Target send rate (TPS)'); ax[1].set_ylabel('Latency (s)'); ax[1].set_title('(b) Write latency',fontsize=9)
ax[1].legend(frameon=False,fontsize=7.5,loc='upper left')
for a in ax:
    a.set_xticks(x); a.grid(True,color='0.88',lw=0.5); a.set_axisbelow(True)
    for s in ('top','right'): a.spines[s].set_visible(False)
fig.tight_layout(); fig.savefig(sys.argv[2])
