import sys
import numpy as np
import math as cal
import os

# input variables

in_arr = sys.argv
if '-vol' not in in_arr :
    print (__doc__)
    raise NameError('error: -vol option is not provided')
else:
    volreg1D = in_arr[in_arr.index('-vol') + 1]
   

# read 1D files [ tdim x (zdim * 6 mopa)]
volreg = np.loadtxt(volreg1D)
#volreg = np.loadtxt('epi_01_volreg.1D')

# define tdim, vardim (=zdim x 6)
dims = np.shape(volreg)
tdim = dims[0]
raddeg = 0.01745329

# dx,dy,dz,rx,ry,rz
dx = volreg[:,4]
dy = volreg[:,5]
dz = volreg[:,3]
rx = volreg[:,1]
ry = volreg[:,2]
rz = volreg[:,0]

# difference
ddx = np.diff(dx)
ddy = np.diff(dy)
ddz = np.diff(dz)
drx = np.diff(rx)
dry = np.diff(ry)
drz = np.diff(rz)

# radius (mm)
R1 = 50 
R2 = 80 

# calculate FD (Power)
FDP = np.abs(ddx) + np.abs(ddy) + np.abs(ddz) + R1*raddeg*(np.abs(drx)+np.abs(dry)+np.abs(drz));
oFDP = np.abs(ddz) + R1*raddeg*(np.abs(drx)+np.abs(dry));

# calculate FD (Jankinson)
d2r = 0.01745329
FDJ = np.zeros((tdim-1,1))
oFDJ = np.zeros((tdim-1,1))
for iz in range(0, tdim-1):
     iddx = ddx[iz]
     iddy = ddy[iz]
     iddz = ddz[iz]
     idrx = drx[iz]
     idry = dry[iz]
     idrz = drz[iz]
     
     # rotation matrix calclation
     xrotmat = np.array([[1, 0, 0], [0, cal.cos(idrx*d2r), -1*cal.sin(idrx*d2r)],	[0, cal.sin(idrx*d2r), cal.cos(idrx*d2r)]])
     yrotmat = np.array([[cal.cos(idry*d2r), 0, cal.sin(idry*d2r)], [0, 1, 0], [-1*cal.sin(idry*d2r), 0, cal.cos(idry*d2r)]])
     zrotmat = np.array([[cal.cos(idrz*d2r), -1*cal.sin(idrz*d2r), 0], [cal.sin(idrz*d2r), cal.cos(idrz*d2r), 0], [0, 0, 1]])
     xyzrotmat = np.dot(zrotmat,np.dot(yrotmat, xrotmat))
     M = np.trace(np.dot(np.transpose(xyzrotmat-np.eye(3)),xyzrotmat-np.eye(3)))
     sumdxyz = iddx*iddx + iddy*iddy + iddz*iddz
     
     # combine all
     FDJ[iz,0] = np.sqrt(R2 * R2 / 5.0 * M + sumdxyz )
     
     iddx = 0
     iddy = 0
     idrz = 0
     
     # rotation matrix calclation
     xrotmat = np.array([[1, 0, 0], [0, cal.cos(idrx*d2r), -1*cal.sin(idrx*d2r)],	[0, cal.sin(idrx*d2r), cal.cos(idrx*d2r)]])
     yrotmat = np.array([[cal.cos(idry*d2r), 0, cal.sin(idry*d2r)], [0, 1, 0], [-1*cal.sin(idry*d2r), 0, cal.cos(idry*d2r)]])
     zrotmat = np.array([[cal.cos(idrz*d2r), -1*cal.sin(idrz*d2r), 0], [cal.sin(idrz*d2r), cal.cos(idrz*d2r), 0], [0, 0, 1]])
     xyzrotmat = np.dot(zrotmat,np.dot(yrotmat, xrotmat))
     M = np.trace(np.dot(np.transpose(xyzrotmat-np.eye(3)),xyzrotmat-np.eye(3)))
     sumdxyz = iddx*iddx + iddy*iddy + iddz*iddz
     
     # combine all
     oFDJ[iz,0] = np.sqrt(R2 * R2 / 5.0 * M + sumdxyz )



# write the result
np.savetxt('FDJ_py.txt',FDJ)	
np.savetxt('FDP_py.txt',FDP)
np.savetxt('oFDJ_py.txt',oFDJ)	
np.savetxt('oFDP_py.txt',oFDP)