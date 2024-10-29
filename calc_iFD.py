import sys
import numpy as np
import math as cal
import os

# input variables

in_arr = sys.argv
if '-sli' not in in_arr :
    print (__doc__)
    raise NameError('error: -sli option is not provided')
elif '-tdim' not in in_arr :
    print (__doc__)
    raise NameError('error: -tdim option is not provided')
else:
    slireg1D = in_arr[in_arr.index('-sli') + 1]
    tdim     = in_arr[in_arr.index('-tdim') + 1]
   

# read 1D files [ tdim x (zdim * 6 mopa)]
slireg = np.loadtxt(slireg1D)
#slireg = np.loadtxt('slimot_py_fit.txt')

# define zmbdim, slireg = [ zmbdim*tdim x 6]
dims = np.shape(slireg)
zmbdim = dims[0]/int(tdim)
# zmbdim = zdim (slice number) / MB acceleration

# define variables; radius (mm)
R1 = 50
R2 = 80 
d2r = 0.01745329

# dx,dy,dz,rx,ry,rz
dx = -1 * slireg[:,4]
dy = -1 * slireg[:,5]
dz = -1 * slireg[:,3]
rx = d2r* slireg[:,1]
ry = d2r* slireg[:,2]
rz = d2r* slireg[:,0]

# calculate iFD (Power)
FDP_sli = np.abs(dx) + np.abs(dy) + np.abs(dz) + R1*(np.abs(rx)+np.abs(ry)+np.abs(rz));
temp = np.reshape(FDP_sli,(int(tdim),int(zmbdim)))
iFDP = np.mean(temp, axis=1)

# calculate ioFD (Power)
FDP_sli = np.abs(dz) + R1*(np.abs(rx)+np.abs(ry));
temp = np.reshape(FDP_sli,(int(tdim),int(zmbdim)))
ioFDP = np.mean(temp, axis=1)


# calculate iFD and izFD (Jenkinson)
iFDJ  = np.zeros((int(tdim),1))
izFDJ = np.zeros((int(tdim),1))
ioFDJ = np.zeros((int(tdim),1))
for t in range (0, int(tdim)):
    ifdj = 0
    izfdj = 0
    iofdj = 0
    for iz in range(0, int(zmbdim)): 
        # read volumetric params first (assume AFNI 3dvolreg)
        # 3dvolreg motion parametner
        # z-rot, x-rot, y-rot, z-shift, x-shift, y-shift 
        # 3dallineate motion parameter 
        # -xshift, -y-shift, -z-shift, z-rot, x-rot, y-rot
        dx = -1 * slireg[iz+t*int(zmbdim),4]
        dy = -1 * slireg[iz+t*int(zmbdim),5]
        dz = -1 * slireg[iz+t*int(zmbdim),3]
        rx = d2r* slireg[iz+t*int(zmbdim),1]
        ry = d2r* slireg[iz+t*int(zmbdim),2]
        rz = d2r* slireg[iz+t*int(zmbdim),0]
        # rotation matrix calclation
        xrotmat = np.array([[1, 0, 0], [0, cal.cos(rx), -1*cal.sin(rx)], [0, cal.sin(rx), cal.cos(rx)]])
        yrotmat = np.array([[cal.cos(ry), 0, cal.sin(ry)], [0, 1, 0], [-1*cal.sin(ry), 0, cal.cos(ry)]])
        zrotmat = np.array([[cal.cos(rz), -1*cal.sin(rz), 0], [cal.sin(rz), cal.cos(rz), 0], [0, 0, 1]])
        xyzrotmat = np.dot(zrotmat,np.dot(yrotmat, xrotmat))
        M = np.dot(np.transpose(xyzrotmat-np.eye(3)),xyzrotmat-np.eye(3))
        ifdj  = ifdj  + np.sqrt(R2 * R2 / 5.0 * (M[0,0] + M[1,1] + M[2,2]) + dx*dx + dy*dy + dz*dz)
        izfdj = izfdj + np.sqrt(R2 * R2 / 5.0 * M[2,2] + dz*dz)

        dx=0
        dy=0
        rz=0
        # rotation matrix calclation
        xrotmat = np.array([[1, 0, 0], [0, cal.cos(rx), -1*cal.sin(rx)], [0, cal.sin(rx), cal.cos(rx)]])
        yrotmat = np.array([[cal.cos(ry), 0, cal.sin(ry)], [0, 1, 0], [-1*cal.sin(ry), 0, cal.cos(ry)]])
        zrotmat = np.array([[cal.cos(rz), -1*cal.sin(rz), 0], [cal.sin(rz), cal.cos(rz), 0], [0, 0, 1]])
        xyzrotmat = np.dot(zrotmat,np.dot(yrotmat, xrotmat))
        M = np.dot(np.transpose(xyzrotmat-np.eye(3)),xyzrotmat-np.eye(3))
        iofdj  = iofdj  + np.sqrt(R2 * R2 / 5.0 * (M[0,0] + M[1,1] + M[2,2]) + dx*dx + dy*dy + dz*dz)




    iFDJ[t,0] =  ifdj/zmbdim
    izFDJ[t,0] = izfdj/zmbdim
    ioFDJ[t,0] = iofdj/zmbdim



# write the result
np.savetxt('iFDJ_py.txt',iFDJ)	
np.savetxt('iFDP_py.txt',iFDP)
np.savetxt('ioFDP_py.txt',ioFDP)	
np.savetxt('izFDJ_py.txt',izFDJ)
np.savetxt('ioFDJ_py.txt',ioFDJ)