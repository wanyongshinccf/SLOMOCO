#!/bin/tcsh

set version   = "0.0";  set rev_dat   = "Sep 20, 2023"
# + tcsh version of Wanyong Shin's SLOMOCO program
#
# ----------------------------------------------------------------

set this_prog = "run_slomoco"
#set tpname    = "${this_prog:gas///}"
set here      = $PWD

# ----------------------- set defaults --------------------------

set prefix  = ""

set odir    = $here
set opref   = ""

set wdir    = ""

# --------------------- slomoco-specific inputs --------------------

# all allowed slice acquisition keywords
set all_sliacq = ( "alt+z" "asc" "des" )

set slomocov   = 5.1                      # ver
#set physiostr  = PHYSIO
#set pesticstr  = PESTICA5
set slomocostr = SLOMOCO$slomocov
set corrstr    = slicemocoxy_afni.slomoco

set moco_meth  = "W"  # 'AFNI_SLOMOCO': W -> 3dWarpDrive; A -> 3dAllineate

set vr_base    = "MIN_OUTLIER" # best def; or could be an int
set vr_idx     = -1            # will get set by vr_base in opt proc

set epi      = ""   # base 3D+time EPI dataset to use to perform corrections
set unsatepi = ""   # unsaturated EPI image, usually Scout_gdc.nii.gz
set epi_mask = ""   # (opt) mask dset name
set maskflag = 0    # no mask, by default
set MBfactor = 1    # MB acceleration factor
set nVolFirstCutOff = 0   # truncate the first few points
set nVolEndCutOff   = 0   # no EPI volumes at the end were truncated as default
set inplaneflag = 0 # flag to use ep2d_pace data
set sliacqorder =  "" # recommend, no default: make user choose"alt+z"

set DO_CLEAN     = 0                       # default: keep working dir
set deletemeflag = 0

set file_tshift      = ""     # file of tshift info
set file_tshift_sec  = ""     # file of tshift info, needs transpose

set phypes   = ""    # input dir of PESTICA regressors
set phypmu   = ""    # input dir of physio/retroicor regressors
set dir_phys = dir_phys   # if used, name of physio dir in wdir
set dir_pest = dir_pest   # if used, name of pestica dir in wdir

set histfile = slomoco_history.txt

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
        set do_echo = "-echo"

    # --------- required

    else if ( "$argv[$ac]" == "-dset_epi" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_unsat_epi" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set unsatepi = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-prefix" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set prefix = "$argv[$ac]"
        set opref  = `basename "$argv[$ac]"`
        set odir   = `dirname  "$argv[$ac]"`

    # --------- opt

    else if ( "$argv[$ac]" == "-file_tshift" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set file_tshift = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-file_tshift_sec" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set file_tshift_sec = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-mb_factor" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set MBfactor = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-cut_first_n" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set nVolFirstCutOff = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-cut_last_n" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set nVolEndCutOff = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_mask" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_mask = "$argv[$ac]"
        set maskflag = 1

    else if ( "$argv[$ac]" == "-phypes" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set phypes = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-phypmu" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set phypmu = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-use_inplane" ) then
        set inplaneflag = 1

    # below, checked that only allowed keyword is used
    else if ( "$argv[$ac]" == "-slice_acq_order" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set sliacqorder = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-moco_meth" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set moco_meth = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-workdir" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set wdir = "$argv[$ac]"

        set tf = `python -c "print('/' in '${wdir}')"`
        if ( "${tf}" == "True" ) then
            echo "** ERROR: '-workdir ..' is a name only, no '/' allowed"
            goto BAD_EXIT
        endif

    # can be int, or MIN_OUTLIER keyword
    else if ( "$argv[$ac]" == "-volreg_base" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set vr_base = "$argv[$ac]"

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
        -prefix "${owdir}/epi_00"
endif

# ---- check dsets that are optional, to verify (if present)

echo "++ Work on optional input datasets"

# these lists must have same length: input filenames and wdir
# filenames, respectively
set all_dset = ( "${unsatepi}" "${epi_mask}" )
set all_wlab = ( unsatepi_00.nii.gz mask.nii.gz )

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

# ----- make automask, if one is not provided

if ( "${epi_mask}" == "" ) then
    echo "++ No mask provided, will make one" |& tee ${histfile}
    # remove skull (PT: could use 3dAutomask)
    3dSkullStrip \
        -input "${epi}" \
        -prefix "${owdir}/___tmp_mask0.nii.gz"

    # binarize
    3dcalc  \
        -a "${owdir}/___tmp_mask0.nii.gz" \
        -expr 'step(a)' \
        -prefix "${owdir}/___tmp_mask1.nii.gz" \
        -datum byte -nscale

    # inflate mask; name must match wlab name for user mask, above
    3dcalc \
        -a "${owdir}/___tmp_mask1.nii.gz"  \
        -b a+i -c a-i -d a+j -e a-j -f a+k -g a-k \
        -expr 'amongst(1,a,b,c,d,e,f,g)' \
        -prefix "${owdir}/mask.nii.gz"

    # save name to apply
    set epi_mask = "${owdir}/mask.nii.gz"
    # clean a bit
    \rm "${owdir}/___tmp*nii.gz"
endif

# ---- apply mask (from either user or automask)

echo "++ Apply mask"

3dcalc                 \
    -a "${epi_mask}"   \
    -b "${epi}"        \
    -expr "step(a)*b"  \
    -prefix "${owdir}/epi_00_mskd"

# ----- check about physio/pestica regressors, cp to wdir if present

echo "++ Work on physio/pestica regressors, if input"

if ( "${phypmu}" != "" && "${phypes}" != "" ) then
    echo "** ERROR: cannot have both -phypes and -phypmu"
    goto BAD_EXIT

else if ( "${phypmu}" != "" ) then
    if ( ! -e "${phypmu}" ) then
        echo "** ERROR: entered phypmu dir does not exist: ${phypmu}"
        goto BAD_EXIT
    endif
    # cp to wdir, if it does exist
    \cp -rp "${phypmu}" "${owdir}/${dir_phys}"

cat <<EOF >> ${histfile}
++ Second order SLOMOCO will be conducted with RETROICOR physio
   regressors in ${dir_phys}
EOF
else if ( "${phypes}" != "" ) then
    if ( ! -e "${phypes}" ) then
        echo "** ERROR: entered phypes dir does not exist: ${phypes}"
        goto BAD_EXIT
    endif
    # cp to wdir, if it does exist
    \cp -rp "${phypes}" "${owdir}/${dir_pest}"

cat <<EOF >> ${histfile}
++ Second order SLOMOCO will be conducted with PESTICA physio 
   regressors in ${dir_pest}
EOF
else
cat <<EOF >> ${histfile}
++ Second order SLOMOCO will be conducted *without* physio 
   regressors
EOF
endif

# ----- check for slice timing (tshift) file

echo "++ Work on tshift information"

if ( "${file_tshift}" != "" && "${file_tshift_sec}" != "" ) then
    # cannot have both file inputs
    echo "** ERROR: cannot use both '-file_tshift' and '-file_tshift_sec'"
    goto BAD_EXIT

else if ( "${file_tshift}" != "" ) then
    if ( ! -e "${file_tshift}" ) then
        echo "** ERROR: file_tshift does not exist: ${file_tshift}"
        goto BAD_EXIT
    endif

    # copy to wdir
    \cp "${file_tshift}" "${owdir}/tshiftfile.1D"

else if ( "${file_tshift_sec}" != "" ) then
    if ( ! -e "${file_tshift_sec}" ) then
        echo "** ERROR: file_tshift_sec does not exist: ${file_tshift_sec}"
        goto BAD_EXIT
    endif

    # copy to wdir, with transpose
    1dtranspose "${file_tshift_sec}" "${owdir}/tshiftfile.1D"
else
    echo "++ No tshift file from cmd line, will try to get from elsewhere." 

    # try getting from other dirs
    if ( "${phypmu}" != "" ) then
        \cp "${owdir}/${dir_phys}/tshiftfile.1D" "${owdir}/tshiftfile.1D"
        if ( $status ) then
            goto BAD_EXIT
        endif
    else if ( "${phypes}" != "" ) then
        \cp "${owdir}/${dir_pest}/tshiftfile.1D" "${owdir}/tshiftfile.1D"
        if ( $status ) then
            goto BAD_EXIT
        endif
    else
        echo "++ Note that new PESTICA needs MB factor as an input"

        # try to calc from MB factor
        if ( "${MBfactor}" == "1" ) then
            echo "++ Alternative ascending acquisition order of single band"
            echo "   EPI is assumed."
        else if ( `echo "${MBfactor} > 1" | bc` ) then
            echo "++ Alternative ascending acquisition order of multi band"
            echo "   EPI is assumed."
        else
            echo "** ERROR: MB factor not a number (?): ${MBfactor}"
            goto BAD_EXIT
        endif

        echo "+++++ PT +++++"
        echo "***** NEED TO ADD CALC HERE *********" 

    endif

endif

# ----- moco method has allowed value

# value can only be one of a short list
if ( ${moco_meth} != "A" && \
     ${moco_meth} != "W" ) then
    echo "** ERROR: bad moco method selected; must be one of: A, W."
    echo "   User provided: '${moco_meth}'"
    goto BAD_EXIT
endif

# ----- volreg base: MIN_OUTLIER

if ( "${vr_base}" == "MIN_OUTLIER" ) then
    # count outliers, as afni_proc.py would
    3dToutcount                                           \
        -mask ${owdir}/mask.nii.gz                        \
        -fraction -polort 3 -legendre                     \
        "${epi}"                                          \
        > "${owdir}/outcount_rall.1D"

    # get TR index for minimum outlier volume
    set vr_idx = `3dTstat -argmin -prefix - "${owdir}"/outcount_rall.1D\'`
    echo "++ MIN_OUTLIER vr_idx : $vr_idx" \
        | tee "${owdir}/out.min_outlier.txt"

else
    # not be choice, but hope user entered an int
    set max_idx = `3dinfo -nvi "${epi}"`
    
    if ( `echo "${vr_base} > ${max_idx}" | bc` || \
         `echo "${vr_base} < 0" | bc` ) then
        echo "** ERROR: allowed volreg_base range is : [0, ${max_idx}]"
        echo "   but the user's value is outside this: ${vr_base}"
        echo "   Consider using (default, and keyword opt): MIN_OUTLIER"
        goto BAD_EXIT
    endif

    # just use that number
    set vr_idx = "${vr_base}"
endif


# =======================================================================
# =========================== ** Main work ** ===========================

cat <<EOF

++ Start main SLOMOCO work

EOF

# move to wdir to do work
cd "${owdir}"

# ---- volumetric motion correction ("mocoafni" in original code)

# PT: what about using MIN_OUTLIER as reference volume here? would be better***

# calc 6 DF (rigid) alignment pars
3dvolreg                                                                     \
    -verbose                                                                 \
    -prefix         epi_01_volreg+orig                                       \
    -dfile          epi_01_volreg.txt                                        \
    -1Dfile         epi_01_volreg.1D                                         \
    -1Dmatrix_save  epi_01_volreg.aff12.1D                                   \
    -maxdisp1D      epi_01_volreg.maxdisp.1D                                 \
    -base           "${vr_idx}"                                              \
    -zpad           2                                                        \
    -maxite         60                                                       \
    -x_thresh       0.005                                                    \
    -rot_thresh     0.008                                                    \
    -heptic                                                                  \
    epi_00+orig.HEAD

# calc inverse alignment pars
cat_matvec epi_01_volreg.aff12.1D -I > epi_01_volreg_INV.aff12.1D

# ----- slicewise moco in xy plane

if ( "${inplaneflag}" == "0" ) then
    # script with 'vol' for inplane motion correction

    echo "++ Run: adjunct_slomoco_vol_slicemoco_xy.tcsh"
    adjunct_slomoco_vol_slicemoco_xy.tcsh  ${do_echo}                       \
        -dset_base   epi_00+orig.HEAD                                       \
        -dset_mask   mask.nii.gz                                            \
        -moco_meth   ${moco_meth}                                           \
        -volreg_base ${vr_idx}                                              \
        -volreg_mat  epi_01_volreg.aff12.1D                                 \
        -file_tshift tshiftfile.1D                                          \
        -prefix      epi_02_slicemoco_xy

    if ( $status ) then
        goto BAD_EXIT
    endif
endif


















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
