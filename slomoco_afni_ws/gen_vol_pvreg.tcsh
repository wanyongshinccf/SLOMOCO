#!/bin/bash


function Usage () {
  cat <<EOF

 Usage:  gen_vol_pvreg.sh  -i epi  (for AFNI BRIK format)
 Flags:
  -b = base 3D+time EPI dataset you will run ICA and physio estimation upon
  -p = 3D+time EPI dataset you will save the output as
  -h = this help

EOF
  exit 1
}

epi=""
pvreg="epi_vol_pvreg" # default
while getopts hi:p:m: opt; do
  case $opt in
    h)
       Usage
       exit 1
       ;;
    i) # input 3D+time EPI dataset to use as <basename>
       epi=$OPTARG
       ;;
    p) # set output dataname prefix (default if not specified is the <basefilename>.slicemocoxy)
       pvreg=$OPTARG
       ;;
    m) # single time point of mask 
       epi_mask=$OPTARG
       ;;
    :)
      echo "option requires input"
      exit 1
      ;;
  esac
done

# handling input/output
if [ ${epi} == "" ]; then
  echo "** ERROR: Missing input data"
  exit
fi


# calc 6 DF (rigid) alignment pars
3dvolreg                                                                     \
    -verbose                                                                 \
    -prefix         epi_volreg                                       \
    -dfile          epi_volreg.txt                                        \
    -1Dfile         epi_volreg.1D                                         \
    -1Dmatrix_save  epi_volreg.aff12.1D                                   \
    -maxdisp1D      epi_volreg.maxdisp.1D                                 \
    -base           0                                                        \
    -zpad           2                                                        \
    -maxite         60                                                       \
    -x_thresh       0.005                                                    \
    -rot_thresh     0.008                                                    \
    -heptic                                                                  \
    ${epi}

# inverse affine matrix
cat_matvec epi_volreg.aff12.1D -I > epi_volreg_INV.aff12.1D

# generating motsim
tdim=`3dnvals ${epi}`
let tcount=$tdim-1

for t in $(seq 0 $tcount) ; do
  3dcalc -a ${epi}'[0]' -expr 'a' -prefix ___temp_static.`printf %04d $t`+orig  > /dev/null 2>&1
  3dcalc -a ${epi_mask} -expr 'a' -prefix ___temp_mask.`printf %04d $t`+orig    > /dev/null 2>&1
done

3dTcat -prefix ___temp_mask+orig   ___temp_mask.????+orig.HEAD   
3dTcat -prefix ___temp_static+orig ___temp_static.????+orig.HEAD  > /dev/null 2>&1
rm -f ___temp_static.* ___temp_mask.*

# inject inverse volume motion on static images
3dAllineate                                  \
  -prefix ___temp_mask4d+orig          \
  -1Dmatrix_apply epi_volreg_INV.aff12.1D \
  -source ___temp_mask+orig                  \
  -final NN 
3dAllineate                                  \
  -prefix epi_motsim+orig                 \
  -1Dmatrix_apply epi_volreg_INV.aff12.1D \
  -source ___temp_static+orig                \
  -final cubic 
3dAllineate \
  -prefix ___temp_vol_pvreg+orig            \
  -1Dmatrix_apply epi_volreg.aff12.1D    \
  -source epi_motsim+orig                \
  -final cubic 

# mask 
3dcalc -a ___temp_mask4d+orig -expr 'step(a)' -prefix epi_motsim_mask4d+orig -nscale        

# normalize vol pv regressor  
3dTstat -mean  -prefix ___temp_vol_pvreg_mean ___temp_vol_pvreg+orig 
3dTstat -stdev -prefix ___temp_vol_pvreg_std  ___temp_vol_pvreg+orig  
3dcalc -a ___temp_vol_pvreg_mean+orig          \
       -b ___temp_vol_pvreg_std+orig           \
       -c ${epi_mask}                          \
       -d ___temp_vol_pvreg+orig               \
       -expr 'step(b)*step(c)*(d-a)/b*step(b)' \
       -prefix epi_vol_pvreg
rm  ___temp* 

# copy header
3drefit -saveatr -atrcopy ${epi} TAXIS_NUMS   epi_vol_pvreg+orig 
3drefit -saveatr -atrcopy ${epi} TAXIS_FLOATS epi_vol_pvreg+orig 

