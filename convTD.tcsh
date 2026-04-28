#!/usr/bin/tcsh

# set version   = "0.0";  set rev_dat   = "April 27, 2026"
# + Conversion iTD to TD (old SLOMOCO motion index)
set version   = "1.0";  set rev_dat   = "April 27, 2026"
# + Absolute path is available
#
# ----------------------------------------------------------------

set this_prog_full = "iTD2TD.tcsh"
set this_prog = "iTD2TD"
#set tpname    = "${this_prog:gas///}"
set cdir      = $PWD

# ----------------------- set defaults --------------------------

set volreg1D  = "epi_01_volreg.1D"
set slireg1D  = "rm.slimopa.1D"
set opref   = ""

# --------------------- inputs --------------------

set slomoco_dir     = ""   # SLOMOCO directorys
set slomoco_ver     = ""   # SLOMOCO directorys
set wdir            = ""   # output directory

# ------------------- process options, a la rr ----------------------


if ( $#argv == 0 ) goto SHOW_HELP

set ac = 1
while ( $ac <= $#argv )
    # terminal options
    if ( ("$argv[$ac]" == "-h" ) || ("$argv[$ac]" == "-help" )) then
        goto SHOW_HELP
    endif
    if ( "$argv[$ac]" == "-ver" ) then
        goto SHOW_VERSION
    endif

    if ( "$argv[$ac]" == "-echo" ) then
        set echo
        set do_echo = "-echo"

    # --------- required

    else if ( "$argv[$ac]" == "-dset_epi" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi = "$argv[$ac]"
    
    else if ( "$argv[$ac]" == "-dset_mask" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_mask = "$argv[$ac]"
    
    else if ( "$argv[$ac]" == "-slomoco_dir" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set slomoco_dir = "$argv[$ac]"
        
    # --------- optional    

    else if ( "$argv[$ac]" == "-volreg" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set volreg1D = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-slireg" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set slireg1D = "$argv[$ac]"

    else
        echo ""
        echo "** ERROR: unexpected option #$ac = '$argv[$ac]'"
        echo ""
        goto BAD_EXIT
        
    endif
    @ ac += 1
end

# =======================================================================
# ======================== ** Verify + setup ** =========================

# define SLOMOCO directory
set fullcommand = "$0"
set fullcommandlines = "$argv"
setenv SLOMOCO_DIR         `dirname "${fullcommand}"`
setenv MATLAB_SLOMOCO_DIR  $SLOMOCO_DIR/slomoco_matlab
setenv MATLAB_AFNI_DIR     $SLOMOCO_DIR/afni_matlab
setenv MATLABLINE "-nodesktop -nosplash -r"

# read EPI here, not qa_slomoco
set dims = `3dAttribute DATASET_DIMENSIONS ${epi}`
set tdim = `3dnvals ${epi}`
set zdim = ${dims[3]}                           # tcsh uses 1-based counting
set dx = `3dinfo -di ${epi}`
set dy = `3dinfo -dj ${epi}`
set dz = `3dinfo -dk ${epi}`
set TR = `3dinfo -tr ${epi}`
echo test2
# BRIK file conversion
3dcalc -a ${epi_mask} -expr 'a' -prefix ${slomoco_dir}/mask+orig -overwrite
echo test3
echo $TR $tdim $zdim $dx $dy $dz
cd ${slomoco_dir}
echo test4
# run SLOMOCO_afni_v2.2, original Erik's codes. Validated with Katherine's study, but a bug is found (W.S)
echo matlab $MATLABLINE
matlab $MATLABLINE "addpath $MATLAB_AFNI_DIR; addpath $MATLAB_SLOMOCO_DIR; qa_slomoco_v22($TR, $tdim, $zdim, $dx, $dy, $dz,'$volreg1D','$slireg1D'); exit;"

# run SLOMOCO_afni_v5.4, out-of-plane normalization was set to one. 
matlab $MATLABLINE "addpath $MATLAB_AFNI_DIR; addpath $MATLAB_SLOMOCO_DIR; qa_slomoco_v54($TR, $tdim, $zdim, $dx, $dy, $dz,'$volreg1D','$slireg1D'); exit;"

# run SLOMOCO_afni_v5.50, slicewise motion is fitted with volmot
matlab $MATLABLINE "addpath $MATLAB_AFNI_DIR; addpath $MATLAB_SLOMOCO_DIR; qa_slomoco_v55('mask+orig',$TR, $tdim, $zdim, $dx, $dy, $dz,'$volreg1D','$slireg1D'); exit;"

# run SLOMOCO_afni_v5.51
matlab $MATLABLINE "addpath $MATLAB_AFNI_DIR; addpath $MATLAB_SLOMOCO_DIR; qa_slomoco_v551('mask+orig',$TR, $tdim, $zdim, $dx, $dy, $dz,'$volreg1D','$slireg1D'); exit;"

# run SLOMOCO_afni_v5.52
matlab $MATLABLINE "addpath $MATLAB_AFNI_DIR; addpath $MATLAB_SLOMOCO_DIR; qa_slomoco_v552('mask+orig',$TR, $tdim, $zdim, $dx, $dy, $dz,'$volreg1D','$slireg1D'); exit;"

# run SLOMOCO_20240604, 0605, 0611 : Minor fitting still max iTDz
matlab $MATLABLINE "addpath $MATLAB_AFNI_DIR; addpath $MATLAB_SLOMOCO_DIR; qa_slomoco_tcsh_max('mask+orig',$TR, $tdim, $zdim, $dx, $dy, $dz,'$volreg1D','$slireg1D'); exit;"

# run SLOMOCO_20240611.1: Golayfit considering TR & mean iTD
matlab $MATLABLINE "addpath $MATLAB_AFNI_DIR; addpath $MATLAB_SLOMOCO_DIR; qa_slomoco_tcsh_mean('mask+orig',$TR, $tdim, $zdim, $dx, $dy, $dz,'$volreg1D','$slireg1D'); exit;"

echo "++ Run: calc_iTD.py ++" 
echo "   Calculating intra-volume TD "
python $SLOMOCO_DIR/calc_iTD_max.py \
    -sli  slimot_py_fit.txt    \
    -tdim ${tdim}

rm -f ${slomoco_dir}/mask+orig.*

echo "" 
echo "++ DONE.  View the finished"
echo "" 

goto GOOD_EXIT

# ========================================================================
# ========================================================================

SHOW_HELP:
cat << EOF
-------------------------------------------------------------------------

conversion new iTD(z) to old TD unit

iTD2TD.tcsh [option] 

Required options:
 -dset_epi input        = input data is 4D EPI images. 

Optional:
 -tfile 1Dfile          = 1D file is slice acquisition timing info.
                          For example, 5 slices, 1s of TR, ascending interleaved acquisition
                          [0 0.4 0.8 0.2 0.6]
 

# ----------------------------------------------------------------------

    goto GOOD_EXIT

SHOW_VERSION:
   echo "version  $version (${rev_dat})"
   goto GOOD_EXIT

FAIL_MISSING_ARG:
    echo "** ERROR: Missing an argument after option flag: '$argv[$ac]'"
    goto BAD_EXIT

BAD_EXIT:
    exit 1

GOOD_EXIT:
    exit 0
