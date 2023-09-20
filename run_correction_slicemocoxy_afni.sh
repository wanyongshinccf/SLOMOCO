#!/bin/bash

function Usage () {
  cat <<EOF

 Usage:  run_correction_slicemocoxy.sh  -b ep2d_pace_132vols (for AFNI BRIK format)
 Flags:
  -b = base 3D+time EPI dataset you will run ICA and physio estimation upon
  -p = 3D+time EPI dataset you will save the output as
  -h = this help

EOF
  exit 1
}

while getopts hb:p: opt; do
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
  outputdata=$inputdata.slicemocoxy_afni
fi
tempslmoco=tempslmocoxy_afni_$inputdata
rm -rf $tempslmoco
if [ -d $tempslmoco ] ; then
  echo "Error: temporary files location \"$tempslmoco\" already exists: "
  echo "if you want to re-run, move or delete this folder before restarting"
  echo "Exiting..."
  exit 1
fi

# get orientation from AFNI 2dwarper code:
fullcommand="$0"
CODEDIR=`dirname $fullcommand`
parfixline=`$CODEDIR/get_orientation.sh $inputdata | tail -n 1`

if [ $? -gt 0 ] ; then
  echo "error running get_orientation.sh"
  exit 1
fi

if [ $AFNI_SLOMOCO = 'W' ]; then
  echo "3dWardrive is used for slicewise motion correction"
  echo "using \"$parfixline_W\" to fix to in-plane motion"
elif [ $AFNI_SLOMOCO = 'A' ]; then
  echo "3dAllineate is used for slicewise motion correction"
  echo "using \"$parfixline_A\" to fix to in-plane motion"
fi

inputdata=$inputdata+orig

dims=(`3dAttribute DATASET_DIMENSIONS $inputdata`)
tdim=`3dnvals $inputdata`
zdim=${dims[2]}
echo doing $zdim slices with $tdim timepoints

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

mkdir $tempslmoco
# use the mean image over time as the target (so all vols should have roughly the same partial voluming/blurring due to coreg)
3dTstat -mean -prefix $tempslmoco/__temp_vol_mean $inputdata > /dev/null 2>&1
3dAutomask -dilate 4 -prefix ./$tempslmoco/__temp_vol_mask $tempslmoco/__temp_vol_mean+orig > /dev/null 2>&1
3dcalc     -a $tempslmoco/__temp_vol_mean+orig -b $tempslmoco/__temp_vol_mask+orig -c a+i -d a-i -e a+j -f a-j  \
           -expr 'median(a,c,d,e,f)*b' -prefix $tempslmoco/__temp_vol_weight > /dev/null 2>&1

# problem: if no weighted voxels in given slice, use input tseries as output
let zcount=$zmbdim-1
let kcount=$zdim-1
let tcount=$tdim-1
let MBcount=$SMSfactor-1        

# define non-zero voxel threshold
nspace_min=4000
delta=(`3dAttribute DELTA $inputdata`)
xdim=${delta[0]}
ydim=${delta[1]}

# below seems to be a bug in SMS sequence. voxelsixe is negative sometimes
if [ $xdim -lt 0 ]; then
  xdim=${xdim/#-/}
fi
if [ $ydim -lt 0 ]; then
  ydim=${ydim/#-/}
fi

nvox_min=`echo "$nspace_min/$xdim/$ydim" | bc `
echo "nvox_min is set to " $nvox_min
echo "nvox_min is set to " $nvox_min >> slomoco_history.txt

for z in $(seq 0 $zcount) ; do
  zsimults=""
  kstart=1
  for mb in $(seq 0 $MBcount) ; do
    # update slice index
    let k=$mb*$zmbdim+$z
    zsimults="$zsimults $k"

    # split off each slice
    3dZcutup -keep $k $k -prefix $tempslmoco/__temp_slc_$mb        $inputdata > /dev/null 2>&1
    3dZcutup -keep $k $k -prefix $tempslmoco/__temp_slc_mean_$mb   $tempslmoco/__temp_vol_mean+orig > /dev/null 2>&1
    3dZcutup -keep $k $k -prefix $tempslmoco/__temp_slc_weight_$mb $tempslmoco/__temp_vol_weight+orig > /dev/null 2>&1
  done
 
  if [ $SMSfactor -gt 1 ]; then
    3dZcat -prefix $tempslmoco/__temp_slc        $tempslmoco/__temp_slc_?+orig.HEAD > /dev/null 2>&1
    3dZcat -prefix $tempslmoco/__temp_slc_mean   $tempslmoco/__temp_slc_mean_?+orig.HEAD > /dev/null 2>&1
    3dZcat -prefix $tempslmoco/__temp_slc_weight $tempslmoco/__temp_slc_weight_?+orig.HEAD > /dev/null 2>&1
  else
    3dcopy $tempslmoco/__temp_slc_0+orig        $tempslmoco/__temp_slc+orig > /dev/null 2>&1
    3dcopy $tempslmoco/__temp_slc_mean_0+orig   $tempslmoco/__temp_slc_mean+orig > /dev/null 2>&1
    3dcopy $tempslmoco/__temp_slc_weight_0+orig $tempslmoco/__temp_slc_weight+orig > /dev/null 2>&1
  fi
  rm $tempslmoco/__temp_slc_?+orig.???? $tempslmoco/__temp_slc_mean_?+orig.???? $tempslmoco/__temp_slc_weight_?+orig.????
  
  # test for minimum number of nonzero voxels:
  nvox=`3dBrickStat -non-zero -count $tempslmoco/__temp_slc_weight+orig`
  
   if [ $SMSfactor -gt 1 ]; then
    echo "doing slices $zsimults at once"     
    echo "doing slices $zsimults at once" >> slomoco_history.txt
  else
    echo "doing slice $zsimults"   
    echo "doing slice $zsimults" >> slomoco_history.txt
  fi            
  
  if [ $nvox -lt $nvox_min ] ; then
    echo "too many zero-ish voxels. Null warpdrive matrix will be generated"     
    echo "too many zero-ish voxels. Null warpdrive matrix will be generated" >> slomoco_history.txt        
    echo "You can modify nvox_min if necesary (default=4,000 mm^3)"
    echo "null warpdrive nvox_min if necesary (default=4,000 mm^3)" >> slomoco_history.txt 
  fi              
  
  disp_flag=1                                
  for t in $(seq 0 $tcount) ; do
    if [ $nvox -gt $nvox_min ] ; then
     if [ $AFNI_SLOMOCO = 'W' ]; then
        $AFNI_SLOMOCO_DIR/3dWarpDrive -affine_general -linear -final linear -maxite 300 -thresh 0.005 \
                 -prefix ./$tempslmoco/__temp_9999.hdr \
                 -base "$tempslmoco/__temp_slc_mean+orig"  \
                 -input "$tempslmoco/__temp_slc+orig[$t]" \
                 -weight "$tempslmoco/__temp_slc_weight+orig" \
                 -1Dfile $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.1D \
                 -1Dmatrix_save $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D \
                  $parfixline > /dev/null 2>&1
                  
      elif [ $AFNI_SLOMOCO = 'A' ]; then
        3dAllineate -cubic -final cubic -cost lpa -conv 0.005 -onepass \
                 -base "$tempslmoco/__temp_slc_mean+orig" \
                 -prefix ./$tempslmoco/__temp_9999.hdr \
                 -input  "$tempslmoco/__temp_slc+orig[$t]" \
                 -weight "$tempslmoco/__temp_slc_weight+orig"  \
                 -1Dfile $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.1D \
                 -1Dmatrix_save $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D \
                 $parfixline > /dev/null 2>&1
      fi
    else
      echo "# null 3dAllineate matrix
      1 0 0 0 0 1 0 0 0 0 1 0" > $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D
      
      echo "# null 3dAllineate/3dWarpdrive parameters:
      #  x-shift  y-shift  z-shift z-angle  x-angle$ y-angle$ x-scale$ y-scale$ z-scale$ y/x-shear$ z/x-shear$ z/y-shear$
      0 0 0 0 0 0 1 1 1 0 0 0" > $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.1D   
      
      3dcalc -a "$tempslmoco/__temp_slc+orig[$t]" -expr 'a' -prefix ./$tempslmoco/__temp_9999.hdr -overwrite > /dev/null 2>&1
    fi
    
    if [ -f ./$tempslmoco/__temp_9999.hdr ]; then
      # break down
      for mb in $(seq 0 $MBcount) ; do
        let k=$mb*$zmbdim+$z
        3dZcutup -keep $mb $mb -prefix $tempslmoco/__temp_`printf %04d $k`.`printf %04d $t`.hdr ./$tempslmoco/__temp_9999.hdr > /dev/null 2>&1
      done
    else
      if [ $disp_flag -eq 1 ]; then
        echo "Error: while running 3dWarpDrive in run_correction_slicemocoxy.sh
        echo "Use the correct version of 3dWarpDrive or "
        echo "lower nvox_min in run_correction_slicemocoxy.sh    
        disp_flag=0  
      fi
    fi  
    rm ./$tempslmoco/__temp_9999.*
  done
  
  for mb in $(seq 0 $MBcount) ; do
    let k=$mb*$zmbdim+$z
    3dTcat -prefix $tempslmoco/__temp_`printf %04d $k`.mocoinplane $tempslmoco/__temp_`printf %04d $k`.????.hdr > /dev/null 2>&1
    rm $tempslmoco/__temp_`printf %04d $k`.????.??? 
  done
  rm  $tempslmoco/__temp_slc*
done

if [ -f $outputdata+orig.BRIK ]; then
  rm ./$outputdata+orig.*
fi
3dZcat -prefix ./$outputdata $tempslmoco/__temp_0???.mocoinplane+orig.HEAD
rm $tempslmoco/__temp_0???.mocoinplane+orig.* $tempslmoco/__temp_vol_*

#copy over and save t-axis nums into new image registered dataset
3drefit -saveatr -atrcopy $inputdata TAXIS_NUMS $outputdata+orig
#copy over and save t-axis floats into new image
3drefit -saveatr -atrcopy $inputdata TAXIS_FLOATS $outputdata+orig
#copy over and save t-axis offsets into new image registered dataset
3drefit -Tslices `cat tshiftfile.1D` $outputdata+orig
3dNotes -h "run_correction_slicemocoxy_afni.sh $inputdata" $outputdata+orig

# rm $tempslmoco/__temp_*
echo "finished slicewise in-plane motion correction"
echo "Exiting"

