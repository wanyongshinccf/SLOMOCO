#!/bin/bash
# script to run EBB slicemoco algorithm:
# 1. average over time to make mean volume
# 2. split off each original slice timeseries
# 3. make a blurry/noisy (add gaussian noise comparable to thermal noise, then blur) 3D+time out of the mean image
# 4. re-interleave the slice of interest's original timeseries into this blurry volume
# 5. run 3dvolreg, save parameters
# do for all slices, then in MATLAB, multiply motion parameters by zdim # of slices
# and thats our slicewise timeseries
# compare with injected noise in pre- and post-mortem scans...

function Usage () {
  cat <<EOF

 Usage:  run_correction_slicemocoxy.sh  -b ep2d_pace_132vols (for AFNI BRIK format)
 Flags:
  -b = base 3D+time EPI dataset you will run ICA and physio estimation upon
  -p = 3D+time EPI dataset you will save the output as
  -c = cost function (lpa, hel, ls, mi, nmi, crA, crU, crM - see 3dAllineate for help)
  -h = this help

EOF
  exit 1
}
while getopts hc:b:p: opt; do
  case $opt in
    h)
       Usage
       exit 1
       ;;
    b) # base 3D+time EPI dataset to use as <basename>
       inputdata=$OPTARG
       ;;
    p) # set output dataname prefix (default if not specified is the <basefilename>.slicemocoxy)
       outputdata=$OPTARG
       ;;
    c) # set cost function
       cost=$OPTARG
       ;;
    :)
      echo "option requires input"
      exit 1
      ;;
  esac
done

if [ -z $inputdata ] ; then
  echo "3D+time EPI dataset $inputdata must be set"
  Usage
  exit 1
fi
if [ -z $outputdata ] ; then
  outputdata=$inputdata.slicemocoxy
fi
if [ -z $cost ] ; then
  cost="lpa"
fi
tempslmoco=tempslmoco_volslc_alg_vol_$inputdata
rm -rf $tempslmoco
if [ -d $tempslmoco ] ; then
  echo "Error: temporary files location \"$tempslmoco\" already exists: "
  echo "if you want to re-run, move or delete this folder before restarting"
  echo "Exiting..."
  exit 1
fi
inputdata=$inputdata+orig

dims=(`3dAttribute DATASET_DIMENSIONS $inputdata`)
tdim=`3dnvals $inputdata`
zdim=${dims[2]}
echo "doing $zdim slices with $tdim timepoints"
let tcount=$tdim-1
let zcount=$zdim-1

# calcuate SMS factor from slice timing
SLOMOCO_SLICE_TIMING=`cat tshiftfile.1D`
SMSfactor=0
for f in $SLOMOCO_SLICE_TIMING ; do
  if [ $f == 0 ]; then
    let "SMSfactor+=1"
  fi
done

if [ $SMSfactor == 0 ]; then
  echo "ERROR: slice acquisition timing does not have zero"
  exit
fi
if [ $SMSfactor = $zdim ]; then
  echo "ERROR: all slice acquisition timing was time-shifted to zero"
  exit
fi

let zmbdim=$zdim/$SMSfactor
let zmbcount=$zmbdim-1
let MBcount=$SMSfactor-1

mkdir $tempslmoco

# use the mean image over time as the target (so all vols should have roughly the same partial voluming/blurring due to coreg)
3dTstat -mean  -prefix $tempslmoco/__temp_mean $inputdata > /dev/null 2>&1
# 3dTstat -stdev -prefix $tempslmoco/__temp_stdev $inputdata > /dev/null 2>&1

# turn into a blurry, noisy 3D+time dataset using random noise injection
for t in $(seq 0 $tcount) ; do
  3dcalc -a $tempslmoco/__temp_mean+orig -expr 'a' -prefix $tempslmoco/__t_`printf %04d $t` > /dev/null 2>&1
done
3dTcat -prefix $tempslmoco/__temp_tseries_mean $tempslmoco/__t_????+orig.HEAD > /dev/null 2>&1
rm $tempslmoco/__t_????+orig.????

#3dmerge -1blur_fwhm 1.0 -doall -prefix $tempslmoco/__temp_mean_blur $tempslmoco/__temp_mean+orig
for z in $(seq 0 $zcount) ; do
  3dZcutup -keep $z $z -prefix $tempslmoco/__temp_tseries_mean_`printf %04d $z` $tempslmoco/__temp_tseries_mean+orig > /dev/null 2>&1
  3dZcutup -keep $z $z -prefix $tempslmoco/__temp_tseries_`printf %04d $z` $inputdata > /dev/null 2>&1
done
#rm $tempslmoco/__temp_mean_blur+orig.*

for z in $(seq 0 $zmbcount) ; do
  zsimults=""
  for mb in $(seq 0 $MBcount) ; do
    # update slice index
    let k=$mb*$zmbdim+$z
    zsimults="$zsimults $k"

    # first, temporarily move away the simulated tseries z-slice for this slice
    mv $tempslmoco/__temp_tseries_mean_`printf %04d $k`+orig.BRIK $tempslmoco/__tmpzBRIK_$mb
    mv $tempslmoco/__temp_tseries_mean_`printf %04d $k`+orig.HEAD $tempslmoco/__tmpzHEAD_$mb

    # and move original tseries into simnoise
    mv $tempslmoco/__temp_tseries_`printf %04d $k`+orig.BRIK $tempslmoco/__temp_tseries_mean_`printf %04d $k`+orig.BRIK
    mv $tempslmoco/__temp_tseries_`printf %04d $k`+orig.HEAD $tempslmoco/__temp_tseries_mean_`printf %04d $k`+orig.HEAD
  done

  if [ $SMSfactor -gt 1 ]; then
    echo "doing slices $zsimults at once"
  else
    echo "doing slice $zsimults"
  fi 

  # pad into volume using the mean image for adjacent slices
  rm -f $tempslmoco/__temp_input*
  3dZcat -prefix $tempslmoco/__temp_input $tempslmoco/__temp_tseries_mean_????+orig.HEAD > /dev/null 2>&1

  rm -f $tempslmoco/__temp_output*
  3dvolreg -zpad 2 -maxite 60 -cubic -prefix $tempslmoco/__temp_output \
           -base $tempslmoco/__temp_mean+orig \
           -1Dmatrix_save $tempslmoco/motion.wholevol_zt.`printf %04d $z`.aff12.1D \
           -1Dfile $tempslmoco/motion.wholevol_zt.`printf %04d $z`.1D \
           $tempslmoco/__temp_input+orig

  for mb in $(seq 0 $MBcount) ; do
    # update slice index
    let k=$mb*$zmbdim+$z
    # move the mean z-slice for this slice back into place
    mv $tempslmoco/__tmpzBRIK_$mb $tempslmoco/__temp_tseries_mean_`printf %04d $k`+orig.BRIK
    mv $tempslmoco/__tmpzHEAD_$mb $tempslmoco/__temp_tseries_mean_`printf %04d $k`+orig.HEAD
  done
done

rm -f $tempslmoco/__temp_* 

echo "finished slicewise in-plane motion correction"
echo "Exiting"

