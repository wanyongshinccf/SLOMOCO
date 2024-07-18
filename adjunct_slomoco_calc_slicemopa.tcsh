#!/bin/tcsh

set version   = "0.0";  set rev_dat   = "Sep 20, 2023"
# + tcsh version of Wanyong Shin's 'run_correction_vol_slicemocoxy_afni.sh'
#
set version   = "0.1";  set rev_dat   = "Jul 09, 2024"
# + use nifti for intermed files, simpler scripting (stable to gzip BRIK)
# ----------------------------------------------------------------

set this_prog_full = "adjunct_slomoco_calc_slicemopa.tcsh"
set this_prog = "adj_calc_slicemopa"
#set tpname    = "${this_prog:gas///}"
set here      = $PWD

# ----------------------- set defaults --------------------------

set prefix  = ""


# --------------------- inputs --------------------

set epi      = ""   # base 3D+time EPI dataset to use to perform corrections


set DO_CLEAN = 0                       # default: keep working dir

set histfile = hist_${this_prog}.txt

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

    else if ( "$argv[$ac]" == "-tfile" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set file_tshift = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-prefix" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set prefix = "$argv[$ac]"
        set opref  = `basename "$argv[$ac]"`
        set odir   = `dirname  "$argv[$ac]"`

    # --------- opt
    
    else if ( "$argv[$ac]" == "-indir" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set inplane_dir = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-outdir" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set outplane_dir = "$argv[$ac]"
    
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

echo "++ Work on output naming"

if ( "${prefix}" == "" ) then
    echo "** ERROR: need to provide output name with '-prefix ..'"
    goto BAD_EXIT
endif

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

endif

# ---- check other expected dsets; make sure they are OK and grid matches

echo "++ Work on other input datasets"


# ----- check tshift file was entered

if ( "${file_tshift}" == "" ) then
    echo "** ERROR: Must use '-file_tshift ..' to input a tshift file"
    goto BAD_EXIT
else 
    if ( ! -e "${file_tshift}" ) then
        echo "** ERROR: file_tshift does not exist: ${file_tshift}"
        goto BAD_EXIT
    endif
endif


# =======================================================================
# =========================== ** Main work ** ===========================


cat <<EOF

++ Start main ${this_prog} work

EOF


# ----- define variables
set dims = `3dAttribute DATASET_DIMENSIONS ${epi}`
set tdim = `3dnvals ${epi}`
set zdim = ${dims[3]}                           # tcsh uses 1-based counting

echo "++ Num of z-dir slices : ${zdim}"
echo "   Num of time points  : ${tdim}"

# ----- calculate SMS factor from slice timing

set SLOMOCO_SLICE_TIMING = `cat tshiftfile.1D`
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

# ----- define more/useful quantities

# this first quantity apparently should be the integer part of the div
set zmbdim  = `echo "scale=0; ${zdim}/${SMSfactor}" | bc`

# define directory & output
set inplane_str  = $inplane_dir/motion.allineate.slicewise_inplane
set outplane_str = $outplane_dir/motion.wholevol_zt

# note that 3dAllnieate 1dfile output is x-/y-/z-shift and z-/x-/y-rotation, ...
# while 3dvolreg 1dfile ouput is z-/x-/y-rot and z-/x-/y-shift and shift direction is flipped
# move to wdir to do work

# remove the pre-existing slicemopa.1D
if ( -f "${owdir}/rm.slicemopa.1D" ) then  
  \rm -f "${owdir}/rm.slicemopa.1D"
endif

set z = 0
while ( $z < $zmbdim )
  set zzzz = `printf "%04d" $z`
  # z-rot (inplane) 
  1dcat  $inplane_str."${zzzz}".1D'[3]'  > "${owdir}/rm.temp.zrot.1D"
  # x-rot (out-of-plane)  
  1dcat  $outplane_str."${zzzz}".1D'[1]' > "${owdir}/rm.temp.xrot.1D"
  # y-rot (out-of-plane)  
  1dcat  $outplane_str."${zzzz}".1D'[2]' > "${owdir}/rm.temp.yrot.1D"
  # z-shift (out-of-plane) 
  1dcat  $outplane_str."${zzzz}".1D'[3]' > "${owdir}/rm.temp.zshift.1D"
  # x-shift (inplane) 
  1dcat  $inplane_str."${zzzz}".1D'[0]'  > "${owdir}/rm.temp.xshift.1D"
  # y-shift (inplane) 
  1dcat  $inplane_str."${zzzz}".1D'[1]'  > "${owdir}/rm.temp.yshift.1D"

  # flipped for inplane x-/y-shift (check that any exist before removing)
  cd "${owdir}"
  set ntempi = `find . -maxdepth 1 -type f -name "rm.temp.?shift.flipped.1D" | wc -l`
  cd -
  if ( ${ntempi} ) then
    \rm -f "${owdir}"/rm.temp.?shift.flipped.1D  
  endif
  1dmatcalc "&read(${owdir}/rm.temp.xshift.1D) -1.0 * &write(${owdir}/rm.temp.xshift.flipped.1D)" 
  1dmatcalc "&read(${owdir}/rm.temp.yshift.1D) -1.0 * &write(${owdir}/rm.temp.yshift.flipped.1D)" 
  
  1dcat "${owdir}/rm.temp.zrot.1D" \
        "${owdir}/rm.temp.xrot.1D" \
        "${owdir}/rm.temp.yrot.1D" \
        "${owdir}/rm.temp.zshift.1D" \
        "${owdir}/rm.temp.xshift.flipped.1D" \
        "${owdir}/rm.temp.yshift.flipped.1D" \
        > "${owdir}"/motion_inoutofplane_zt."${zzzz}".1D

  1dtranspose "${owdir}"/motion_inoutofplane_zt."${zzzz}".1D \
        > "${owdir}"/rm.motion_inoutofplane_zt."${zzzz}".T.1D
  @ z++
end

# concatenate
cat "${owdir}"/rm.motion_inoutofplane_zt.????.T.1D \
    > "${owdir}/rm.slicemopa.T.1D"

# copy and paste for SMS
set mb = 0
while ( $mb < $SMSfactor ) 
  \cp "${owdir}"/rm.slicemopa.T.1D "${owdir}"/rm.slicemopa.T."${mb}".1D
  @ mb++
end
\rm -f "${owdir}"/rm.slicemopa.T.1D 
  
if ( $SMSfactor >  1 ) then 
  cat "${owdir}"/rm.slicemopa.T.?.1D >> "${owdir}"/rm.slicemopa.T.1D
else
  \cp "${owdir}"/rm.slicemopa.T.0.1D "${owdir}"/rm.slicemopa.T.1D
endif

1dtranspose "${owdir}"/rm.slicemopa.T.1D "${prefix}" -overwrite

# cleaning up
\rm -f "${owdir}"/rm.*.1D

# move out of wdir to the odir
cd ..
set whereout = $PWD

if ( $DO_CLEAN == 1 ) then
    echo "+* Removing temporary axialization working dir: '$wdir'"

    # ***** clean

else
    echo "++ NOT removing temporary axialization working dir: '$wdir'"
endif

echo ""
echo "++ DONE.  Finished generating slice motion 1D file:"
echo "     ${owdir}/${opref}*"
echo ""


goto GOOD_EXIT


# ========================================================================
# ========================================================================

SHOW_HELP:
cat << EOF
-------------------------------------------------------------------------

test test

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

