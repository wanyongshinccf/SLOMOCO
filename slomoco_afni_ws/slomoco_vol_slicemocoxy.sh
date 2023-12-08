#!/bin/bash

function Usage () {
  cat <<EOF

 Usage:  slomoco_vol_slicemocoxy.sh  -b ep2d_pace_132vols (for AFNI BRIK format)
 Flags:
  -b = base 3D+time EPI dataset you will run ICA and physio estimation upon
  -p = 3D+time EPI dataset you will save the output as
  -h = this help

EOF
  exit 1
}

while getopts hi:r:p:e:m:wa opt; do
  case $opt in
    h)
       Usage
       exit 1
       ;;
    i) # input 3D+time EPI dataset to use as <basename>
       epi=$OPTARG
       ;;
    r) # referrence = motsim 
       refvol=$OPTARG
       ;;
    p) # set output dataname prefix (default if not specified is the <basefilename>.slicemocoxy)
       outputdata=$OPTARG
       ;;
    e) # mask
       epi_mask=$OPTARG
       ;;
    m) # time-series affine matrix
       affmatrix=$OPTARG
       ;;
    w) # 3dWarpdrive
       SLOMOCO2d=W
	;;
    a) # 
       SLOMOCO2d=A
	;;
    :)
      echo "option requires input"
      exit 1
      ;;
  esac
done

# define SLOMOCO_DIR: Note that SLOMOCO_DIR is defined in each script now.
fullcommand="$0"
SLOMOCO_DIR=`dirname "${fullcommand}"`
AFNI_SLOMOCO=$SLOMOCO_DIR/afni_linux

# define directory & output
tempdir=inplane

# get orientation from AFNI 2dwarper code:
parfixline=`$SLOMOCO_DIR/get_orientation.sh $epi | tail -n 1`

# in this process, too many 2d slices will be saved and removed. 
# To save the computation time, compression process will be skipped if any
if [ "$AFNI_COMPRESSOR" = "GZIP" ]; then
  temp_AFNI_COMPRESSOR=$AFNI_COMPRESSOR
  export AFNI_COMPRESSOR=""
fi

# define variables
dims=(`3dAttribute DATASET_DIMENSIONS $epi`)
tdim=`3dnvals $epi`
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
elif [ $SMSfactor = $zdim ]; then
  echo "ERROR: all slice acquisition timing was time-shifted to zero"
  exit
fi

# define variables
let zmbdim=$zdim/$SMSfactor
let tcount=$tdim-1
let zcount=$zmbdim-1
let kcount=$zdim-1
let MBcount=$SMSfactor-1    
mkdir $tempdir
              
# define non-zero voxel threshold
# now 5cm x 5cm is the minimal size of 2d image to attempt image registration.
nspace_min=2500
delta=(`3dAttribute DELTA $epi`)
xdim=${delta[0]}
ydim=${delta[1]}

# below seems to be a bug in SMS sequence. voxelsixe is negative sometimes
xdim=${xdim/#-/}
ydim=${ydim/#-/}

nvox_min=`echo "$nspace_min/$xdim/$ydim" | bc `
echo "nvox_min is set to " $nvox_min

# prepare volume transformation matrix
1dtranspose $affmatrix > rm.col.aff12.1D

# new starts
total_start_time=$(date +%s.%3N)
for t in $(seq 0 $tcount) ; do
  start_time=$(date +%s.%3N)
  
  # select single volume of input, mask and reference
  3dcalc -a $refvol[$t]    -expr 'a' -prefix $tempdir/__temp_vol_base  -overwrite > /dev/null 2>&1
  3dcalc -a $epi[$t]       -expr 'a' -prefix $tempdir/__temp_vol_input -overwrite > /dev/null 2>&1
  3dcalc -a $epi_mask[$t]  -expr 'a' -prefix $tempdir/__temp_vol_mask  -overwrite > /dev/null 2>&1
  3dcalc -a $tempdir/__temp_vol_base+orig \
         -b $tempdir/__temp_vol_mask+orig \
         -expr 'a*step(b)' \
         -prefix $tempdir/__temp_vol_weight  -overwrite > /dev/null 2>&1
  
  # select single time point of 3dvolreg transformation matrix
  1d_tool.py -infile rm.col.aff12.1D[$t] -write rm.vol.col.aff12.1D -overwrite
  1dtranspose rm.vol.col.aff12.1D > rm.vol.aff12.1D 
    
  for z in $(seq 0 $zcount) ; do
    zsimults=""
    kstart=1
    for mb in $(seq 0 $MBcount) ; do
      # update slice index
      let k=$mb*$zmbdim+$z
      zsimults="$zsimults $k"

      # split off each slice
      3dZcutup -keep $k $k -prefix $tempdir/__temp_slc_$mb        $tempdir/__temp_vol_input+orig  > /dev/null 2>&1
      3dZcutup -keep $k $k -prefix $tempdir/__temp_slc_mask_$mb   $tempdir/__temp_vol_mask+orig   > /dev/null 2>&1
      3dZcutup -keep $k $k -prefix $tempdir/__temp_slc_base_$mb   $tempdir/__temp_vol_base+orig   > /dev/null 2>&1
      3dZcutup -keep $k $k -prefix $tempdir/__temp_slc_weight_$mb $tempdir/__temp_vol_weight+orig > /dev/null 2>&1
    done
 
    if [ $SMSfactor -gt 1 ]; then
      3dZcat -prefix $tempdir/__temp_slc        $tempdir/__temp_slc_?+orig.HEAD        -overwrite > /dev/null 2>&1
      3dZcat -prefix $tempdir/__temp_slc_mask   $tempdir/__temp_slc_mask_?+orig.HEAD   -overwrite > /dev/null 2>&1
      3dZcat -prefix $tempdir/__temp_slc_base   $tempdir/__temp_slc_base_?+orig.HEAD   -overwrite > /dev/null 2>&1
      3dZcat -prefix $tempdir/__temp_slc_weight $tempdir/__temp_slc_weight_?+orig.HEAD -overwrite > /dev/null 2>&1
    else
      3dcopy $tempdir/__temp_slc_0+orig        $tempdir/__temp_slc+orig        -overwrite > /dev/null 2>&1
      3dcopy $tempdir/__temp_slc_mask_0+orig   $tempdir/__temp_slc_mask+orig   -overwrite > /dev/null 2>&1
      3dcopy $tempdir/__temp_slc_base_0+orig   $tempdir/__temp_slc_base+orig   -overwrite > /dev/null 2>&1
      3dcopy $tempdir/__temp_slc_weight_0+orig $tempdir/__temp_slc_weight+orig -overwrite > /dev/null 2>&1
    fi
    rm -f $tempdir/__temp_slc_?+orig.* $tempdir/__temp_slc_base_?+orig.* $tempdir/__temp_slc_mask_?+orig.* $tempdir/__temp_slc_weight_?+orig.* 
  
    # test for minimum number of nonzero voxels:
    nvox=`3dBrickStat -non-zero -count $tempdir/__temp_slc_mask+orig`
    
    # display slice loop
    if [ $t -eq 0 ]; then
      if [ $SMSfactor -gt 1 ]; then
        echo "doing slices $zsimults at once"     
      else
        echo "doing slice $zsimults"   
      fi      
    else
      if [ $z -eq 0 ]; then            
        echo "doing volume $t"
      fi   
    fi
   
    if [ $nvox -gt $nvox_min ] ; then
      if [ $SLOMOCO2d = 'W' ]; then
        $AFNI_SLOMOCO/3dWarpDrive -affine_general -cubic -final cubic -maxite 300 -thresh 0.005 \
                  -prefix ./$tempdir/__temp_9999 \
                  -base   "$tempdir/__temp_slc_base+orig"  \
                  -input  "$tempdir/__temp_slc+orig" \
                  -weight "$tempdir/__temp_slc_weight+orig" \
                  -1Dfile $tempdir/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.1D \
                  -1Dmatrix_save $tempdir/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D \
                  $parfixline -overwrite  > /dev/null 2>&1
                  
      elif [ $SLOMOCO2d = 'A' ]; then
        3dAllineate -interp cubic -final cubic -cost nmi -conv 0.005 -onepass \
                  -prefix ./$tempdir/__temp_9999 \
                  -base   "$tempdir/__temp_slc_base+orig" \
                  -input  "$tempdir/__temp_slc+orig" \
                  -weight "$tempdir/__temp_slc_weight+orig"  \
                  -1Dfile $tempdir/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.1D \
                  -1Dmatrix_save $tempdir/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D \
                  $parfixline -overwrite > /dev/null 2>&1
      fi
    else
      echo $nvox of tissue voxels are too zero-sh at $k slice, $t volume 
      
      echo "# null 3dAllineate matrix
1 0 0 0 0 1 0 0 0 0 1 0" > $tempdir/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D
      echo "# null 3dAllineate/3dWarpdrive parameters:
      #  x-shift  y-shift  z-shift z-angle  x-angle$ y-angle$ x-scale$ y-scale$ z-scale$ y/x-shear$ z/x-shear$ z/y-shear$
0 0 0 0 0 0 1 1 1 0 0 0" > $tempdir/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.1D
      3dcalc -a $tempdir/__temp_slc+orig -expr 'a' -prefix $tempdir/__temp_9999 > /dev/null 2>&1
    fi
    
    # generating partial volume regressor
    cat_matvec $tempdir/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D > rm.sli.aff12.1D
    cat_matvec $tempdir/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D -I > rm.sli.inv.aff12.1D

    if [ -f ./$tempdir/__temp_9999+orig.HEAD ]; then
      # break down
      for mb in $(seq 0 $MBcount) ; do
        let k=$mb*$zmbdim+$z
        3dZcutup -keep $mb $mb -prefix $tempdir/__temp_slc_mocoxy.z`printf %04d $k` ./$tempdir/__temp_9999+orig  > /dev/null 2>&1
      done
    else
      echo "Error while running run_correction_vol_slicemocoxy_afni.sh"
      echo "Unexpected error: Welcome to my world."
    fi
    rm -f $tempdir/__temp_9999+orig.* $tempdir/__temp_slc+orig.* $tempdir/__temp_slc_base+orig.* \
          $tempdir/__temp_slc_mask+orig.* $tempdir/__temp_slc_weight+orig.*   
  done # z loop ends  
  
  if [ $t -eq 0 ]; then
    end_time=$(date +%s.%3N)
    elapsed=$(echo "scale=3; $end_time - $start_time" | bc)
    echo "slicewise motion correction will be done in $elapsed sec per volume"
  fi  
  
  # stack up slice images to volume image
  3dZcat -prefix $tempdir/__temp_vol_mocoxy+orig $tempdir/__temp_slc_mocoxy.z????+orig.HEAD  > /dev/null 2>&1
  rm $tempdir/__temp_slc_mocoxy.z????+orig.*
  
  # volume image moves back to baseline
  3dAllineate -prefix $tempdir/__temp_vol_mocoxy.t`printf %04d $t` -1Dmatrix_apply rm.vol.aff12.1D \
      -final cubic -input $tempdir/__temp_vol_mocoxy+orig -overwrite  > /dev/null 2>&1

  rm $tempdir/__temp_vol_mocoxy+orig.*
done
end_time=$(date +%s.%3N)
elapsed=$(echo "scale=3; $end_time - $total_start_time" | bc)
echo "Slice motion correction is done in $elapsed sec"

if [ "$temp_AFNI_COMPRESSOR" = "GZIP" ]; then
  export AFNI_COMPRESSOR="GZIP"
fi
  
# concatenate output         
3dTcat -prefix $outputdata $tempdir/__temp_vol_mocoxy.t????+orig.HEAD > /dev/null 2>&1
rm $tempdir/__temp_vol_mocoxy.t????+orig.*
  
# let's play with motion parameters here 
echo "# null 3dAllineate/3dWarpdrive parameters:
#  x-shift  y-shift  z-shift z-angle  x-angle$ y-angle$ x-scale$ y-scale$ z-scale$ y/x-shear$ z/x-shear$ z/y-shear$ " > $tempdir/motion.allineate.slicewise_inplane.header.1D

for z in $(seq 0 $zcount) ; do
  # flip motion para 1D file for concatenation
  for t in $(seq 0 $tcount) ; do
    1dcat $tempdir/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.1D > $tempdir/rm.inplane.add.1D
    1dtranspose $tempdir/rm.inplane.add.1D > $tempdir/rm.inplane.add.col.t`printf %04d $t`.1D

    1dcat $tempdir/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D > $tempdir/rm.inplane.add.1D
    1dtranspose $tempdir/rm.inplane.add.1D > $tempdir/rm.inplane.add.col.t`printf %04d $t`.aff12.1D
  done
    
  # conca rigid motion 6 par
  # note that 3dAllnieate 1dfile output is x-/y-/z-shift and z-/x-/y-rotation, ...
  # while 3dvolreg 1dfile ouput is z-/x-/y-rot and z-/x-/y-shift and shift direction is flipped
  # We store inplane 1d file from 3dWardrive (3dAllineate) while out-of-plane motion from 3dvolreg
  # 1d motion parameters are used as the regrsesor so that direction does not matter
  # flipped direction of x-/y-/z-shift and 3dAllneate convention will be handled in pre_slicemoco_regressor.sh and qa_slomoco.m
  1dcat $tempdir/rm.inplane.add.col.t????.1D > $tempdir/rm.motion.allineate.slicewise_inplane.col.1D
  1dtranspose $tempdir/rm.motion.allineate.slicewise_inplane.col.1D > $tempdir/rm.motion.allineate.slicewise_inplane.1D  
  cat $tempdir/motion.allineate.slicewise_inplane.header.1D $tempdir/rm.motion.allineate.slicewise_inplane.1D > $tempdir/motion.allineate.slicewise_inplane.`printf %04d $z`.1D 

  1dcat $tempdir/rm.inplane.add.col.t????.aff12.1D > $tempdir/rm.motion.allineate.slicewise_inplane.col.aff12.1D
  1dtranspose $tempdir/rm.motion.allineate.slicewise_inplane.col.aff12.1D > $tempdir/rm.motion.allineate.slicewise_inplane.aff12.1D
  1d_tool.py -infile $tempdir/rm.motion.allineate.slicewise_inplane.aff12.1D \
             -write $tempdir/motion.allineate.slicewise_inplane.`printf %04d $z`.aff12.1D -overwrite
              
  rm  $tempdir/rm.*.1D
done # z loop ends
       
# clean up
rm $tempdir/__temp_* $tempdir/motion.allineate.slicewise_inplane.z????.t????*1D  
rm rm.*aff12.1D 

#copy over and save t-axis nums into new image registered dataset
3drefit -saveatr -atrcopy $epi TAXIS_NUMS $outputdata+orig > /dev/null 2>&1
3drefit -saveatr -atrcopy $epi TAXIS_FLOATS $outputdata+orig > /dev/null 2>&1
3drefit -Tslices `cat tshiftfile.1D` $outputdata+orig > /dev/null 2>&1
3dNotes -h "run_correction_slicemocoxy_afni.sh $epi+orig" $outputdata+orig > /dev/null 2>&1

# rm $tempdir/__temp_*
echo "finished slicewise in-plane motion correction"
echo "Exiting"

