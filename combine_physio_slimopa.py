import sys
import numpy as np


# input variables

in_arr = sys.argv
if '-physio' not in in_arr  not in in_arr:
    print (__doc__)
    raise NameError('error: -physio options are not provided')
elif '-slireg' not in in_arr:
    print (__doc__)
    raise NameError('error: -slireg options are not provided')
elif '-write' not in in_arr:
    print (__doc__)
    raise NameError('error: -write options are not provided')
else:
    slimotfn = in_arr[in_arr.index('-slireg') + 1]
    physiofn = in_arr[in_arr.index('-physio') + 1]
    ofile    = in_arr[in_arr.index('-write') + 1]

#slimot = np.loadtxt('slireg_zp.1D')
#physio = np.loadtxt('physioreg.1D')
# exclude_slices = np.loadtxt('inplane/slice_excluded.txt')

slimot = np.loadtxt(slimotfn)
physio = np.loadtxt(physiofn)

dims = np.shape(slimot)
tdim_s = int(dims[0])
zdim = int(dims[1]/6)

dims = np.shape(physio)
tdim_p = int(dims[0])
regnum_physio = int(dims[1]/zdim)

if   tdim_p != tdim_s  :
	print('error: physio and slimopa do not have the same time points')
	
print(f'Number of physio regressors is {regnum_physio}')

# add physio to slimot
slireg_all = np.zeros((tdim_p,zdim*(6+regnum_physio)))

for z in range(0, zdim, 1) :
	#print(f'slice number is {num}')
	idxs1 = int( z*6 + 0 )
	idxe1 = int( z*6 + 6 )
	slimot_sli = slimot[: , idxs1:idxe1]
		
	idxs2 = int( z*regnum_physio + 0 )
	idxe2 = int( z*regnum_physio + regnum_physio )
	physio_sli = physio[:, idxs2:idxe2]
		
	idxs = idxs1 + idxs2
	idxe = idxe1 + idxe2
	reg_sli = np.concatenate((slimot_sli, physio_sli),axis=1)
	slireg_all[:,idxs:idxe] = reg_sli
	

np.savetxt(ofile,slireg_all)	

print('finished: combine_physio_slimopa.py')

