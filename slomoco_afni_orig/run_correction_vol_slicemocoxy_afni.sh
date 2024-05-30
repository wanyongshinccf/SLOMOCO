#!/bin/bash

function Usage () {
  cat <<EOF

 Usage:  run_correction_vol_slicemocoxy.sh  -b ep2d_pace_132vols (for AFNI BRIK format)
 Flags:
  -b = base 3D+time EPI dataset you will run ICA and physio estimation upon
  -p = 3D+time EPI dataset you will save the output as
  -h = this help

EOF
  exit 1
}

while getopts hb:p:e: opt; do
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
    e) # mask
       epi_brain=$OPTARG
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

# define directory & output
tempslmoco=tempslmocoxy_afni_$inputdata
volmoco=$inputdata.mocoafni

# delete the pre-existing slomocoxy_afni directory
rm -rf $tempslmoco

# get orientation from AFNI 2dwarper code:
fullcommand="$0"
CODEDIR=`dirname $fullcommand`
parfixline=`$CODEDIR/get_orientation.sh $inputdata | tail -n 1`

if [ $? -gt 0 ] ; then
  echo "error running get_orientation.sh"
  exit 1
fi

if [ $AFNI_SLOMOCO = 'W' ]; then
  echo "3dWarpdrive is used for slicewise motion correction" >> slomoco_history.txt
  echo "3dWarpdrive is used for slicewise motion correction"      
elif [ $AFNI_SLOMOCO = 'A' ]; then     
 echo "3dAllineate is used for slicewise motion correction" >> slomoco_history.txt
 echo "3dAllineate is used for slicewise motion correction"      
fi
echo "using \"$parfixline\" to fix to in-plane motion" >> slomoco_history.txt
echo "using \"$parfixline\" to fix to in-plane motion" 

# define variables
dims=(`3dAttribute DATASET_DIMENSIONS $inputdata+orig`)
tdim=`3dnvals $inputdata+orig`
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

# define variables
let zmbdim=$zdim/$SMSfactor
let tcount=$tdim-1
let zcount=$zmbdim-1
let kcount=$zdim-1
let MBcount=$SMSfactor-1    
mkdir $tempslmoco

# select the base image
3dcalc -a $inputdata+orig[0] -expr 'a' -prefix $tempslmoco/__temp_vol_mean > /dev/null 2>&1
                 
# synthesize static image
for t in $(seq 0 $tcount) ; do
  3dcalc -a $tempslmoco/__temp_vol_mean+orig -expr 'a' -prefix $tempslmoco/__temp_static.`printf %04d $t`+orig > /dev/null 2>&1
done
3dTcat -prefix $tempslmoco/__temp_static+orig $tempslmoco/__temp_static.????+orig.HEAD > /dev/null 2>&1
rm -f $tempslmoco/__temp_static.*

# inject inverse volume motion on static images
3dAllineate -prefix $tempslmoco/__temp_static_volmotinj+orig -1Dmatrix_apply $volmoco.inv.aff12.1D \
  -source $tempslmoco/__temp_static+orig -final cubic > /dev/null 2>&1
3dAllineate -prefix $tempslmoco/__temp_vol.pvreg+orig -1Dmatrix_apply $volmoco.aff12.1D \
  -source $tempslmoco/__temp_static_volmotinj+orig -final cubic > /dev/null 2>&1  

# normalize vol pv regressor  
3dTstat -mean -prefix $tempslmoco/__temp_vol.pvreg.mean $tempslmoco/__temp_vol.pvreg+orig > /dev/null 2>&1
3dTstat -stdev -prefix $tempslmoco/__temp_vol.pvreg.std $tempslmoco/__temp_vol.pvreg+orig > /dev/null 2>&1
3dcalc -a $tempslmoco/__temp_vol.pvreg.mean+orig -b $tempslmoco/__temp_vol.pvreg.std+orig \
       -c $inputdata.brain+orig -d $tempslmoco/__temp_vol.pvreg+orig \
       -expr 'step(c)*(d-a)/b' -prefix $inputdata.vol.pvreg -overwrite > /dev/null 2>&1
rm  $tempslmoco/__temp_vol.pvreg* 

# use the mean image over time as the target (so all vols should have roughly the same partial voluming/blurring due to coreg)
for t in $(seq 0 $tcount) ; do
  3dcalc -a $epi_brain+orig -expr 'a' -prefix $tempslmoco/__temp_brain.`printf %04d $t`+orig > /dev/null 2>&1
done
3dTcat -prefix $tempslmoco/__temp_brain+orig $tempslmoco/__temp_brain.????+orig.HEAD > /dev/null 2>&1
rm -f $tempslmoco/__temp_brain.*

3dAllineate -prefix $tempslmoco/__temp_brain_volmotinj+orig -1Dmatrix_apply $volmoco.inv.aff12.1D \
  -source $tempslmoco/__temp_brain+orig -final cubic   
3dcalc     -a $tempslmoco/__temp_static_volmotinj+orig -b $tempslmoco/__temp_brain_volmotinj+orig \
           -expr 'a*step(b)' -prefix $tempslmoco/__temp_vol_weight_timeseries 
              
# define non-zero voxel threshold
# now 5cm x 5cm is the minimal size of 2d image to attempt image registration.
nspace_min=2500
delta=(`3dAttribute DELTA $inputdata+orig`)
xdim=${delta[0]}
ydim=${delta[1]}

# below seems to be a bug in SMS sequence. voxelsixe is negative sometimes
xdim=${xdim/#-/}
ydim=${ydim/#-/}

nvox_min=`echo "$nspace_min/$xdim/$ydim" | bc `
echo "nvox_min is set to " $nvox_min
echo "nvox_min is set to " $nvox_min >> slomoco_history.txt

# prepare volume transformation matrix
echo "1dtranspose $inputdata.mocoafni.aff12.1D > rm.col.aff12.1D"
      1dtranspose $inputdata.mocoafni.aff12.1D > rm.col.aff12.1D

# new starts
total_start_time=$(date +%s.%3N)
for t in $(seq 0 $tcount) ; do
  start_time=$(date +%s.%3N)
  # select the reference volume
  3dcalc -a $tempslmoco/__temp_static_volmotinj+orig[$t] -expr 'a' -prefix $tempslmoco/__temp_vol_base  -overwrite > /dev/null 2>&1
  3dcalc -a $inputdata+orig[$t] -expr 'a' -prefix $tempslmoco/__temp_vol_input -overwrite > /dev/null 2>&1
  3dcalc -a $tempslmoco/__temp_vol_weight_timeseries+orig[$t] -expr 'a' -prefix $tempslmoco/__temp_vol_weight -overwrite  > /dev/null 2>&1
  
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
      3dZcutup -keep $k $k -prefix $tempslmoco/__temp_slc_$mb        $tempslmoco/__temp_vol_input+orig  > /dev/null 2>&1
      3dZcutup -keep $k $k -prefix $tempslmoco/__temp_slc_base_$mb   $tempslmoco/__temp_vol_base+orig   > /dev/null 2>&1
      3dZcutup -keep $k $k -prefix $tempslmoco/__temp_slc_weight_$mb $tempslmoco/__temp_vol_weight+orig > /dev/null 2>&1
    done
 
    if [ $SMSfactor -gt 1 ]; then
      3dZcat -prefix $tempslmoco/__temp_slc        $tempslmoco/__temp_slc_?+orig.HEAD -overwrite  > /dev/null 2>&1
      3dZcat -prefix $tempslmoco/__temp_slc_base   $tempslmoco/__temp_slc_base_?+orig.HEAD -overwrite   > /dev/null 2>&1
      3dZcat -prefix $tempslmoco/__temp_slc_weight $tempslmoco/__temp_slc_weight_?+orig.HEAD -overwrite   > /dev/null 2>&1
    else
      3dcopy $tempslmoco/__temp_slc_0+orig        $tempslmoco/__temp_slc+orig -overwrite  > /dev/null 2>&1
      3dcopy $tempslmoco/__temp_slc_base_0+orig   $tempslmoco/__temp_slc_base+orig -overwrite  > /dev/null 2>&1
      3dcopy $tempslmoco/__temp_slc_weight_0+orig   $tempslmoco/__temp_slc_weight+orig -overwrite > /dev/null 2>&1
    fi
    rm -f $tempslmoco/__temp_slc_?+orig.* $tempslmoco/__temp_slc_base_?+orig.*  $tempslmoco/__temp_slc_weight_?+orig.* 
  
    # test for minimum number of nonzero voxels:
    nvox=`3dBrickStat -non-zero -count $tempslmoco/__temp_slc_weight+orig`
  
    # display slice loop
    if [ $t -eq 0 ]; then
      if [ $SMSfactor -gt 1 ]; then
        echo "doing slices $zsimults at once"     
      else
        echo "doing slice $zsimults"   
      fi     
      
      if [ $nvox -lt $nvox_min ] ; then
        if [ $AFNI_SLOMOCO = 'W' ]; then
          echo "too many zero-ish voxels. Null 3dWardrive matrix will be generated"     
          echo "too many zero-ish voxels. Null 3dWardrive matrix will be generated" >> slomoco_history.txt        
        elif [ $AFNI_SLOMOCO = 'A' ]; then
          echo "too many zero-ish voxels. Null 3dAllineate matrix will be generated"     
          echo "too many zero-ish voxels. Null 3dAllineate matrix will be generated" >> slomoco_history.txt 
        fi
        echo "You can modify nvox_min if necesary (default=2,500 mm^2)"
        echo "null warpdrive nvox_min if necesary (default=2,500 mm^2)" >> slomoco_history.txt 
      fi    
    else
      if [ $z -eq 0 ]; then            
        echo "doing volume $t"
      fi   
    fi
   
    if [ $nvox -gt $nvox_min ] ; then
      if [ $AFNI_SLOMOCO = 'W' ]; then
        $AFNI_SLOMOCO_DIR/3dWarpDrive -affine_general -cubic -final cubic -maxite 300 -thresh 0.005 \
                  -prefix ./$tempslmoco/__temp_9999 \
                  -base "$tempslmoco/__temp_slc_base+orig"  \
                  -input "$tempslmoco/__temp_slc+orig" \
                  -weight "$tempslmoco/__temp_slc_weight+orig" \
                  -1Dfile $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.1D \
                  -1Dmatrix_save $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D \
                  $parfixline -overwrite > /dev/null 2>&1
                  
      elif [ $AFNI_SLOMOCO = 'A' ]; then
        3dAllineate -interp cubic -final cubic -cost ls -conv 0.005 -onepass \
                 -base "$tempslmoco/__temp_slc_base+orig" \
                 -prefix ./$tempslmoco/__temp_9999 \
                 -input  "$tempslmoco/__temp_slc+orig" \
                 -weight "$tempslmoco/__temp_slc_weight+orig"  \
                 -1Dfile $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.1D \
                 -1Dmatrix_save $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D \
                 $parfixline -overwrite > /dev/null 2>&1
      fi
    else
      echo "# null 3dAllineate matrix
1 0 0 0 0 1 0 0 0 0 1 0" > $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D
      echo "# null 3dAllineate/3dWarpdrive parameters:
      #  x-shift  y-shift  z-shift z-angle  x-angle$ y-angle$ x-scale$ y-scale$ z-scale$ y/x-shear$ z/x-shear$ z/y-shear$
0 0 0 0 0 0 1 1 1 0 0 0" > $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.1D
      3dcalc -a $tempslmoco/__temp_slc+orig -expr 'a' -prefix $tempslmoco/__temp_9999 > /dev/null 2>&1
    fi
    
    # generating partial volume regressor
    cat_matvec $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D > rm.sli.aff12.1D
    cat_matvec $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D -I > rm.sli.inv.aff12.1D

    3dAllineate -prefix $tempslmoco/__temp_slc_pvreg1 -1Dmatrix_apply rm.sli.inv.aff12.1D \
      -source $tempslmoco/__temp_slc_base+orig -final linear -overwrite  > /dev/null 2>&1
    3dAllineate -prefix $tempslmoco/__temp_slc_pvreg2 -1Dmatrix_apply rm.sli.aff12.1D \
      -source $tempslmoco/__temp_slc_pvreg1+orig -final linear -overwrite  > /dev/null 2>&1

    if [ -f ./$tempslmoco/__temp_9999+orig.HEAD ]; then
      # break down
      for mb in $(seq 0 $MBcount) ; do
        let k=$mb*$zmbdim+$z
        3dZcutup -keep $mb $mb -prefix $tempslmoco/__temp_slc_mocoxy.z`printf %04d $k` ./$tempslmoco/__temp_9999+orig  > /dev/null 2>&1
        3dZcutup -keep $mb $mb -prefix $tempslmoco/__temp_slc_pvreg.z`printf %04d $k` ./$tempslmoco/__temp_slc_pvreg2+orig   > /dev/null 2>&1
      done
    else
      echo "Error while running run_correction_vol_slicemocoxy_afni.sh"
      echo "Unexpected error: Welcome to my world."
    fi
    rm $tempslmoco/__temp_9999+orig.* $tempslmoco/__temp_slc_pvreg?+orig.* 
    rm $tempslmoco/__temp_slc+orig.* $tempslmoco/__temp_slc_base+orig.*  $tempslmoco/__temp_slc_weight+orig.*   
    
  done # z loop ends  
  
  if [ $t -eq 0 ]; then
    end_time=$(date +%s.%3N)
    elapsed=$(echo "scale=3; $end_time - $start_time" | bc)
    echo "slicewise motion correction will be done in $elapsed sec per volume"
  fi  
  
  # stack up slice images to volume image
  3dZcat -prefix $tempslmoco/__temp_vol_pv+orig $tempslmoco/__temp_slc_pvreg.z????+orig.HEAD > /dev/null 2>&1
  3dZcat -prefix $tempslmoco/__temp_vol_mocoxy+orig $tempslmoco/__temp_slc_mocoxy.z????+orig.HEAD > /dev/null 2>&1
  rm $tempslmoco/__temp_slc_pvreg.z????+orig.* $tempslmoco/__temp_slc_mocoxy.z????+orig.*
  
  # volume image moves back to baseline
  3dAllineate -prefix $tempslmoco/__temp_vol_pv.t`printf %04d $t` -1Dmatrix_apply rm.vol.aff12.1D \
      -source $tempslmoco/__temp_vol_pv+orig -final cubic -overwrite > /dev/null 2>&1
  3dAllineate -prefix $tempslmoco/__temp_vol_mocoxy.t`printf %04d $t` -1Dmatrix_apply rm.vol.aff12.1D \
      -final cubic -input $tempslmoco/__temp_vol_mocoxy+orig -overwrite > /dev/null 2>&1
  rm $tempslmoco/__temp_vol_pv+orig.* $tempslmoco/__temp_vol_mocoxy+orig.*
done # t loop ends
end_time=$(date +%s.%3N)
elapsed=$(echo "scale=3; $end_time - $total_start_time" | bc)
echo "Slice motion correction is done in $elapsed sec"
  
# concatenate output  
3dTcat -prefix $tempslmoco/__temp_sli.pvreg $tempslmoco/__temp_vol_pv.t????+orig.HEAD > /dev/null 2>&1
3dTstat -mean -prefix $tempslmoco/__temp_sli.pvreg.mean $tempslmoco/__temp_sli.pvreg+orig > /dev/null 2>&1
3dTstat -stdev -prefix $tempslmoco/__temp_sli.pvreg.std $tempslmoco/__temp_sli.pvreg+orig > /dev/null 2>&1
3dcalc -a $tempslmoco/__temp_sli.pvreg.mean+orig -b $tempslmoco/__temp_sli.pvreg.std+orig \
       -c $inputdata.brain+orig -d $tempslmoco/__temp_sli.pvreg+orig \
       -expr 'step(c)*(d-a)/b' -prefix $inputdata.sli.pvreg 
       
3dTcat -prefix $outputdata $tempslmoco/__temp_vol_mocoxy.t????+orig.HEAD > /dev/null 2>&1
rm  $tempslmoco/__temp_vol_pv.t????+orig.* $tempslmoco/__temp_vol_mocoxy.t????+orig.*
  
# let's play with motion parameters here 
echo "# null 3dAllineate/3dWarpdrive parameters:
#  x-shift  y-shift  z-shift z-angle  x-angle$ y-angle$ x-scale$ y-scale$ z-scale$ y/x-shear$ z/x-shear$ z/y-shear$ " > $tempslmoco/motion.allineate.slicewise_inplane.header.1D

for z in $(seq 0 $zcount) ; do
  # flip motion para 1D file for concatenation
  for t in $(seq 0 $tcount) ; do
    1dcat $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.1D > $tempslmoco/rm.inplane.add.1D
    1dtranspose $tempslmoco/rm.inplane.add.1D > $tempslmoco/rm.inplane.add.col.t`printf %04d $t`.1D

    1dcat $tempslmoco/motion.allineate.slicewise_inplane.z`printf %04d $z`.t`printf %04d $t`.aff12.1D > $tempslmoco/rm.inplane.add.1D
    1dtranspose $tempslmoco/rm.inplane.add.1D > $tempslmoco/rm.inplane.add.col.t`printf %04d $t`.aff12.1D
  done
    
  # conca rigid motion 6 par
  # note that 3dAllnieate 1dfile output is x-/y-/z-shift and z-/x-/y-rotation, ...
  # while 3dvolreg 1dfile ouput is z-/x-/y-rot and z-/x-/y-shift and shift direction is flipped
  # We store inplane 1d file from 3dWardrive (3dAllineate) while out-of-plane motion from 3dvolreg
  # 1d motion parameters are used as the regrsesor so that direction does not matter
  # flipped direction of x-/y-/z-shift and 3dAllneate convention will be handled in pre_slicemoco_regressor.sh and qa_slomoco.m
  1dcat $tempslmoco/rm.inplane.add.col.t????.1D > $tempslmoco/rm.motion.allineate.slicewise_inplane.col.1D
  1dtranspose $tempslmoco/rm.motion.allineate.slicewise_inplane.col.1D > $tempslmoco/rm.motion.allineate.slicewise_inplane.1D  
  cat $tempslmoco/motion.allineate.slicewise_inplane.header.1D $tempslmoco/rm.motion.allineate.slicewise_inplane.1D > $tempslmoco/motion.allineate.slicewise_inplane.`printf %04d $z`.1D 

  1dcat $tempslmoco/rm.inplane.add.col.t????.aff12.1D > $tempslmoco/rm.motion.allineate.slicewise_inplane.col.aff12.1D
  1dtranspose $tempslmoco/rm.motion.allineate.slicewise_inplane.col.aff12.1D > $tempslmoco/rm.motion.allineate.slicewise_inplane.aff12.1D
  1d_tool.py -infile $tempslmoco/rm.motion.allineate.slicewise_inplane.aff12.1D \
             -write $tempslmoco/motion.allineate.slicewise_inplane.`printf %04d $z`.aff12.1D -overwrite
              
  rm  $tempslmoco/rm.*.1D
done # z loop ends
       
# clean up
rm $tempslmoco/__temp_* $tempslmoco/motion.allineate.slicewise_inplane.z????.t????*1D  
rm rm.*aff12.1D 

#copy over and save t-axis nums into new image registered dataset
3drefit -saveatr -atrcopy $inputdata+orig TAXIS_NUMS $outputdata+orig > /dev/null 2>&1
3drefit -saveatr -atrcopy $inputdata+orig TAXIS_NUMS $inputdata.sli.pvreg+orig 
3drefit -saveatr -atrcopy $inputdata+orig TAXIS_NUMS $inputdata.vol.pvreg+orig > /dev/null 2>&1

#copy over and save t-axis floats into new image
3drefit -saveatr -atrcopy $inputdata+orig TAXIS_FLOATS $outputdata+orig > /dev/null 2>&1
3drefit -saveatr -atrcopy $inputdata+orig TAXIS_FLOATS $inputdata.sli.pvreg+orig 
3drefit -saveatr -atrcopy $inputdata+orig TAXIS_FLOATS $inputdata.vol.pvreg+orig > /dev/null 2>&1

#copy over and save t-axis offsets into new image registered dataset
3drefit -Tslices `cat tshiftfile.1D` $outputdata+orig > /dev/null 2>&1
3drefit -Tslices `cat tshiftfile.1D` $inputdata.sli.pvreg+orig
3drefit -Tslices `cat tshiftfile.1D` $inputdata.vol.pvreg+orig > /dev/null 2>&1

3dNotes -h "run_correction_slicemocoxy_afni.sh $inputdata+orig" $outputdata+orig > /dev/null 2>&1
3dNotes -h "Time series vol-/sli-motion partial volume regressor" $inputdata.sli.pvreg+orig 
3dNotes -h "Time series volume motion partial volume regressor" $inputdata.vol.pvreg+orig > /dev/null 2>&1
 
# rm $tempslmoco/__temp_*
echo "finished slicewise in-plane motion correction"
echo "Exiting"

