#!/bin/tcsh

set version   = "0.0";  set rev_dat   = "Sep 20, 2023"
# + tcsh version of Wanyong Shin's 'run_correction_vol_slicemocoxy_afni.sh'
#
# ----------------------------------------------------------------

set this_prog = "adj_vol_slicemoco"
#set tpname    = "${this_prog:gas///}"
set here      = $PWD

# ----------------------- set defaults --------------------------

set prefix  = ""

set odir    = $here
set opref   = ""

set wdir    = ""

# --------------------- inputs --------------------

set epi      = ""   # base 3D+time EPI dataset to use to perform corrections
set unsatepi = ""   # unsaturated EPI image, usually Scout_gdc.nii.gz
set epi_mask = ""   # (opt) mask dset name
set maskflag = 0    # no mask, by default

set moco_meth   = ""  # req, one of: A, W
set file_tshift = ""  # req, *.1D file

set vr_base     = ""  # opt, for setting vr_idx
set vr_idx      = 0   # opt, but sh/could come from MIN_OUTLIER in upper scr
set vr_mat      = ""  # req, need matrix from full volume volreg

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

    else if ( "$argv[$ac]" == "-dset_base" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_mask" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_mask = "$argv[$ac]"
        set maskflag = 1

    else if ( "$argv[$ac]" == "-moco_meth" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set moco_meth = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-volreg_base" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set vr_base = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-volreg_mat" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set vr_mat = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-file_tshift" ) then
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

    # copy to wdir
    3dcalc \
        -a "${epi}" \
        -expr 'a'   \
        -prefix "${owdir}/base_00"
endif

# a mask is required here.
if ( "${epi_mask}" == "" ) then
    echo "** ERROR: must input a mask with '-mask_dset ..'"
    goto BAD_EXIT
endif


# ---- check other expected dsets; make sure they are OK and grid matches

echo "++ Work on other input datasets"

# these lists must have same length: input filenames and wdir
# filenames, respectively
set all_dset = ( "${epi_mask}" )
set all_wlab = ( mask.nii.gz )

if ( ${#all_dset} != ${#all_wlab} ) then
    echo "** ERROR in script: all_set and all_wlab must have same len"
    goto BAD_EXIT
endif

# finally go through list and verify+copy any that are present
foreach ii ( `seq 1 1 ${#all_dset}` )
    # must keep :q here, to keep quotes, in case fname is empty
    set dset = "${all_dset[$ii]:q}"
    set wlab = "${all_wlab[$ii]:q}"
    if ( "${dset}" != "" ) then
        # verify dset is OK to read
        3dinfo "${dset}"  >& /dev/null
        if ( ${status} ) then
            echo "** ERROR: cannot read/open dset: ${dset}"
            goto BAD_EXIT
        endif

        # must have same grid as input EPI (NB: this command outputs 2
        # numbers, which should both be identical)
        set same_grid = `3dinfo -same_grid "${epi}" "${dset}"`
        if ( "${same_grid[1]}" != "1" ) then
            echo "** ERROR: grid mismatch between input EPI (${epi})"
            echo "   and: ${dset}."
            echo "   The output of '3dinfo -same_all_grid ..' for these is:"
            3dinfo -same_all_grid "${epi}" "${dset}"
            goto BAD_EXIT
        endif

        # at this point, copy to wdir
        3dcalc                                \
            -a "${dset}"                      \
            -expr 'a'                         \
            -prefix "${owdir}/${wlab}" 
    endif
end

# ----- moco method has allowed value

# value can only be one of a short list
if ( ${moco_meth} != "A" && \
     ${moco_meth} != "W" ) then
    echo "** ERROR: bad moco method selected; must be one of: A, W."
    echo "   User provided: '${moco_meth}'"
    goto BAD_EXIT
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

# ----- volreg base

# at present, there is no MIN_OUTLIER at this level; assume upper
# script did so, if desired.
if ( 1 ) then
    # not be choice, but hope user entered an int
    set max_idx = `3dinfo -nvi "${epi}"`
    
    if ( `echo "${vr_base} > ${max_idx}" | bc` || \
         `echo "${vr_base} < 0" | bc` ) then
        echo "** ERROR: allowed volreg_base range is : [0, ${max_idx}]}"
        echo "   but the user's value is outside this: ${vr_base}"
        goto BAD_EXIT
    endif

    # just use that number
    set vr_idx = "${vr_base}"
endif

# ----- check volreg_mat was entered

if ( "${vr_mat}" == "" ) then
    echo "** ERROR: Must use '-volreg_mat ..' to input a volreg matrix"
    goto BAD_EXIT
else 
    if ( ! -e "${vr_mat}" ) then
        echo "** ERROR: volreg_mat does not exist: ${vr_mat}"
        goto BAD_EXIT
    endif

    # copy to wdir
    \cp "${vr_mat}" "${owdir}/volreg.aff12.1D"
    # ... along with inverse
    cat_matvec "${vr_mat}" -I > "${owdir}/volreg_INV.aff12.1D"

endif


# =======================================================================
# =========================== ** Main work ** ===========================

cat <<EOF

++ Start main ${this_prog} work

EOF

# move to wdir to do work
cd "${owdir}"

# ----- get orient and parfix info

adjunct_slomoco_get_orient.tcsh  base_00+orig.HEAD  text_parfix.txt

if ( $status ) then
    echo "** ERROR: could get dset orient"
    goto BAD_EXIT
endif

# ----- define variables

set dims = `3dAttribute DATASET_DIMENSIONS base_00+orig.HEAD`
set tdim = `3dnvals base_00+orig.HEAD`
set zdim = ${dims[2]}

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
@   tcount  = ${tdim} - 1
@   zcount  = ${zmbdim} - 1
@   kcount  = ${zdim} - 1
@   MBcount = ${SMSfactor} - 1    

# ----- synthesize static image

# one-step method to get constant 3D+t dataset, matching [vr_idx] vol
3dcalc                                       \
    -a      base_00+orig.HEAD                \
    -b      base_00+orig.HEAD"[${vr_idx}]"   \
    -expr   'b'                              \
    -prefix base_03_static

# ----- inject volume motion (and inv vol mot) on static dsets

# [PT] why cubic here, and not wsinc5?
3dAllineate \
    -prefix         base_04_static_volmotinj \
    -1Dmatrix_apply volreg_inv.aff12.1D      \
    -source         base_03_static+orig.HEAD \
    -final          cubic \
    >& /dev/null

3dAllineate \
    -prefix         base_05_vol_pvreg \
    -1Dmatrix_apply volreg.aff12.1D \
    -source         base_04_static_volmotinj+orig.HEAD \
    -final          cubic \
    >& /dev/null




# **** ADD MORE PARTS



# ---------------------------------------------------------------------

# move out of wdir to the odir
cd ..
set whereout = $PWD

if ( $DO_CLEAN == 1 ) then
    echo ""
    echo "+* Removing temporary axialization working dir: '$wdir'"
    echo ""

    # ***** clean

else
    echo ""
    echo "++ NOT removing temporary axialization working dir: '$wdir'"
    echo ""
endif

echo ""
echo "++ DONE.  View the finished, axialized product:"
echo "     ****"
echo ""




goto GOOD_EXIT

# ========================================================================
# ========================================================================

SHOW_HELP:
cat << EOF
-------------------------------------------------------------------------

SLOMOCO: slicewise motion correction software (required PESTICA
library package)

Update history
slomoco v5.5
distributed separately from PESTICA

***should not be needed*** compatibility issue with new version of
AFNI commands, e.g. 3dWarpDrive SLOMOCO does not work with the latest
version of AFNI 3dWarDrive command <<AFNI_SLOMOCO_DIR>> should be
defined in setup_slomoco.sh depending on which OS system you are
using, e.g. linux or macOS The working version of LINUX AFNI commands
are stored in <<AFNI_SLOMOCO_DIR>> However, we haven't found working
version of 3dWarpDrive for Mac.
In case that you use MAC, you have two options.
1) find the working version of 3dWarpDrive and compile/use it
2) Use 3dAllineate instead of 3dWarpDrive. To do it, you should set 
   <<AFNI_SLOMOCO>>=A
in setup_slomoco.sh. However, we found the different final result when
using 3dAllineate based on 3dWarpDrive. We are investigating, but
yours is also welcome.

Check "readme.txt" file in <<AFNI_PESTIAC_DIR>>
Feel free to add the working version of commands if necesary.
debugging a few

update from v5.2 to v5.3
It was reported that accidental slow trending was added after SLOMOCO
output.  If you runs any detrending or temporal filtering,
e.g. <0.01Hz, the previous version of output should generate the same
result from v5.3

Update from v5.x to v5.5
==============================================================================
DO NOT use any motion corrected data as an input in slicemoco_newalgorithm.sh.
==============================================================================

IF your data is acquired using Siemens ep2d_pace (retrospective motion 
  correction)
  The previous version of SLOMOCO (v5.4) should be used.
  ep2d_PACE data already includes 3d volume registration by refining the 
  relative cordinate at each volume. 
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
Simple method to remove 1st 4: 3dcalc -a "<epi_file>+orig[4..\$]" -expr a -prefix <epi_file>.steadystate

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
