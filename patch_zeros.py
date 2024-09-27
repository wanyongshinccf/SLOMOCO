import sys
import numpy as np

# input variables

in_arr = sys.argv
if '-infile' not in in_arr  not in in_arr:
    print (__doc__)
    raise NameError('error: -infile options are not provided')
elif '-write' not in in_arr:
    print (__doc__)
    raise NameError('error: -write options are not provided')
else:
    ifile = in_arr[in_arr.index('-infile') + 1]
    ofile = in_arr[in_arr.index('-write') + 1]
   

slireg = np.loadtxt(ifile)

dims = np.shape(slireg)
tdim = dims[0]

dummy = np.linspace(0, tdim-1, tdim)

slireg_zp = slireg
temp = np.sum(abs(slireg),axis=0)
idx_zeros = np.where( temp == 0)
idx_zeros = idx_zeros[0]
for iz in range(len(idx_zeros)):
	zz = idx_zeros[iz]
	print(f'zero col at  = {zz}')
	slireg_zp[:,zz] = dummy

np.savetxt(ofile,slireg_zp)	
print('finished: patch_zeros.py')