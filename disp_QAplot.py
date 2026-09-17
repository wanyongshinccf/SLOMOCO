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
elif '-iTD' not in in_arr :
    print (__doc__)
    raise NameError('error: -iTD option is not provided')
elif '-FDJ' not in in_arr :
    print (__doc__)
    raise NameError('error: -ioFDJ option is not provided')
elif '-FDP' not in in_arr :
    print (__doc__)
    raise NameError('error: -iFDP option is not provided')
elif '-ioTD' not in in_arr :
    print (__doc__)
    raise NameError('error: -ioTD option is not provided')
else:
    SSDvol1D = in_arr[in_arr.index('-ssdvol') + 1]
    SSDsli1D= in_arr[in_arr.index('-ssdsli') + 1]
    volsli1D = in_arr[in_arr.index('-volsli') + 1]
    slireg1D = in_arr[in_arr.index('-sli') + 1]
    FDJ1D  = in_arr[in_arr.index('-FDJ') + 1]
    FDP1D  = in_arr[in_arr.index('-FDP') + 1]
    iTD1D   = in_arr[in_arr.index('-iTD') + 1]
    ioTD1D  = in_arr[in_arr.index('-ioTD') + 1]
   

# read 1D files [ tdim x (zdim * 6 mopa)]
SSDvol = np.loadtxt(SSDvol1D)
SSDsli = np.loadtxt(SSDsli1D)
volsli = np.loadtxt(volsli1D)
sli    = np.loadtxt(slireg1D)
FDJ    = np.loadtxt(FDJ1D)
FDP    = np.loadtxt(FDP1D)
iTD    = np.loadtxt(iTD1D)
ioTD   = np.loadtxt(ioTD1D)

#SSDvol = np.loadtxt('SSD.volmoco.1D')
#SSDsli = np.loadtxt('SSD.slomoco.1D')
#volsli = np.loadtxt('volslimot_py_fit.txt')
#sli    = np.loadtxt('slimot_py_fit.txt')
#FDJ    = np.loadtxt('FDJ_py.txt')
#FDP    = np.loadtxt('FDP_py.txt')
#iTD    = np.loadtxt('iTD_py.txt')
#ioTD    = np.loadtxt('ioTD_py.txt')

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
ttable_vol_FD = np.linspace(2,tdim,tdim-1)
ttable_vol_2pt = np.linspace(1,tdim,tdim)
iTD_outlier_2pt = np.ones(tdim) * 0.3
ioTD_outlier_2pt = np.ones(tdim) * 0.2

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
plt.title('SSD after moco + reg (blue/red = VOLMOCO/SLOMOCO)')
plt.xlabel('vols')
plt.ylabel('%')

plt.subplot(3,1,2)
plt.plot(ttable_vol_2pt,iTD_outlier_2pt,'r')
plt.plot(ttable_vol,iTD,'b')
plt.title('iTD (a red line is the outlier)')
plt.xlabel('vols')
plt.ylabel('mm')

plt.subplot(3,1,3)
plt.plot(ttable_vol_2pt,ioTD_outlier_2pt,'r')
plt.plot(ttable_vol,ioTD,'b')
plt.title('ioTD (a red line is the outlier)')
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