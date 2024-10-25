import numpy as np
import matplotlib.pyplot as plt

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

plt.plot(xpoints, ypoints)
plt.show()



# reshape; FDJ_sli is [tdim*zdim,1] vectort
temp = np.reshape(iFDJ_sli,(int(tdim),int(zdim)))
ioFDJ = np.mean(temp, axis=1)

# write the result
np.savetxt('iFDJ_py.txt',iFDJ)	
np.savetxt('iFDP_py.txt',iFDP)
np.savetxt('ioFDJ_py.txt',ioFDJ)	
np.savetxt('ioFDP_py.txt',ioFDP)