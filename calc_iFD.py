import sys
import numpy as np
import math as cal
import os

# input variables

in_arr = sys.argv
if '-sli' not in in_arr :
    print (__doc__)
    raise NameError('error: -sli option is not provided')
elif '-zdim' not in in_arr :
    print (__doc__)
    raise NameError('error: -zdim option is not provided')
else:
    slireg1D = in_arr[in_arr.index('-sli') + 1]
    zdim     = in_arr[in_arr.index('-zdim') + 1]
   

# read 1D files [ tdim x (zdim * 6 mopa)]
slireg = np.loadtxt(slireg1D)
#slireg = np.loadtxt('slimot_py_fit.txt')

# define tdim, vardim (=zdim x 6)
dims = np.shape(slireg)
tdim = dims[0]/int(zdim)

# dx,dy,dz,rx,ry,rz
dx = slireg[:,4]
dy = slireg[:,5]
dz = slireg[:,3]
rx = slireg[:,1]
ry = slireg[:,2]
rz = slireg[:,0]

# radius (mm)
R1 = 50 
d2r = 0.01745329

# calculate iFD (Power)
FDP_sli = np.abs(dx) + np.abs(dy) + np.abs(dz) + R1*d2r*(np.abs(rx)+np.abs(ry)+np.abs(rz));
temp = np.reshape(FDP_sli,(int(tdim),int(zdim)))
iFDP = np.mean(temp, axis=1)

# calculate ioFD (Power)
FDP_sli = np.abs(dz) + R1*d2r*(np.abs(rx)+np.abs(ry));
temp = np.reshape(FDP_sli,(int(tdim),int(zdim)))
ioFDP = np.mean(temp, axis=1)

# calculate iFD (Jankinson)
R2 = 80
d2r = 0.01745329
iFDJ_sli = np.zeros((int(zdim)*int(tdim),1))
for iz in range(0, int(zdim)*int(tdim)-1): 
     iddx = dx[iz]
     iddy = dy[iz]
     iddz = dz[iz]
     idrx = rx[iz]
     idry = ry[iz]
     idrz = rz[iz]
     
     # rotation matrix calclation
     xrotmat = np.array([[1, 0, 0], [0, cal.cos(idrx*d2r), -1*cal.sin(idrx*d2r)],	[0, cal.sin(idrx*d2r), cal.cos(idrx*d2r)]])
     yrotmat = np.array([[cal.cos(idry*d2r), 0, cal.sin(idry*d2r)], [0, 1, 0], [-1*cal.sin(idry*d2r), 0, cal.cos(idry*d2r)]])
     zrotmat = np.array([[cal.cos(idrz*d2r), -1*cal.sin(idrz*d2r), 0], [cal.sin(idrz*d2r), cal.cos(idrz*d2r), 0], [0, 0, 1]])
     xyzrotmat = np.dot(zrotmat,np.dot(yrotmat, xrotmat))
     M = np.trace(np.dot(np.transpose(xyzrotmat-np.eye(3)),xyzrotmat-np.eye(3)))
     sumdxyz = iddx*iddx + iddy*iddy + iddz*iddz
     iFDJ_sli[iz,0] = np.sqrt(R2 * R2 / 5.0 * M + sumdxyz )


# reshape; FDJ_sli is [tdim*zdim,1] vectort
temp = np.reshape(iFDJ_sli,(int(tdim),int(zdim)))
iFDJ = np.mean(temp, axis=1)

# ioFD
iFDJ_sli = np.zeros((int(zdim)*int(tdim),1))
for iz in range(0, int(zdim)*int(tdim)-1): 
     iddx = 0
     iddy = 0
     iddz = dz[iz]
     idrx = rx[iz]
     idry = ry[iz]
     idrz = 0
     
     # rotation matrix calclation
     xrotmat = np.array([[1, 0, 0], [0, cal.cos(idrx*d2r), -1*cal.sin(idrx*d2r)],	[0, cal.sin(idrx*d2r), cal.cos(idrx*d2r)]])
     yrotmat = np.array([[cal.cos(idry*d2r), 0, cal.sin(idry*d2r)], [0, 1, 0], [-1*cal.sin(idry*d2r), 0, cal.cos(idry*d2r)]])
     zrotmat = np.array([[cal.cos(idrz*d2r), -1*cal.sin(idrz*d2r), 0], [cal.sin(idrz*d2r), cal.cos(idrz*d2r), 0], [0, 0, 1]])
     xyzrotmat = np.dot(zrotmat,np.dot(yrotmat, xrotmat))
     M = np.trace(np.dot(np.transpose(xyzrotmat-np.eye(3)),xyzrotmat-np.eye(3)))
     sumdxyz = iddx*iddx + iddy*iddy + iddz*iddz
     iFDJ_sli[iz,0] = np.sqrt(R2 * R2 / 5.0 * M + sumdxyz )


# reshape; FDJ_sli is [tdim*zdim,1] vectort
temp = np.reshape(iFDJ_sli,(int(tdim),int(zdim)))
ioFDJ = np.mean(temp, axis=1)

izFDJ_sli = np.zeros((int(zdim)*int(tdim),1))
for iz in range(0, int(zdim)*int(tdim)-1): 
     iddx = dx[iz]
     iddy = dy[iz]
     iddz = dz[iz]
     idrx = rx[iz]
     idry = ry[iz]
     idrz = rz[iz]
     
     # rotation matrix calclation
     xrotmat = np.array([[1, 0, 0], [0, cal.cos(idrx*d2r), -1*cal.sin(idrx*d2r)],	[0, cal.sin(idrx*d2r), cal.cos(idrx*d2r)]])
     yrotmat = np.array([[cal.cos(idry*d2r), 0, cal.sin(idry*d2r)], [0, 1, 0], [-1*cal.sin(idry*d2r), 0, cal.cos(idry*d2r)]])
     zrotmat = np.array([[cal.cos(idrz*d2r), -1*cal.sin(idrz*d2r), 0], [cal.sin(idrz*d2r), cal.cos(idrz*d2r), 0], [0, 0, 1]])
     xyzrotmat = np.dot(zrotmat,np.dot(yrotmat, xrotmat))

     M = np.dot(np.transpose(xyzrotmat-np.eye(3)),xyzrotmat-np.eye(3))
     izFDJ_sli[iz,0] = np.sqrt(R2 * R2 / 5.0 * M[2,2] + iddz*iddz )

# reshape; FDJ_sli is [tdim*zdim,1] vectort
temp = np.reshape(izFDJ_sli,(int(tdim),int(zdim)))
izFDJ = np.mean(temp, axis=1)

# write the result
np.savetxt('iFDJ_py.txt',iFDJ)	
np.savetxt('iFDP_py.txt',iFDP)
np.savetxt('ioFDJ_py.txt',ioFDJ)	
np.savetxt('ioFDP_py.txt',ioFDP)
np.savetxt('izFDJ_py.txt',izFDJ)