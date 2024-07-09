#!/bin/tcsh

set version   = "0.0";  set rev_dat   = "Dec 09, 2023"
# + tcsh version of Wanyong Shin's 'run_slicemoco_inside_fixed_vol.sh'
#
set version   = "0.1";  set rev_dat   = "Jul 09, 2024"
# + use nifti for intermed files, simpler scripting (stable to gzip BRIK)
#
# ----------------------------------------------------------------

set this_prog_full = "adjunct_slomoco_inside_fixed_vol.tcsh"
set this_prog = "adj_inside_fixed"
#set tpname    = "${this_prog:gas///}"
set here      = $PWD
  
# ----------------------- set defaults --------------------------

set prefix  = ""

set odir    = $here
set opref   = ""

set wdir    = ""

# --------------------- inputs --------------------

set epi         = ""   # req, epi_slicemoco_xy
set epi_mask    = ""   # req, mask 3D+time images
set file_tshift = ""   # req, *.1D file

set DO_CLEAN = 0                       # default: keep working dir

set histfile = hist_${this_prog}.txt

# ------------------- process options, a la rr ----------------------

if ( $#argv == 0 ) goto SHOW_HELP

set ac = 1
while ( $ac <= $#argv )
    # terminal options
    if ( ("$argv[$ac]" == "-h" ) || ("$argv[$ac]" == "-help" )) then
        echo why me?
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

    else if ( "$argv[$ac]" == "-tfile" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set file_tshift = "$argv[$ac]"

    # --------- opt

    else if ( "$argv[$ac]" == "-workdir" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set wdir = "$argv[$ac]"

        set tf = `python -c "print('/' in '${wdir}')"`
        if ( "${tf}" == "True" ) then
            echo ""
            echo "** ERROR: '-workdir ..' is a name only, no '/' allowed"
            echo ""
            goto BAD_EXIT
        endif

    else if ( "$argv[$ac]" == "-do_clean" ) then
        set DO_CLEAN     = 1
        set deletemeflag = 1
        
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

# check output directory, use input one if nothing given
if ( ! -e "${odir}" ) then
    echo "++ Making new output directory: $odir"
    \mkdir -p "${odir}"
endif

# make workdir name, if nec
if ( "${wdir}" == "" ) then
    set tmp_code = `3dnewid -fun11`  # should be essentially unique hash
    set wdir     = __workdir_${this_prog}_${tmp_code}
endif

# simplify path to wdir
set owdir = "${odir}/${wdir}"

echo $owdir
# make the working directory
if ( ! -e "${owdir}" ) then
    echo "++ Making working directory: ${owdir}"
    \mkdir -p "${owdir}"
else
    echo "+* WARNING:  Somehow found a premade working directory:"
    echo "      ${owdir}"
endif

# ----- find required dsets, and any properties

echo "++ Work on input datasets"

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

    # copy to wdir
    3dcalc \
        -a "${epi}" \
        -expr 'a'   \
        -prefix "${owdir}/epi_02"
endif

# ----- mask is required input
# new update - 3D+t mask improves the result better, required. (W.S)
if ( "${epi_mask}" == "" ) then
    echo "** ERROR: must input a mask with '-dset_mask ..'"
    goto BAD_EXIT
else
    # verify dset is OK to read
    3dinfo "${epi_mask}"  >& /dev/null
    if ( ${status} ) then
        echo "** ERROR: cannot read/open dset: ${epi_mask}"
        goto BAD_EXIT
    endif

    # must have +orig space for input EPI
    set av_space = `3dinfo -av_space "${epi_mask}" `
    if ( "${av_space}" != "+orig" ) then
        echo "** ERROR: input EPI must have +orig av_space, not: ${av_space}"
        goto BAD_EXIT
    endif

    # copy to wdir
    3dcalc \
        -a "${epi_mask}" \
        -expr 'a'   \
        -prefix "${owdir}/epi_02_mask"
endif
 
# ----- check tshift file was entered

if ( "${file_tshift}" == "" ) then
    echo "** ERROR: Must use '-file_tshift ..' to input a tshift file"
    goto BAD_EXIT
else 
    if ( ! -e "${file_tshift}" ) then
        echo "** ERROR: file_tshift does not exist: ${file_tshift}"
        goto BAD_EXIT
    endif

    # copy to wdir
    \cp "${file_tshift}" "${owdir}/tshiftfile.1D"

endif

# =======================================================================
# =========================== ** Main work ** ===========================

cat <<EOF

++ Start main ${this_prog} work

EOF

# move to wdir to do work
cd "${owdir}"

# ----- define variables

set dims = `3dAttribute DATASET_DIMENSIONS epi_02+orig.HEAD`
set tdim = `3dnvals epi_02+orig.HEAD`
set zdim = ${dims[3]}                           # tcsh uses 1-based counting


echo "++ Num of z-dir slices : ${zdim}"
echo "   Num of time points  : ${tdim}"

# ----- calculate SMS factor from slice timing

set SLOMOCO_SLICE_TIMING = `cat tshiftfile.1D`
set SMSfactor            = 0

# count the number of zeros in slice timings to get SMS factor
# [PT] *** probably avoid strict equality in this, bc of floating point vals?
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

# ----- define more/useful quantities

# this first quantity apparently should be the integer part of the div
set zmbdim  = `echo "scale=0; ${zdim}/${SMSfactor}" | bc`

# use the mean image over time as the target 
# so all vols should have roughly the same partial voluming/blurring due to coreg
3dTstat -mean  -prefix __temp_mean epi_02+orig  >& /dev/null

# concatenate mean volume to time-series
set t = 0
while ( $t < $tdim ) 
  set tttt   = `printf "%04d" $t`
  3dcalc -a __temp_mean+orig -expr 'a' -prefix __t_"${tttt}"+orig >& /dev/null
  @ t++ 
end
3dTcat -prefix __temp_tseries_mean   __t_????+orig.HEAD >& /dev/null
\rm __t_????+orig.*

# split into time-series of each slice
set z = 0
while ( $z < $zdim ) 
  set zzzz   = `printf "%04d" $z`
  3dZcutup \
    -keep $z $z \
    -prefix __temp_tseries_mean_"${zzzz}".nii \
    __temp_tseries_mean+orig  >& /dev/null
    
  3dZcutup \
    -keep $z $z \
    -prefix __temp_tseries_"${zzzz}".nii \
    epi_02+orig  >& /dev/null
  
  @ z++ 
end


set z = 0
while ( $z < $zmbdim ) 
  set zsimults = ""
  set zzzz  = `printf "%04d" $z`
  set bname = "motion.wholevol_zt.${zzzz}"
  set mb = 0    
  while ($mb < $SMSfactor )
    set k = `echo "${mb} * ${zmbdim} + ${z}" | bc`
    set zsimults = "${zsimults} $k"   # updating+accumulating
    set kkkk   = `printf "%04d" $k`
    
    # first, temporarily move away the simulated tseries z-slice for this slice
    \mv __temp_tseries_mean_"${kkkk}".nii __tmpz_${mb}.nii

    # and move original tseries into simnoise
    \mv __temp_tseries_"${kkkk}".nii __temp_tseries_mean_"${kkkk}".nii
    
    @ mb++
  end
  
  if ( $SMSfactor > 1 ) then
    echo "++ doing slices $zsimults at once"
  else
    echo "++ doing slice $zsimults"
  endif
  
  # pad into volume using the mean image for adjacent slices
  set ntempi = `find . -maxdepth 1 -type f -name "__temp_input*" | wc -l`
  if ( ${ntempi} ) then
    \rm -f __temp_input*
  endif
  3dZcat -prefix __temp_input __temp_tseries_mean_????.nii >& /dev/null

  set ntempo = `find . -maxdepth 1 -type f -name "__temp_output*" | wc -l`
  if ( ${ntempo} ) then
    \rm -f __temp_output*
  endif
  3dvolreg -zpad 2 -maxite 60 -cubic \
           -prefix        __temp_output \
           -base          __temp_mean+orig \
           -1Dmatrix_save $bname.aff12.1D \
           -1Dfile        $bname.1D \
           __temp_input+orig
  
  set mb = 0
  while ($mb < $SMSfactor )
    set k = `echo "${mb} * ${zmbdim} + ${z}" | bc`
    set kkkk   = `printf "%04d" $k`
    # move the mean z-slice for this slice back into place
    \mv __tmpz_${mb}.nii __temp_tseries_mean_"${kkkk}".nii
    @ mb++
  end
  @ z++
end

\rm -f __temp_* epi_02* tshiftfile.1D

# move out of wdir to the odir
cd ..
set whereout = $PWD

if ( $DO_CLEAN == 1 ) then
    #echo "+* Removing temporary working dir: '${wdir}'"
    #\rm -rf "${wdir}"
    echo "** NB: will NOT clean this temporary working dir: '${wdir}'"
else
    echo "++ NOT removing temporary working dir: '${wdir}'"
endif

echo ""
echo "++ DONE.  Finished slicewise out-of-plane motion correction:"
echo "     ${owdir}/${opref}*"
echo ""


goto GOOD_EXIT


# ========================================================================
# ========================================================================

SHOW_HELP:
cat << EOF
-------------------------------------------------------------------------

Note that output is 1D file, not 

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
