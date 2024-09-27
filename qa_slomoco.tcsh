#!/bin/tcsh

#set version   = "0.0";  set rev_dat   = "Sep 25, 2024"
# + tcsh version of QA_slomoco.m 
#

# ----------------------------------------------------------------

set this_prog_full = "qa_slomoco.tcsh"
set this_prog = "qa_slomoco"
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
set jsonfile   = ""       # json file
set tfile      = ""       # tshiftfile (sec)

set DO_CLEAN = 0                       # default: keep working dir

set do_echo  = ""

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

    else if ( "$argv[$ac]" == "-volreg1D" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set volreg1D = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-slireg1D" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set slireg1D = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-tfile" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set tfile = "$argv[$ac]"

    # --------- opt

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


# ----- output prefix/odir/wdir

echo "++ Work on output naming"

# find slice acquisition timing
if ( "${tfile}" == "" ) then
    echo "** ERROR: tshift file does not exist"
    goto BAD_EXIT
endif

# ----- find required dsets, and any properties
if ( "${epi}" == "" ) then
    echo "** ERROR: need to provide EPI dataset with '-dset_epi ..'" 
    goto BAD_EXIT
else
    # verify dset is OK to read
    3dinfo "${epi}"  >& /dev/null
    if ( ${status} ) then
        echo "** ERROR: cannot read/open dset: ${epi}" 
        goto BAD_EXIT
    endif

    # must have +orig space for input EPI
    set av_space = `3dinfo -av_space "${epi}" `
    if ( "${av_space}" != "+orig" ) then
        echo "** ERROR: input EPI must have +orig av_space, not: ${av_space}" 
        goto BAD_EXIT
    endif
endif

if ( "${epi_mask}" == "" ) then
    echo "** ERROR: need to provide mask with '-dset_mask ..'" 
    goto BAD_EXIT
endif

# ----- define variables

set dims = `3dAttribute DATASET_DIMENSIONS ${epi}`
# origentation sagital?
set zdim = ${dims[3]}                          

set tdim = `3dnvals ${epi}`
set Taxis = `3dAttribute TAXIS_FLOATS ${epi}`
set TR = ${Taxis[2]}   

# read slice acquisition timing from tshift file and caculate SMS factor
set SLOMOCO_SLICE_TIMING = `cat $tfile`
set SMSfactor            = 0

# count the number of zeros in slice timings to get SMS factor
foreach tval ( ${SLOMOCO_SLICE_TIMING} )
    if ( `echo "${tval} == 0" | bc` ) then
        @ SMSfactor += 1
    endif
end

if ( "$SMSfactor" == "0" ) then
    echo "** ERROR: slice acquisition timing does not have any zeros"
    goto BAD_EXIT
else if ( "$SMSfactor" == "${zdim}" ) then
    echo "** ERROR: slice acquisition timing was shifted to ALL zeros"
    goto BAD_EXIT
else
    echo "++ Num of zeros in timing file (hence SMS factor): ${SMSfactor}"
endif


# find the acquisition order from slice acquisition timing
setenv AFNI_1D_TIME YES
# for interleaved alt+z 6 slices: sliacqorder.1D = [0 2 4 1 3 5] 
3dTsort -overwrite -ind -prefix sliacqorder.1D $tfile


# combine slimot to volmot
# output is volslimot_py.txt & volslimot_py_fit.txt
python $SLOMOCO_DIR/combine_slimot_volmot.py \
    -vol $volreg1D \
    -sli $slireg1D \
    -acq sliacqorder.1D \
    -exc inplane/slice_excluded.txt

# calculate TDz, DAVAR and FD here
# python $SLOMOCO_DIR/cal_motindex.py \
# -vol epi_01_volreg.1D \
# -volsli volslimot_py.txt



