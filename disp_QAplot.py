import sys
import numpy as np
import matplotlib.pyplot as plt

# input variables

in_arr = sys.argv
if '-ssdvol' not in in_arr :
    print (__doc__)
    raise NameError('error: -ssdvol option is not provided')
elif '-ssdsli' not in in_arr :
    print (__doc__)
    raise NameError('error: -ssdsli option is not provided')
elif '-volsli' not in in_arr :
    print (__doc__)
    raise NameError('error: -volsli option is not provided')
elif '-sli' not in in_arr :
    print (__doc__)
    raise NameError('error: -sli option is not provided')
elif '-iFDJ' not in in_arr :
    print (__doc__)
    raise NameError('error: -iFDJ option is not provided')
elif '-iFDP' not in in_arr :
    print (__doc__)
    raise NameError('error: -iFDP option is not provided')
elif '-iTD' not in in_arr :
    print (__doc__)
    raise NameError('error: -iTD option is not provided')
elif '-ioFDJ' not in in_arr :
    print (__doc__)
    raise NameError('error: -ioFDJ option is not provided')
elif '-ioFDP' not in in_arr :
    print (__doc__)
    raise NameError('error: -ioFDP option is not provided')
elif '-ioTD' not in in_arr :
    print (__doc__)
    raise NameError('error: -ioTD option is not provided')
else:
    SSDvol1D = in_arr[in_arr.index('-ssdvol') + 1]
    SSDsli1D= in_arr[in_arr.index('-ssdsli') + 1]
    volsli1D = in_arr[in_arr.index('-volsli') + 1]
    slireg1D = in_arr[in_arr.index('-sli') + 1]
    iFDJ1D  = in_arr[in_arr.index('-iFDJ') + 1]
    iFDP1D  = in_arr[in_arr.index('-iFDP') + 1]
    iTD1D   = in_arr[in_arr.index('-iTD') + 1]
    ioFDJ1D = in_arr[in_arr.index('-ioFDJ') + 1]
    ioFDP1D = in_arr[in_arr.index('-ioFDP') + 1]
    ioTD1D  = in_arr[in_arr.index('-ioTD') + 1]
   

# read 1D files [ tdim x (zdim * 6 mopa)]
SSDvol = np.loadtxt(SSDvol1D)
SSDsli = np.loadtxt(SSDsli1D)
volsli = np.loadtxt(volsli1D)
sli    = np.loadtxt(slireg1D)
iFDJ   = np.loadtxt(iFDJ1D)
iFDP   = np.loadtxt(iFDP1D)
iTD    = np.loadtxt(iTD1D)
ioFDJ  = np.loadtxt(ioFDJ1D)
ioFDP  = np.loadtxt(ioFDP1D)
ioTD   = np.loadtxt(ioTD1D)

SSDvol = np.loadtxt('SSD.volmoco.1D')
SSDsli = np.loadtxt('SSD.slomoco.1D')
volsli = np.loadtxt('volslimot_py_fit.txt')
sli    = np.loadtxt('slimot_py_fit.txt')
iFDJ    = np.loadtxt('iFDJ_py.txt')
iFDP    = np.loadtxt('iFDP_py.txt')
iTD    = np.loadtxt('iTD_py.txt')
ioFDJ    = np.loadtxt('ioFDJ_py.txt')
ioFDP    = np.loadtxt('ioFDP_py.txt')
ioTD    = np.loadtxt('ioTD_py.txt')
# iTDz   = np.loadtxt('iTDz_py.txt')

# define variables
# define zmbdim, slireg = [ zmbdim*tdim x 6]
dims = np.shape(SSDvol)
tdim = int(dims[0])
dims = np.shape(sli)
zmbdim = int(dims[0]/(tdim))

# volmotion extention
volext = volsli - sli

# t table
ttable_vol = np.linspace(1,tdim,tdim)
ttable_vol_fd = fd = np.linspace(2,tdim,tdim-1)
ttable_sli = np.ones(zmbdim)
for t in range (2,tdim+1):
    tb = t*np.ones(zmbdim)
    ttable_sli = np.concatenate((ttable_sli,tb),axis=None)


# Make an example plot with two subplots...
plt.figure()
plt.subplot(3,1,1)
plt.plot(ttable_vol,SSDvol,'b')
plt.plot(ttable_vol,SSDsli,'r')
plt.title('SSD after motion correction (blue/red = VOLMOCO/SLOMOCO')
plt.xlabel('vols')
plt.ylabel('%')

plt.subplot(3,1,2)
plt.plot(ttable_vol,iFDJ,'b')
plt.plot(ttable_vol,iFDP,'r')
plt.plot(ttable_vol,iTD,'k')
plt.title('iFD (blue/red = Jenkinson / Power) & iTD (black)')
plt.xlabel('vols')
plt.ylabel('mm')

plt.subplot(3,1,3)
plt.plot(ttable_vol,ioFDJ,'b')
plt.plot(ttable_vol,ioFDP,'r')
plt.plot(ttable_vol,ioTD,'k')
plt.title('ioFD (blue/red = Jenkinson / Power) & ioTD (black)')
plt.xlabel('vols')
plt.ylabel('mm')

#ax1 = plt.subplot(3,1,3)
#ax2 = ax1.twinx()
#ax1.plot(ttable_vol,ioFDP, 'b')
#ax2.plot(ttable_vol,ioTDz, 'r')
#ax1.set_ylabel('iTD(mm)', color='b')
#ax2.set_ylabel('iTDz(mm)', color='r')
#ax1.set_xlabel('vols')
#ax1.set_title('intra-volume out-of-plane FD (blue/red = Jenkinson / Power) & ioTD (black)')

plt.tight_layout()
plt.savefig('qa_volslimoco_metrics_py.jpg')

# motion parameter
plt.figure()
plt.subplot(3,1,1)
plt.plot(ttable_sli,volext[:,0],'b')
plt.plot(ttable_sli,volsli[:,0],'r')
plt.title('z-rotation (blue/red = volmoco/slomoco)')
plt.subplot(3,1,2)
plt.plot(ttable_sli,volext[:,4],'b')
plt.plot(ttable_sli,volsli[:,4],'r')
plt.title('x-shift (mm)')
plt.subplot(3,1,3)
plt.plot(ttable_sli,volext[:,5],'b')
plt.plot(ttable_sli,volsli[:,5],'r')
plt.title('y-shift (mm)')

plt.tight_layout()
plt.savefig('qa_slomoco_inplane_motion_py.jpg')