import numpy as np, struct, glob, os, sys
def load(p):
    d=open(p,'rb').read(); n=struct.unpack('<I',d[80:84])[0]
    a=np.frombuffer(d[84:],dtype=np.dtype([('n','<3f4'),('v','<9f4'),('a','<u2')]),count=n)
    return a['v'].reshape(-1,3,3).astype(float)
for p in sorted(glob.glob("out/stl/*.stl")):
    t=load(p); e1=t[:,1]-t[:,0]; e2=t[:,2]-t[:,0]; n=np.cross(e1,e2); A=np.linalg.norm(n,axis=1)/2; n/= (2*A[:,None]+1e-12)
    zmin=t[...,2].min(1)
    bad=(n[:,2]< -0.72)&(zmin>0.25)
    # separar en "puentes" estrechos: no podemos medir anchura fácil; reportamos área y rango z
    ov=A[bad].sum()
    nm=os.path.basename(p)[:-4]
    if ov>0.5:
        zs=t[bad][...,2].mean(1)
        hist=np.histogram(zs,bins=8)
        print(f"{nm:20s} voladizo {ov:7.1f} mm²  z≈{zs.min():.1f}–{zs.max():.1f}  base {A[(n[:,2]<-0.99)&(zmin<=0.25)].sum():.0f} mm²")
    else:
        print(f"{nm:20s} sin voladizos   base {A[(n[:,2]<-0.99)&(zmin<=0.25)].sum():.0f} mm²")
