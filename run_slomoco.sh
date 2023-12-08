#! /bin/bash

function Usage () {
  cat <<EOF
   slicewise motion correction software (required PESTICA library package)
   
   Update history
   slomoco v5.5
   distributed separately from PESTICA
   
   compatibility issue with new version of AFNI commands, e.g. 3dWarpDrive
   SLOMOCO does not work with the latest version of AFNI 3dWarDrive command
   <<AFNI_SLOMOCO_DIR>> should be defined in setup_slomoco.sh depending on 
   which OS system you are using, e.g. linux or macOS
   The working version of LINUX AFNI commands are stored in <<AFNI_SLOMOCO_DIR>>
   However, we haven't found working version of 3dWarpDrive for Mac.
   In case that you use MAC, you have two options.
   1) find the working version of 3dWarpDrive and compile/use it
   2) Use 3dAllineate instead of 3dWarpDrive. To do it, you should set <<AFNI_SLOMOCO>>=A
   in setup_slomoco.sh. However, we found the different final result when using
   3dAllineate based on 3dWarpDrive. We are investigating, but yours is also welcome.
                           
  Check "readme.txt" file in <<AFNI_PESTIAC_DIR>>
  Feel free to add the working version of commands if necesary.
  debugging a few

  update from v5.2 to v5.3
  It was reported that accidental slow trending was added after SLOMOCO output.
  If you runs any detrending or temporal filtering, e.g. <0.01Hz, the previous 
  version of output should generate the same result from v5.3  

   Update from v5.x to v5.5
   ==============================================================================   
   DO NOT use any motion corrected data as an input in slicemoco_newalgorithm.sh.
   ==============================================================================
   IF your data is acquired using Siemens ep2d_pace (retrospective motion correction)
     The preivous version of SLOMOCO (v5.4) should be used.
     ep2d_PACE data already includes 3d volume registration by refining the relative cordinate at each volume. 
   IF your data is acquired with ep2d_bold or conventional EPI sequence
     INPUT SHOULD BE NO-MOTION-CORRECTED DATA
     the pipeline includes 3d volume registration process.
   
   SLICE ACQUISITION TIMING
   We strongly suggest to provide slice acquisition timing file, named as "tshiftfile_sec.1D"
   Each row includes the slince acquisition time with a second unit.
   tshiftfile_sec.1D file will be copied to SLOMOCO directory and renamed as "tshiftfile.1D" 
   If -p or -r option is selected, tshiftfile.1D should be located in PESTICA5 or PHYSIO directory,
   and it will be copied to SLOMOCO5 directory
   If tshiftfile_sec.1D is not provided, the script assumes single band EPI with the interleaved order,
   and tshiftfile.1D is generated. CHECK GENERATED TSHIFT FILE.
  
   Algorithm: this script first runs slicewise in-plane (xy) 3DOF motion correction
              then runs a slicewise 6DOF rigid-body correction for each slice
	      this script reads these motion parameters back in and regress on voxel timeseries
   
   WARNING, make sure you have removed unsaturated images at start 
   You can test first volumes for spin saturation with: 3dToutcount <epi_filename> | 1dplot -stdin -one
   Is the first volume much higher than rest? If so, you may need to remove first several volumes first
   If you don't know what this means, consult someone who does know, this is very important,
   regression corrections (and analyses) perform poorly when the data has unsaturated volumes at the start
   Simple method to remove 1st 4: 3dcalc -a "<epi_file>+orig[4..$]" -expr a -prefix <epi_file>.steadystate

 Usage:  run_slomoco.sh -d <epi_filename>  -m MBfactor
 	     -d = dataset: <epi_filename> is the file prefix of
	     the 3D+time dataset to use and correct.
               Note: this script will detect suffix for epi_filename

         run_slomoc.sh -d <epi_filename> -r
             -r = perform in parallel with final PESTICA regression correction
                  this assumes PESTICA estimation steps 1-5 have been run and exist in subdir pestica5/

         run_slomoc.sh -d <epi_filename> -p
             -p = same as -r option, but assuming you used PMU data instead of PESTICA for the correction

 Recommended, run after running PESTICA or PMU correction, so we can incorporate all regressions in parallel:
	       run_slomoc.sh -d <epi_file> -r
	   OR, run_slomoc.sh -d <epi_file> -p

 output: <input file name>.slicemocoxy_afni.slomoco
         <input file name>.slicemocoxy_afni.slomoco.pmu
         <input file name>.slicemocoxy_afni.slomoco.pestica
           slicewise motion correction and second order motion/RETROICOR/PESTICA regresed out from input file 

         <input file name>.slicemocoxy_afni.slomoco.bucket
         <input file name>.slicemocoxy_afni.slomoco.pmu.bucket
         <input file name>.slicemocoxy_afni.slomoco.pestica.bucket
	   fitting results 

         <input file name>.slicemocoxy_afni.slomoco.errt
         <input file name>.slicemocoxy_afni.slomoco.pmu.errt
         <input file name>.slicemocoxy_afni.slomoco.pestica.errt
           residual time-series after slicewise motion correction, motion/physio regress-out and detrending  
	
         slomoco.TDmetric.txt & slomoco.TDzmetric.txt    
           slicewise motion index parameter - used as an outlier (see Bealls and Mark's paper, 2014) 

EOF
  exit 1
}

slomocov=5
phypes=0
phypmu=0
physiostr=PHYSIO
pesticstr=PESTICA5
slomocostr=SLOMOCO$slomocov
corrstr=slicemocoxy_afni.slomoco
MBfactor=1 
nVolEndCutOff=0   # no EPI volumes at the end were truncated as default
nVolFirstCutOff=0 # truncate the first few points
maskflag=0
inplaneflag=0
sliacqorder="alt+z"
deletemeflag=0

while getopts hd:u:m:f:t:e:rpiadc opt; do
  case $opt in
    h)
       Usage
       exit 1
       ;;
    d) # base 3D+time EPI dataset to use to perform corrections
       epi=$OPTARG
       ;;
    u) # unsaturated EPI image, usually Scout_gdc.nii.gz
       unsatepi=$OPTARG
      ;;
    m) # MB acceleration factor
       MBfactor=$OPTARG
       ;;
    f) # the number of volumes truncted at the first of the EPI acquisitions
       nVolFirstCutOff=$OPTARG
       ;;
    t) # the number of volumes truncted at the end of the EPI acquisitions
       nVolEndCutOff=$OPTARG
       echo nVolEndCutOff=$nVolEndCutOff
       ;;
    e) # mask
       epi_mask=$OPTARG
       maskflag=1
       ;;
    r)
       phypes=1
       ;;
    p)
       phypmu=1
       ;;
    i) # if you are using ep2d_pace data
       inplaneflag=1
       ;;
    a) # ascending slice acquisition order
       sliacqorder=asc
       ;;
    d) # ep2d_bold case or out-of-plane motion
       sliacqorder=des
       ;;
    c) # compact mode, delete intermediate files
       deletemeflag=1
       ;;
    :)
      echo "option requires input"
      exit 1
      ;;
  esac
done


# test if epi filename was set
if [ -z $epi ] ; then
  echo "3D+time EPI dataset $epi must be given"
  Usage
  exit 1
fi

# remove "." if the input file name ends with "." 
nstr=$((${#epi}-1))
if [ "${epi:$nstr:1}" = "." ]; then
  epi=${epi:0:$nstr}
fi

# test for presence of input EPI file with one of the accepted formats and set suffix
epinosuffix=${epi%.*}
suffix="${epi##*.}"
if [ "$suffix" = "hdr" ] || [ "$suffix" = "nii" ]; then
  epi=$epinosuffix
  suffix=.$suffix
elif [ "$suffix" = "gz" ]; then
  epi=$epinosuffix
  epinosuffix=${epi%.*}
  suffix2="${epi##*.}"
  suffix=.$suffix2.$suffix
  epi=$epinosuffix
elif [ "$suffix" = "HEAD" ]; then
  nstr=$((${#str}-9))
  epi_org=${epi:$nstr:4}
  if [ $epi_org == tlrc ]; then
    echo "PESTICA needs original EPI data set as input, not Talarigh or MNI space data"
    exit 2 
  fi
  epi=${epinosuffix%+orig}
  suffix="+orig.HEAD"
else  # when input file is given without postfix
  if [ -f $epi.hdr ] ; then
    suffix=".hdr"
  elif [ -f $epi.HEAD ] ; then
    epi=${epi%+orig}
    suffix="+orig.HEAD"
  elif [ -f $epi+orig.HEAD ] ; then
    suffix="+orig.HEAD"
  elif [ -f $epi+tlrc.HEAD ] ; then
    echo "PESTICA needs original EPI data set as input, not Talarigh or MNI space data"
    exit 2 
  elif [ -f $epi.nii ] ; then
    suffix=".nii"
  elif [ -f $epi.nii.gz ] ; then
    suffix=".nii.gz"
  else  
    echo "3D+time EPI dataset $epi must exist, check filename "
    echo "accepted formats: hdr  +orig  nii  nii.gz"
    echo "accepted inputs: with/without <.hdr>, <.HEAD>, <+orig.HEAD>, <nii> or <nii.gz>"
    echo ""
    echo "*****   $epi does not exist, exiting ..."
    exit 2
  fi
fi

fullcommand="$0"
if [ -z $SLCMOCO_DIR ] ; then
  echo "setting SLCMOCO_DIR to directory where this script is located (not the CWD)"
  SLCMOCO_DIR=`dirname $fullcommand`
  # this command resides in the moco/ subdirectory of PESTICA_DIR
  export SLCMOCO_DIR=$SLCMOCO_DIR
fi

# first test if we are running run_pestica.sh from the base SLCMOCO_DIR
homedir=`pwd`
if [ $homedir == $SLCMOCO_DIR ] ; then
  echo "you cannot run PESTICA from the downloaded/extracted SLCMOCO_DIR"
  echo "please run this from the directory containing the data (or copy of the data)"
  echo "that you want to correct.  Exiting..."
  exit 1
fi

# create SLOMOCO subdirectory if it does not exist
if [ -d $slomocostr ] ; then
  echo $slomocostr directory already exists.
  echo The previous output in $slomocostr directory will be used without overwriting.
  echo If you like to overwrite the previous output, delete $slomocostr directory and re-run it as a clean version
else
  echo ""
  echo "* Creating SLOMOCO Directory: $slomocostr"
  echo ""
  mkdir $slomocostr
  echo "mkdir $slomocostr" >> $slomocostr/slomoco_history.txt
  echo "" >> $slomocostr/slomoco_history.txt
fi    
  
if [ $phypmu -eq 1 ] ; then
  if [ -d $physiostr ]; then
    echo Second order SLOMOCO will be conducted with RETROICOR physio regressors
    echo Second order SLOMOCO will be conducted with RETROICOR physio regressors >> $slomocostr/slomoco_history.txt
    echo CAUTION: Failure or missing output files of RETROICOR causes errors 
    echo CAUTION: Failure or missing output files of RETROICOR causes errors >> $slomocostr/slomoco_history.txt
    epi_physio=pmu
    slomocoout=$epi.$corrstr.$epi_physio
  else
    echo $physiostr directory does not exists.
    echo $physiostr directory does not exists. >> $slomocostr/slomoco_history.txt
    echo run RETROICOR first or re-run without -p option
    echo run RETROICOR first or re-run without -p option >> $slomocostr/slomoco_history.txt
    exit 1
  fi
elif [ $phypes -eq 1 ] ; then
  if [ -d $pesticstr ]; then
    echo Second order SLOMOCO will be conducted with PESTICA physio regressors
    echo Second order SLOMOCO will be conducted with PESTICA physio regressors >> $slomocostr/slomoco_history.txt
    echo CAUTION: Failure or missing output files of PESTICA causes errors 
    echo CAUTION: Failure or missing output files of PESTICA causes errors >> $slomocostr/slomoco_history.txt
    epi_physio=pestica
    slomocoout=$epi.$corrstr.$epi_physio
  else
    echo $pesticstr directory does not exists.
    echo $pesticstr directory does not exists. >> $slomocostr/slomoco_history.txt
    echo run PESTICA first or re-run without -r option
    echo run PESTICA first or re-run without -r option >> $slomocostr/slomoco_history.txt
    exit 1
  fi
else
  echo Note: Second order SLOMOCO will be conducted without physio regressors
  echo Note: Second order SLOMOCO will be conducted without physio regressors >> $slomocostr/slomoco_history.txt 
  epi_physio=dummy
  slomocoout=$epi.$corrstr
fi
  
# write command line and SLCMOCO_DIR to history file
echo "==========================================" >> $slomocostr/slomoco_history.txt
echo "`date`" >> $slomocostr/slomoco_history.txt
echo "SLOMOCO_afni-v${pesticav} command line: `basename $fullcommand` $*" >> $slomocostr/slomoco_history.txt
echo "SLOMOCO env: `env | grep SLOMOCO`" >> $slomocostr/slomoco_history.txt
echo "PESTICA env: `env | grep PESTICA`" >> $slomocostr/slomoco_history.txt
echo "" >> $slomocostr/slomoco_history.txt

# change directory and redefine file name
cd $slomocostr
echo "cd $slomocostr" >> slomoco_history.txt
echo "" >> slomoco_history.txt

echo "*****   Using $epi+orig.HEAD as input timeseries"
if [ $nVolFirstCutOff -gt 0 ]; then
  if [ ! -f $epi.trunc"${nVolFirstCutOff}"+orig.BRIK ]; then
    echo "Removing the first "${nVolFirstCutOff}" volumes"
    echo 3dcalc -a ../$epi$suffix["${nVolFirstCutOff}"..$] -expr 'a' -prefix $epi.trunc"${nVolFirstCutOff}"+orig 
    echo 3dcalc -a ../$epi$suffix["${nVolFirstCutOff}"..$] -expr 'a' -prefix $epi.trunc"${nVolFirstCutOff}"+orig >> slomoco_history.txt
         3dcalc -a ../$epi$suffix["${nVolFirstCutOff}"..$] -expr 'a' -prefix $epi.trunc"${nVolFirstCutOff}"+orig
    epi=$epi.trunc"${nVolFirstCutOff}"
  fi
else
  if [ ! -f $epi+orig.BRIK ]; then
    echo "Copying: 3dcopy ../$epi$suffix $epi+orig"
    echo "3dcopy ../$epi$suffix $epi+orig"  >> slomoco_history.txt
          3dcopy ../$epi$suffix $epi+orig
  fi
fi

# do ALL work inside the slomoco/ subdirectory
homedir=`pwd`

# import or generate a mask file
if [ $maskflag -gt 0 ]; then
  # remove .
  nstr=$((${#epi_mask}-1))
  if [ "${epi_mask:$nstr:1}" = "." ]; then
    epi_mask=${epi_mask:0:$nstr}
  fi
  if [ -f ../$epi_mask.HEAD ] || [ -f ../$epi_mask ]; then
    echo "copy brain mask" 
    echo 3dcalc -a ../$epi_mask -expr 'a' -prefix $epi.brain+orig -overwrite
    echo 3dcalc -a ../$epi_mask -expr 'a' -prefix $epi.brain+orig -overwrite >> physiocor_history.txt
         3dcalc -a ../$epi_mask -expr 'a' -prefix $epi.brain+orig -overwrite
    epi_mask=$epi.brain
  else
    echo "Error: Cannot find manual mask"
    exit 2
  fi
else
  epi_mask="$epi".brain
  if [ -f $epi_mask+orig.HEAD ] ; then 
    echo SKIP: $epi_mask+orig.HEAD exists.
  else
    if [ -f ../$epi_mask$suffix ] ; then
      echo 3dcopy ../$epi_mask$suffix "$epi".brain+orig
      echo 3dcopy ../$epi_mask$suffix "$epi".brain+orig >> physiocor_history.txt
           3dcopy ../$epi_mask$suffix "$epi".brain+orig 
    else
      echo ""
      echo "*****   $epi_mask+orig.HEAD does not exist, creating mask"
      echo "note, if you wish to use your own mask/brain file, kill this script"
      echo "then generate your own mask file and use -e option"
      echo ""
      echo "running 3dSkullStrip -input  $epi+orig -prefix $epi_mask"
      echo "3dSkullStrip -input $epi+orig -prefix ___tmp_mask" >> physiocor_history.txt
            3dSkullStrip -input $epi+orig -prefix ___tmp_mask

      # dilate mask by one voxel
      3dcalc -a ___tmp_mask+orig -prefix ___tmp_mask_ones+orig -expr 'step(a)'
      3dcalc -a ___tmp_mask_ones+orig -prefix ___tmp_mask_ones_dil -b a+i -c a-i -d a+j -e a-j -f a+k -g a-k -expr 'amongst(1,a,b,c,d,e,f,g)'
      3dcalc -a "$epi+orig[0]" -b ___tmp_mask_ones_dil+orig -prefix $epi_mask -expr 'a*step(b)'
      rm ___tmp_mask*
      echo ""
      echo "done with skull-stripping - please check file and if not satisfied, I recommend running"
      echo "3dSkullStrip with different parameters to attempt to get a satisfactory brain mask."
      echo "Either way, this script looks in $epi_physio/ for $epi_mask to use as your brain mask/strip"
      sleep 1
      echo "3dcalc -a ___tmp_mask+orig -prefix ___tmp_mask_ones+orig -expr 'step(a)'" >> physiocor_history.txt
      echo "3dcalc -a ___tmp_mask_ones+orig -prefix ___tmp_mask_ones_dil -b a+i -c a-i -d a+j -e a-j -f a+k -g a-k -expr 'amongst(1,a,b,c,d,e,f,g)'" >> physiocor_history.txt
      echo "3dcalc -a "$epi+orig[0]" -b ___tmp_mask_ones_dil+orig -prefix $epi_mask -expr 'a*step(b)'" >> physiocor_history.txt
      echo "rm ___tmp_mask*" >> physiocor_history.txt
      echo "" >> physiocor_history.txt
    fi
  fi
fi
echo "*****   Using $epi_mask+orig.HEAD to mask out non-brain voxels"
echo "*****   Using $epi+orig.HEAD as input timeseries"

# generate slice time shift info file
if [ -f ../tshiftfile.1D ]; then
  echo "Slice acqusition timing information is read from a tshiftfile.1D file"
  echo cp ../tshiftfile.1D .
       cp ../tshiftfile.1D . >> slomoco_history.txt
       cp ../tshiftfile.1D .
elif [ -f ../tshiftfile_sec.1D ]; then
  echo "Slice acqusition timing information is read from a tshiftfile_sec.1D file"
  echo 1dtranspose ../tshiftfile_sec.1D tshiftfile.1D
       1dtranspose ../tshiftfile_sec.1D tshiftfile.1D >> slomoco_history.txt
       1dtranspose ../tshiftfile_sec.1D tshiftfile.1D
else
  echo "tshiftfile_sec.1D is not provided with input."
  echo "tshiftfile_sec.1D is not provided with input." >> slomoco_history.txt
  if [ $phypmu -eq 1 ] ; then
    echo cp ../$physiostr/tshiftfile.1D tshiftfile.1D
    echo cp ../$physiostr/tshiftfile.1D tshiftfile.1D >> slomoco_history.txt
         cp ../$physiostr/tshiftfile.1D tshiftfile.1D
  elif [ $phypes -eq 1 ]  ; then
    echo cp ../$pesticstr/tshiftfile.1D tshiftfile.1D
    echo cp ../$pesticstr/tshiftfile.1D tshiftfile.1D >> slomoco_history.txt
         cp ../$pesticstr/tshiftfile.1D tshiftfile.1D
  else
    echo "tshiftfile.1D will be generated with MB = $MBfactor"
    echo "tshiftfile.1D will be generated with MB = $MBfactor" >> slomoco_history.txt
  
    echo "Note that new PESTICA needs MB factor as an input"
    if [ $MBfactor -eq 1 ]; then
      echo "Alternative ascending acquisition order of single band EPI is assumed."
    else
      echo "Alternative ascending acquisition order of multi band EPI is assumed." 
    fi
    echo "If any other acquisition than alternative ascending alt+z is used, modify genSMStimeshiftfile.m or its input."

    echo matlab $MATLABLINE <<<"addpath $MATLAB_PESTICA_DIR; addpath $MATLAB_AFNI_DIR; [err,Info] = BrikInfo('$epi+orig'); genSMStimeshiftfile($MBfactor, Info.DATASET_DIMENSIONS(3),Info.TAXIS_FLOATS(2),'$sliacqorder'); exit;" 
    echo matlab $MATLABLINE <<<"addpath $MATLAB_PESTICA_DIR; addpath $MATLAB_AFNI_DIR; [err,Info] = BrikInfo('$epi+orig'); genSMStimeshiftfile($MBfactor, Info.DATASET_DIMENSIONS(3),Info.TAXIS_FLOATS(2),'$sliacqorder'); exit;" >> slomoco_history.txt
         matlab $MATLABLINE <<<"addpath $MATLAB_PESTICA_DIR; addpath $MATLAB_AFNI_DIR; [err,Info] = BrikInfo('$epi+orig'); genSMStimeshiftfile($MBfactor, Info.DATASET_DIMENSIONS(3),Info.TAXIS_FLOATS(2),'$sliacqorder'); exit;" 
    1dtranspose tshiftfile_sec.1D tshiftfile.1D -overwrite
  fi
fi
echo "The following slice acquisition timing shift is used."
echo "The following slice acquisition timing shift is used." >> slomoco_history.txt
cat tshiftfile.1D 
cat tshiftfile.1D  >> slomoco_history.txt
echo "If this shift is not correct, SLOMOCO will not work."
echo "If this shift is not correct, SLOMOCO will not work." >> slomoco_history.txt

##### calculate vol moco parameter###
if [ -f $epi.mocoafni.1D ] && [ -f $epi.mocoafni+orig.HEAD ] && [ -f $epi.mocoafni.aff12.1D ] ; then
  echo "SKIP; 3dvolume registration has been done."
else
  if [ -f ../$epi.mocoafni.txt ] && [ -f $epi.mocoafni+orig.HEAD ] && [ -f ../$epi.mocoafni.1D ] && [ -f ../$epi.mocoafni.maxdisp.1D ] && [ -f ../$epi.mocoafni.aff12.1D ]; then
    echo cp ../$epi.mocoafni.txt $epi.mocoafni.txt
    echo cp ../$epi.mocoafni.txt $epi.mocoafni.txt >> slomoco_history.txt
         cp ../$epi.mocoafni.txt $epi.mocoafni.txt
    echo cp ../$epi.mocoafni.1D  $epi.mocoafni.1D     
    echo cp ../$epi.mocoafni.1D  $epi.mocoafni.1D >> slomoco_history.txt
         cp ../$epi.mocoafni.1D  $epi.mocoafni.1D
    echo cp ../$epi.mocoafni.maxdisp.1D   $epi.mocoafni.maxdisp.1D 
    echo cp ../$epi.mocoafni.maxdisp.1D   $epi.mocoafni.maxdisp.1D >> slomoco_history.txt
         cp ../$epi.mocoafni.maxdisp.1D   $epi.mocoafni.maxdisp.1D 
    echo cp ../$epi.mocoafni+orig.* .     
    echo cp ../$epi.mocoafni+orig.* . >> slomoco_history.txt
         cp ../$epi.mocoafni+orig.* .
    echo cp ../$epi.mocoafni.aff12.1D .     
    echo cp ../$epi.mocoafni.aff12.1D . >> slomoco_history.txt
         cp ../$epi.mocoafni.aff12.1D .
  else
    echo "3dvolreg -prefix $epi.mocoafni+orig -base 0 -zpad 2 -maxite 60 -x_thresh 0.005 -rot_thresh 0.008 -verbose -dfile $epi.mocoafni.txt -1Dfile $epi.mocoafni.1D -1Dmatrix_save $epi.mocoafni.aff12.1D -maxdisp1D $epi.mocoafni.maxdisp.1D -heptic $epi+orig"
    echo "3dvolreg -prefix $epi.mocoafni+orig -base 0 -zpad 2 -maxite 60 -x_thresh 0.005 -rot_thresh 0.008 -verbose -dfile $epi.mocoafni.txt -1Dfile $epi.mocoafni.1D -1Dmatrix_save $epi.mocoafni.aff12.1D -maxdisp1D $epi.mocoafni.maxdisp.1D -heptic $epi+orig" >> slomoco_history.txt
          3dvolreg -prefix $epi.mocoafni+orig -base 0 -zpad 2 -maxite 60 -x_thresh 0.005 -rot_thresh 0.008 -verbose -dfile $epi.mocoafni.txt -1Dfile $epi.mocoafni.1D -1Dmatrix_save $epi.mocoafni.aff12.1D -maxdisp1D $epi.mocoafni.maxdisp.1D -heptic $epi+orig
  fi
fi

echo "cat_matvec $epi.mocoafni.aff12.1D -I > $epi.mocoafni.inv.aff12.1D"
echo "cat_matvec $epi.mocoafni.aff12.1D -I > $epi.mocoafni.inv.aff12.1D" >> slomoco_history.txt
      cat_matvec $epi.mocoafni.aff12.1D -I > $epi.mocoafni.inv.aff12.1D

echo "cp $epi.mocoafni.txt mocoafni.txt"
echo "cp $epi.mocoafni.txt mocoafni.txt" >> slomoco_history.txt
      cp $epi.mocoafni.txt mocoafni.txt

if [ "$AFNI_COMPRESSOR" = "GZIP" ]; then
  temp_AFNI_COMPRESSOR=$AFNI_COMPRESSOR
  export AFNI_COMPRESSOR=""
fi

if [ -d tempslmocoxy_afni_$epi ] ; then
  echo tempslmocoxy_afni_$epi directory exists.
  echo tempslmocoxy_afni_$epi directory exists. >> slomoco_history.txt
  echo "Assumed that slicemocoxy has been aleady done" 
  echo "Assumed that slicemocoxy has been aleady done" >> slomoco_history.txt
  echo "If slicemocoxy is not done correctly, you need to delete tempslmocoxy_afni_$epi directory and re-run it"
  echo "If slicemocoxy is not done correctly, you need to delete tempslmocoxy_afni_$epi directory and re-run it" >> slomoco_history.txt
else
  if [ $inplaneflag -eq 0 ]; then
    echo "$SLCMOCO_DIR/run_correction_vol_slicemocoxy_afni.sh -b $epi -e $epi.brain -p $epi.slicemocoxy_afni"
    echo "$SLCMOCO_DIR/run_correction_vol_slicemocoxy_afni.sh -b $epi -e $epi.brain -p $epi.slicemocoxy_afni" >> slomoco_history.txt
          $SLCMOCO_DIR/run_correction_vol_slicemocoxy_afni.sh -b $epi -e $epi.brain -p $epi.slicemocoxy_afni 
  else
    echo "$SLCMOCO_DIR/run_correction_slicemocoxy_afni.sh -b $epi -p $epi.slicemocoxy_afni"
    echo "$SLCMOCO_DIR/run_correction_slicemocoxy_afni.sh -b $epi -p $epi.slicemocoxy_afni" >> slomoco_history.txt
          $SLCMOCO_DIR/run_correction_slicemocoxy_afni.sh -b $epi -p $epi.slicemocoxy_afni 
  fi
fi

if [ -d tempslmoco_volslc_alg_vol_$epi.slicemocoxy_afni ] ; then
  echo tempslmoco_volslc_alg_vol_$epi.slicemocoxy_afni directory exists.
  echo tempslmoco_volslc_alg_vol_$epi.slicemocoxy_afni directory exists. >> slomoco_history.txt
  echo "Assumed that slicemoco in volume has been aleady done" 
  echo "Assumed that slicemoco in volume has been aleady done" >> slomoco_history.txt
  echo "If slicemoco in volume is not done correctly, you need to delete tempslmoco_volslc_alg_vol_$epi.slicemocoxy_afni and re-run it"
  echo "If slicemoco in volume is not done correctly, you need to delete tempslmoco_volslc_alg_vol_$epi.slicemocoxy_afni and re-run it" >> slomoco_history.txt
else
  echo "$SLCMOCO_DIR/run_slicemoco_inside_fixed_vol.sh -b $epi.slicemocoxy_afni" 
  echo "$SLCMOCO_DIR/run_slicemoco_inside_fixed_vol.sh -b $epi.slicemocoxy_afni" >> slomoco_history.txt
        $SLCMOCO_DIR/run_slicemoco_inside_fixed_vol.sh -b $epi.slicemocoxy_afni
fi

# always copy input file into PESTICA subdirectory in AFNI format
echo  3dDeconvolve -polort 1 -input $epi.slicemocoxy_afni+orig -x1D_stop -x1D $epi.slicemocoxy_afni.polort.xmat.1D -overwrite
echo "3dDeconvolve -polort 1 -input $epi.slicemocoxy_afni+orig -x1D_stop -x1D $epi.slicemocoxy_afni.polort.xmat.1D -overwrite" >> slomoco_history.txt
      3dDeconvolve -polort 1 -input $epi.slicemocoxy_afni+orig -x1D_stop -x1D $epi.slicemocoxy_afni.polort.xmat.1D -overwrite
      1dcat $epi.slicemocoxy_afni.polort.xmat.1D > rm.$epi.slicemocoxy_afni.polort.xmat.1D 
echo "1dcat $epi.slicemocoxy_afni.polort.xmat.1D > rm.$epi.slicemocoxy_afni.polort.xmat.1D" >> slomoco_history.txt
      1dcat $epi.slicemocoxy_afni.polort.xmat.1D > rm.$epi.slicemocoxy_afni.polort.xmat.1D 

if [ "$temp_AFNI_COMPRESSOR" = "GZIP" ]; then
  export AFNI_COMPRESSOR="GZIP"
fi

# prepare volumewise mopa,
1d_tool.py -infile $epi.mocoafni.1D -demean -write $epi.mocoafni.demean.1D -overwrite
 
# slicewise mopa
if [ -d tempvolsli_afni ] ; then
  echo tempvolsli_afni directory exists.
  echo tempvolsli_afni directory exists. >> slomoco_history.txt
  echo "Assumed that vol+slicemoco has been aleady done" 
  echo "Assumed that vol+slicemoco has been aleady done" >> slomoco_history.txt
  echo "If vol+slicemoco is not done correctly, you need to delete tempvolsli_afni and re-run it"
  echo "If vol+slicemoco is not done correctly, you need to delete tempvolsli_afni and re-run it" >> slomoco_history.txt
else
  echo "$SLCMOCO_DIR/prep_slicemoco_regressor.sh -b $epi"
  echo "$SLCMOCO_DIR/prep_slicemoco_regressor.sh -b $epi" >> slomoco_history.txt
        $SLCMOCO_DIR/prep_slicemoco_regressor.sh -b $epi
fi  

##### done vol moco parameter###
echo ""
echo "Running Secondorder Motion Correction using SLOMOCO output"
echo ""

if [ $phypmu -eq 1 ]; then
  1dcat ../PHYSIO/RetroTS.PMU.slibase.1D > rm.physio.1D 
elif [ $phypes -eq 1 ] ; then
  1dcat ../PESTICA5/RetroTS.PESTICA5.slibase.1D > rm.physio.1D
else
  rm -f rm.physio.1D 
fi

  echo "matlab $MATLABLINE addpath $MATLAB_AFNI_DIR; addpath $MATLAB_PESTICA_DIR; addpath $MATLAB_SLOMOCO_DIR; gen_regout('$epi.slicemocoxy_afni+orig','$epi_mask+orig','physio','rm.physio.1D','physio'polort','rm.$epi.slicemocoxy_afni.polort.xmat.1D','volreg','$epi.mocoafni.1D','slireg','$epi.slicemopa.1D','voxreg','$epi.sli.pvreg+orig','out','$slomocoout');"
  echo "matlab $MATLABLINE addpath $MATLAB_AFNI_DIR; addpath $MATLAB_PESTICA_DIR; addpath $MATLAB_SLOMOCO_DIR; gen_regout('$epi.slicemocoxy_afni+orig','$epi_mask+orig','physio','rm.physio.1D','polort','rm.$epi.slicemocoxy_afni.polort.xmat.1D','volreg','$epi.mocoafni.1D','slireg','$epi.slicemopa.1D','voxreg','$epi.sli.pvreg+orig','out','$slomocoout'); exit;" >> slomoco_history.txt
  matlab $MATLABLINE <<<"addpath $MATLAB_AFNI_DIR; addpath $MATLAB_PESTICA_DIR; addpath $MATLAB_SLOMOCO_DIR; gen_regout('$epi.slicemocoxy_afni+orig','$epi_mask+orig','physio','rm.physio.1D','polort','rm.$epi.slicemocoxy_afni.polort.xmat.1D','volreg','$epi.mocoafni.1D','slireg','$epi.slicemopa.1D','voxreg','$epi.sli.pvreg+orig','out','$slomocoout'); exit;"

# run QA
echo "matlab $MATLABLINE addpath $MATLAB_PESTICA_DIR; addpath $MATLAB_AFNI_DIR; addpath $MATLAB_SLOMOCO_DIR; qa_slomoco_new('$epi.slicemocoxy_afni+orig','$epi.brain+orig','$epi.mocoafni.1D','$epi.slicemopa.1D'); exit;"
echo "matlab $MATLABLINE addpath $MATLAB_PESTICA_DIR; addpath $MATLAB_AFNI_DIR; addpath $MATLAB_SLOMOCO_DIR; qa_slomoco_new('$epi.slicemocoxy_afni+orig','$epi.brain+orig','$epi.mocoafni.1D','$epi.slicemopa.1D'); exit;" >> slomoco_history.txt
  matlab $MATLABLINE <<<"addpath $MATLAB_PESTICA_DIR; addpath $MATLAB_AFNI_DIR; addpath $MATLAB_SLOMOCO_DIR; qa_slomoco_new('$epi.slicemocoxy_afni+orig','$epi.brain+orig','$epi.mocoafni.1D','$epi.slicemopa.1D'); exit;"

if [ "$AFNI_COMPRESSOR" = "GZIP" ]; then
  echo gzip -f $epi.slicemocoxy_afni+orig.BRIK
  echo gzip -f $epi.slicemocoxy_afni+orig.BRIK >> slomoco_history.txt
       gzip -f $epi.slicemocoxy_afni+orig.BRIK
  echo gzip -f $epi.vol.pvreg+orig.BRIK
  echo gzip -f $epi.vol.pvreg+orig.BRIK >> slomoco_history.txt
       gzip -f $epi.vol.pvreg+orig.BRIK
  echo gzip -f $epi.sli.pvreg+orig.BRIK
  echo gzip -f $epi.sli.pvreg+orig.BRIK >> slomoco_history.txt
       gzip -f $epi.sli.pvreg+orig.BRIK
  echo gzip -f $slomocoout+orig.BRIK
  echo gzip -f $slomocoout+orig.BRIK >> slomoco_history.txt
       gzip -f $slomocoout+orig.BRIK       
fi

# change attributes to match original data
taxis_nums=`3dAttribute TAXIS_NUMS $epi+orig`
taxis_floats=`3dAttribute TAXIS_FLOATS $epi+orig`
taxis_offset=`cat tshiftfile.1D`

#change TR back to input dataset TR
#3drefit -TR $tr $epi+orig $epi.slicemocoxy_afni.zalg_moco2+orig
#copy over and save t-axis nums into new image registered dataset
echo 3drefit -saveatr -atrcopy $epi+orig TAXIS_NUMS $slomocoout+orig >> slomoco_history.txt
     3drefit -saveatr -atrcopy $epi+orig TAXIS_NUMS $slomocoout+orig > /dev/null 2>&1
#copy over and save t-axis floats into new image
echo 3drefit -saveatr -atrcopy $epi+orig TAXIS_FLOATS $slomocoout+orig  >> slomoco_history.txt
     3drefit -saveatr -atrcopy $epi+orig TAXIS_FLOATS $slomocoout+orig > /dev/null 2>&1
echo 3drefit -Tslices `cat tshiftfile.1D`  $slomocoout+orig  >> slomoco_history.txt 
     3drefit -Tslices `cat tshiftfile.1D`  $slomocoout+orig > /dev/null 2>&1

rm $epi+orig.BRIK* $epi+orig.HEAD rm.*.1D

if [ $deletemeflag -eq 1 ]; then
  rm -f $epi.mocoafni+orig.* $epi.slicemocoxy_afni+orig.* $epi.sli.pvreg+orig.* $epi.vol.pvreg+orig.* 
fi
echo "End of SLOMOCO script" >> slomoco_history.txt
echo "`date`" >> slomoco_history.txt
echo "" >> slomoco_history.txt
