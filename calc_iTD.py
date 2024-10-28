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

# brain the edge
lowz  = -40
highz =  52
lowx  = -64
highx =  64
lowy  = -84
highy =  84

# define variables
d2r  = 0.01745329
iTD  = np.zeros((int(tdim),1))
iTDz = np.zeros((int(tdim),1))
npix = 6

# calculate intra-volume total volume displacement
# Jiang Jiang A, Kennedy DN, Baker JR, et al. HBM. 1995;3(3):224-235
# Beall EB, Lowe MJ. Neuroimage. 2014;101:21-34.
for t in range (0, int(tdim)):
    itd = 0
    itdz = 0
    for iz in range (0, int(zmbdim)):
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
        for z in (lowz, highz): 
            for x in (lowx, highx):
                for y in (lowy, highy):
                    disp  = np.dot(xyzrotmat, np.array([x,y,z])) + np.array([dx,dy,dz]) - np.array([x,y,z])
                    dist  = cal.sqrt(disp[0]*disp[0] + disp[1]*disp[1] + disp[2]*disp[2])
                    distz = abs(disp[2])
                    itd   = itd  + dist
                    itdz  = itdz + distz
    itd  = itd / (npix*zmbdim)
    itdz = itdz / (npix*zmbdim) 
    iTD[t,0] = itd
    iTDz[t,0] = itdz


# write the result
np.savetxt('iTD_py.txt',iTD)	
np.savetxt('iTDz_py.txt',iTDz)