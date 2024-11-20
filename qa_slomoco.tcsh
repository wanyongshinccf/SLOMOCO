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

set epi_volmoco = ""   # base 3D+time EPI dataset to use to perform corrections
set epi_slomoco = ""   # base 3D+time EPI dataset to use to perform corrections
set epi_mask    = ""   # mask 3D+time images
set jsonfile    = ""       # json file
set tfile       = ""       # tshiftfile (sec)

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

    else if ( "$argv[$ac]" == "-dset_volmoco" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_volmoco = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_slomoco" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_slomoco = "$argv[$ac]"

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
if ( "${epi_volmoco}" == "" ) then
    echo "** ERROR: need to provide EPI dataset with '-dset_volmoco ..'" 
    goto BAD_EXIT
else
    # verify dset is OK to read
    3dinfo "${epi_volmoco}"  >& /dev/null
    if ( ${status} ) then
        echo "** ERROR: cannot read/open dset: ${epi_volmoco}" 
        goto BAD_EXIT
    endif

    # must have +orig space for input EPI
    set av_space = `3dinfo -av_space "${epi_volmoco}" `
    if ( "${av_space}" != "+orig" ) then
        echo "** ERROR: input EPI must have +orig av_space, not: ${av_space}" 
        goto BAD_EXIT
    endif
endif

if ( "${epi_slomoco}" == "" ) then
    echo "** ERROR: need to provide EPI dataset with '-dset_slomoco ..'" 
    goto BAD_EXIT
else
    # verify dset is OK to read
    3dinfo "${epi_slomoco}"  >& /dev/null
    if ( ${status} ) then
        echo "** ERROR: cannot read/open dset: ${epi_slomoco}" 
        goto BAD_EXIT
    endif

    # must have +orig space for input EPI
    set av_space = `3dinfo -av_space "${epi_slomoco}" `
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
# note SLOMOCO assumes the slice is in z direction.
# you need to modify the code wtih sagital/coronal acquisition
set zdim = `3dinfo -nk ${epi_slomoco}`                   
set tdim = `3dinfo -nt ${epi_slomoco}`
set TR   = `3dinfo -tr ${epi_slomoco}`

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
if ( -f inplane/slice_excluded.txt ) then
    echo "++ Too zero-ish slice(s) is(are) excluded."
    set excstr = "-exc inplane/slice_excluded.txt " 
else
    echo "++ Excluded slice(s) is(are) not provided."
    set excstr = ""
endif

echo "++ Combining slimot with volmot "
python $SLOMOCO_DIR/combine_slimot_volmot.py \
    -vol $volreg1D                           \
    -sli $slireg1D                           \
    -acq sliacqorder.1D                      \
    $excstr

# calculate SSD of VOLMOCO
3dTstat                     \
    -mean                   \
    -prefix rm.mean+orig    \
    -overwrite              \
    ${epi_volmoco}

3dcalc                          \
    -a      ${epi_volmoco}      \
    -b      rm.mean+orig        \
    -expr   '(100*(a-b)/b)^2'   \
    -prefix rm.norm2+orig       \
    -overwrite

3dROIstats              \
    -mask ${epi_mask}   \
    -quiet rm.norm2+orig > rm.norm2.1D

1deval -a rm.norm2.1D -expr 'sqrt(a)' > SSD.volmoco.1D

# calculate SSD of full SLOMOCO
3dTstat                  \
    -mean                \
    -prefix rm.mean+orig \
    -overwrite           \
    ${epi_slomoco}

3dcalc                          \
    -a      ${epi_slomoco}      \
    -b      rm.mean+orig        \
    -expr   '(100*(a-b)/b)^2'   \
    -prefix rm.norm2+orig       \
    -overwrite

3dROIstats              \
    -mask ${epi_mask}   \
    -quiet rm.norm2+orig > rm.norm2.1D

1deval -a rm.norm2.1D -expr 'sqrt(a)' > SSD.slomoco.1D

\rm -f rm.*

# calculate FD, output will be FDJ.txt, FDP.txt with a length of total volume - 1
echo "++ Calculating FD "
python $SLOMOCO_DIR/calc_FD.py \
    -vol epi_01_volreg.1D 

# Test purpse. It does not work well. commented out
echo "++ Calculating intra-volume FD "
python $SLOMOCO_DIR/calc_iFD.py \
    -sli  slimot_py_fit.txt    \
    -tdim ${tdim}

echo "++ Calculating intra-volume TD "
python $SLOMOCO_DIR/calc_iTD.py \
    -sli  slimot_py_fit.txt    \
    -tdim ${tdim}

echo "++ Generating QA plots "
python $SLOMOCO_DIR/disp_QAplot.py  \
    -ssdvol SSD.volmoco.1D          \
    -ssdsli SSD.slomoco.1D          \
    -volsli volslimot_py_fit.txt    \
    -sli    slimot_py_fit.txt       \
    -iFDJ   iFDJ_py.txt             \
    -iFDP   iFDP_py.txt             \
    -iTD    iTD_py.txt              \
    -ioFDJ  ioFDP_py.txt            \
    -ioFDP  ioFDP_py.txt            \
    -ioTD   ioTD_py.txt

