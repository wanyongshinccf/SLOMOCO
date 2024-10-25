#!/bin/tcsh

#set version   = "0.0";  set rev_dat   = "Sep 20, 2023"
# + tcsh version of gen_regout.m'
#
# ----------------------------------------------------------------

set this_prog_full = "adjunct_slomoco_regreout_nuisance.tcsh"
set this_prog = "adj_regout"
#set tpname    = "${this_prog:gas///}"
set here      = $PWD

# ----------------------- set defaults --------------------------

set prefix  = ""

set odir    = $here
set opref   = ""

set wdir    = ""

# --------------------- inputs --------------------

set epi      = ""   # base 3D+time EPI dataset to use to perform corrections
set epi_mask = ""   # mask 3D+time images
set epi_mean = ""   # mask 3D+time images
set volreg1D = ""
set slireg1D = ""
set voxpvreg = ""
set physiofile = ""
set tfile = ""      

set DO_CLEAN = 0                       # default: keep working dir

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

    # --------- required

    else if ( "$argv[$ac]" == "-dset_epi" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_mask" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_mask = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-volreg" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set volreg1D = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-slireg" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set slireg1D = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-voxreg" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set voxpvreg = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-prefix" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set prefix = "$argv[$ac]"

    # --------- opt
	else if ( "$argv[$ac]" == "-physio" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set physiofile = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_mean" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_mean = "$argv[$ac]"

    
    else if ( "$argv[$ac]" == "-do_clean" ) then
        set DO_CLEAN     = 1
        
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

# ----- find AFNI 

# find AFNI binaries directory
set adir      = ""
which afni >& /dev/null
if ( ${status} ) then
    echo "** ERROR: Cannot find 'afni'"
    goto BAD_EXIT
else
    set aa   = `which afni`
    set adir = $aa:h
endif

# ----- in/output prefix

echo "++ Work on input data"

if ( "${epi}" == "" ) then
    echo "** ERROR: need to provide EPI dataset with '-dset_epi ..'"
    goto BAD_EXIT
endif


echo "++ Work on output naming"

if ( "${prefix}" == "" ) then
    echo "** ERROR: need to provide output name with '-prefix ..'"
    goto BAD_EXIT
endif


# ----- mask is required input
# new update - 3D+t mask improves the result better, required. (W.S)
if ( "${epi_mask}" == "" ) then
    echo "** ERROR: must input a mask with '-dset_mask ..'"
    goto BAD_EXIT
endif


# =======================================================================
# =========================== ** Main work ** ===========================

cat <<EOF

++ Start main ${this_prog} work

EOF


# demean volume motion parameter 
1d_tool.py                  \
    -infile $volreg1D       \
    -demean                 \
    -write mopa6.demean.1D  \
    -overwrite
    
# volmopa includues the linear detrending 
3dDeconvolve                                                            \
 	-input ${epi}                                                       \
 	-mask ${epi_mask}                                                   \
  	-polort 1 															\
  	-num_stimts 6 														\
  	-stim_file 1 mopa6.demean.1D'[0]' -stim_label 1 mopa1 -stim_base 1 	\
  	-stim_file 2 mopa6.demean.1D'[1]' -stim_label 2 mopa2 -stim_base 2 	\
  	-stim_file 3 mopa6.demean.1D'[2]' -stim_label 3 mopa3 -stim_base 3 	\
  	-stim_file 4 mopa6.demean.1D'[3]' -stim_label 4 mopa4 -stim_base 4 	\
  	-stim_file 5 mopa6.demean.1D'[4]' -stim_label 5 mopa5 -stim_base 5 	\
  	-stim_file 6 mopa6.demean.1D'[5]' -stim_label 6 mopa6 -stim_base 6 	\
  	-x1D volmopa.1D                                                     \
  	-x1D_stop                                                           \
  	-overwrite
  
# slicewise regressor includes zero vectors when in/out-of-plane motion
# is not trustable. Since slibase option does not support zero vector,
# zero vector is replaced with one vector.

#[W.S] Paul, please check the python script. Is it the right way to use? 
#[W.S] How can I add "-overwrite" option in patch_zero.py? 
# replace zero vectors with linear one
\rm -f slireg_demean_zp.1D 
python $SLOMOCO_DIR/patch_zeros.py  \
    -infile $slireg1D   \
    -write slireg_zp.1D  
    	  

# combine physio 1D with slireg    
if ( $physiofile == "" ) then
    \rm -f slireg.1D
    cp slireg_zp.1D slireg.1D
else
    \rm -f sllireg.1D
    combine_physio_slimopa.py       \
        -slireg slireg_zp.1D \                    
        -physio $physiofile         \
        -write slireg.1D  
endif


# regress out all nuisances here
3dREMLfit                   \
    -input ${epi}           \
    -mask ${epi_mask}       \
    -matrix volmopa.1D      \
    -slibase_sm slireg.1D   \
    -dsort ${voxpvreg}      \
    -Oerrts errt.slomoco    \
    -GOFORIT                \
    -overwrite              

# calculate the average tissue contrast, if necessary
if ( "${epi_mean}" == "" ) then
    set epi_mean = epi_base_mean+orig
    3dTstat                     \
        -mean                   \
        -prefix epi_base_mean   \
        -overwrite              \
        ${epi}      
        
endif


# put the tissue contrast back to the residual signal  
3dcalc                      \
    -a errt.slomoco+orig    \
    -b ${epi_mean}          \
    -c ${epi_mask}          \
    -expr '(a+b)*step(c)'   \
    -prefix $prefix         \
    -overwrite


if ( $DO_CLEAN == 1 ) then
    echo "+* Removing temporary 1D files "
    \rm -f Decon.REML_cmd   \
           slireg_zp.1D     \
           mopa6.demean.1D  \
           slireg.demean.1D
        # ***** clean

else
    echo "++ NOT removing temporary axialization files"
endif

echo ""
echo "++ DONE.  Finished Nuisance regress-out:"
echo ""


goto GOOD_EXIT

# ========================================================================
# ========================================================================

SHOW_HELP:
cat << EOF
-------------------------------------------------------------------------

This adjuct_regout_nuisance.tcsh script is replaced with gen_regout.m
3dREMLfit runs with volume-/slice-/voxel-wise regressors.
Since slicewise regressor inclues zero vectors at a certain slice where
the measured slice motion is not trustable, the zero vector is replaced
with linear line vector. 3dMREMLfit complains the multiple identical 
vectors in slicewise regressors, which is ignored with "-GOFORIT" option.

EOF

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
