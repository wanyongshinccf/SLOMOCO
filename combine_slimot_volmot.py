import sys
import os
import numpy as np
import scipy.interpolate as sp
import matplotlib.pyplot as plt
from scipy.signal import savgol_filter

# input variables

in_arr = sys.argv
if '-vol' not in in_arr  not in in_arr:
    print (__doc__)
    raise NameError('error: -vol options are not provided')
elif '-sli' not in in_arr:
    print (__doc__)
    raise NameError('error: -sli options are not provided')
elif '-acq' not in in_arr:
    print (__doc__)
    raise NameError('error: -acq options are not provided')
else:
    volmotfn = in_arr[in_arr.index('-vol') + 1]
    slimotfn = in_arr[in_arr.index('-sli') + 1]
    acqodrfn = in_arr[in_arr.index('-acq') + 1]

if '-exc' not in in_arr  not in in_arr:
    excslifn = []     
else :
    excslifn = in_arr[in_arr.index('-exc') + 1]

# python script.py -i1 Input1 -i2 Input2
#volmot = np.loadtxt('epi_01_volreg.1D')
#slimot = np.loadtxt('epi_slireg.1D')
#acqodr = np.loadtxt('sliacqorder.1D')
#excsli = np.loadtxt('inplane/slice_excluded.txt')

volmot = np.loadtxt(volmotfn)
slimot = np.loadtxt(slimotfn)
acqodr = np.loadtxt(acqodrfn)

if os.path.isfile(excslifn) :
    print('++ Reading too-zero-ish slices')
    excsli = np.loadtxt(excslifn)
else :
    excsli = []

dims = np.shape(volmot)
tdim = int(dims[0])
dims = np.shape(slimot)
zdim = int(dims[1]/6)

# set zero in case of small voxel number
# print("tdim = ", tdim)
# print("zdim = ", zdim)
# print("acqorder:\n", acqorder)

# add slimot to volmot
volslimot_added = volmot

for rep in range (0,tdim , 1):
	# print(f'volume number = {rep}')
	volmot_rep = volmot[rep,:]
	for num in acqodr :
		#print(f'slice number is {num}')
		idxs = int( num*6 + 0 )
		idxe = int( num*6 + 6 )
		idx = np.where( excsli == num)
		#print("idx = ", np.size(idx))
		if (np.size(idx) == 0)  :
			slimot_rep = slimot[rep, idxs:idxe]
			volslimot_rep = volmot_rep + slimot_rep
			volslimot_added = np.concatenate((volslimot_added, volslimot_rep[None,:]),axis=0)
			

volslimot_added = np.delete(volslimot_added,slice(0,tdim),0)

# generate the extended volmot
volmot_ext = volmot

for rep in range (0,tdim , 1):
	#print(f'volume number = {rep}')
	for num in range(0, zdim, 1) :
		#print(f'slice number is {num}')
		volmot_sli = volmot[rep,:]
		volmot_ext = np.concatenate((volmot_ext, volmot_sli[None,:]),axis=0)

volmot_ext = np.delete(volmot_ext,slice(0,tdim),0)


# interpolate in excluded slices
if  ( np.size(excsli) > 0 ) :
    exclude_slices_tp = np.array(0)
    for rep in range(0,tdim,1):
	    # print(rep)
        for exs in range(len(excsli)):
            #print("exclude_slices: ", excsli[exs])
            x = np.where(acqodr == excsli[exs])
            xx = x[0]
            slice_tp = xx[0]
            exclude_slices_tp = np.append(exclude_slices_tp, slice_tp+zdim*rep)	
            
    exclude_slices_tp = np.delete(exclude_slices_tp,0,axis=0)
    
    x = np.linspace(0, zdim*tdim-1, zdim*tdim)
    x_obs = np.setxor1d(x,exclude_slices_tp)
    volslimot = np.zeros((zdim*tdim,6))
    for mopa in range(0,6,1):
	    # print("mopa = ", mopa)
        y_obs = volslimot_added[:,mopa]
        y = sp.pchip_interpolate(x_obs, y_obs, x)
        volslimot[:,mopa] = y
else :
    volslimot = volslimot_added    


#plt.plot(x_obs, y_obs, "o", label="observation")
#plt.plot(x, y, label="pchip interpolation")
#plt.legend()
#plt.show()


# filtering
volslimot_fit = np.zeros((zdim*tdim,6))
glen = int(zdim/2)*2+1
for mopa in range(0,6,1):
	y = volslimot[:,mopa]
	yfit = savgol_filter(y, glen, 2)
	volslimot_fit[:,mopa] = yfit
	

#plt.plot(x, y, "o", label="observation")
#plt.plot(x, yfit, label="pchip interpolation")
#plt.legend()
#plt.show()

# generate and save motion parameter in time doain
slimot = volslimot - volmot_ext
slimot_fit = volslimot_fit - volmot_ext
np.savetxt('volslimot_py.txt',volslimot)	
np.savetxt('volslimot_py_fit.txt',volslimot_fit)
np.savetxt('slimot_py.txt',slimot)	
np.savetxt('slimot_py_fit.txt',slimot_fit)	

print('finished')

