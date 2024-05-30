#!/bin/tcsh

set version   = "0.0";  set rev_dat   = "Nov 28, 2023"
# + tcsh version of Wanyong Shin's SLOMOCO program
#
# ----------------------------------------------------------------

# -------------------- set environment vars -----------------------

setenv AFNI_MESSAGE_COLORIZE     NO         # so all text is simple b/w

# ----------------------- set defaults --------------------------

set this_prog = "run_volmoco"
set here      = $PWD

set prefix    = ""
set odir      = $here
set opref     = ""
set wdir      = ""

# --------------------- slomoco-specific inputs --------------------

# all allowed slice acquisition keywords
set slomocov   = 5                      # ver
set moco_meth  = "W"  # 'AFNI_SLOMOCO': W -> 3dWarpDrive; A -> 3dAllineate
set vr_base    = "0" # select either "MIN_OUTLIER" or "MIN_ENORM", or integer
set vr_idx     = -1            # will get set by vr_base in opt proc

set epi      = ""   # base 3D+time EPI dataset to use to perform corrections
set unsatepi = ""   # unsaturated EPI image, usually Scout_gdc.nii.gz
set epi_mask = ""   # (opt) mask dset name
set jsonfile = ""   # json file
set tfile = ""      # tshiftfile (sec)
set physiofile = "" # physio1D file, from RETROICOR or PESTICA
set regflag = "MATLAB" # MATLAB or AFNI
set qaflag = "MATLAB" # MATLAB or AFNI

set DO_CLEAN     = 0                       # default: keep working dir
set deletemeflag = 0

set histfile = slomoco_history.txt

set do_echo  = ""

# test purpose (W.S)
set step1flag = "nskip" # voxelwise PV regressor
set step2flag = "nskip" # inplance moco
set step3flag = "nskip" # outofplane moco
set step4flag = "nskip" # slicewise motion 1D
set step5flag = "nskip" # 2nd order regress-out
set step6flag = "nskip" # qa plot

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

    else if ( "$argv[$ac]" == "-prefix" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set prefix = "$argv[$ac]"
        set opref  = `basename "$argv[$ac]"`
        set odir   = `dirname  "$argv[$ac]"`

    # --------- required either of tfile or json option
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

# define SLOMOCO directory
set fullcommand = "$0"
setenv SLOMOCO_DIR `dirname "${fullcommand}"`
setenv MATLAB_SLOMOCO_DIR $SLOMOCO_DIR/slomoco_matlab
setenv AFNI_SLOMOCO_DIR $SLOMOCO_DIR/afni_linux

echo $fullcommand
cat <<EOF >> ${histfile}
$fullcommand
EOF

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

echo $vr_idx volume will be the reference volume

# gen mask 
3dcalc -a "${epi}[$vr_idx]" -expr 'step(a-200)' -prefix "${owdir}"/epi_base_mask

cat <<EOF >> ${histfile}
++ epi_base+orig is the reference volume (basline), $vr_idx th volume of input
EOF

# =======================================================================
# =========================== ** Main work ** ===========================

# move to wdir to do work
cd "${owdir}"

# update mask file name
set epi_mask = "epi_base_mask+orig"

# ----- step 1 voxelwise time-series PV regressor
# volreg output is also generated.
if ( $step1flag != 'skip' ) then
    gen_vol_pvreg.tcsh                 \
        -dset_epi  ../"${epi}"        \
        -dset_mask "${epi_mask}"      \
        -vr_idx    "${vr_idx}"         \
        -prefix_pv epi_01_pvreg        \
        -prefix_vr epi_01_volreg       \
        |& tee     log_gen_vol_pvreg.txt
    
    if ( $status ) then
        goto BAD_EXIT
    endif

cat <<EOF >> ${histfile}
++ Voxelwise partial volume motion nuisance regressors is generated.
EOF

endif

# ----- step 2 second order 

1d_tool.py -infile epi_01_volreg.1D -demean -write mopa6.demean.1D
3dDeconvolve -input epi_01_volreg+orig -mask epi_base_mask+orig \
  -polort 1 -num_stimts 6 \
  -stim_file 1 mopa6.demean.1D'[0]' -stim_label 1 mopa1 -stim_base 1 \
  -stim_file 2 mopa6.demean.1D'[1]' -stim_label 2 mopa2 -stim_base 2 \
  -stim_file 3 mopa6.demean.1D'[2]' -stim_label 3 mopa3 -stim_base 3 \
  -stim_file 4 mopa6.demean.1D'[3]' -stim_label 4 mopa4 -stim_base 4 \
  -stim_file 5 mopa6.demean.1D'[4]' -stim_label 5 mopa5 -stim_base 5 \
  -stim_file 6 mopa6.demean.1D'[5]' -stim_label 6 mopa6 -stim_base 6 \
  -x1D mopa6.1D -x1D_stop 
  
3dREMLfit -input epi_01_volreg+orig -mask epi_base_mask+orig \
  -matrix mopa6.1D -dsort epi_01_pvreg+orig -Oerrts errt.mopa6.pvreg    
3dREMLfit -input epi_01_volreg+orig -mask epi_base_mask+orig \
  -matrix mopa6.1D -Oerrts errt.mopa6
  
3dTstat -stdev -prefix errt.std             epi_01_volreg+orig  
3dTstat -stdev -prefix errt.mopa6.std       errt.mopa6+orig
3dTstat -stdev -prefix errt.mopa6.pvreg.std errt.mopa6.pvreg+orig

rm epi_motsim* errt.mopa6.pvreg+orig.* errt.mopa6+orig.*  

# script for inplane motion correction



# move out of wdir to the odir
cd ..
set whereout = $PWD

# copy the final result
cp -f "${owdir}"/"${prefix}"* . # output only

if ( $DO_CLEAN == 1 ) then
    echo "\n+* Removing temporary axialization working dir: '$wdir'\n"

    # ***** clean
    rm -rf "${owdir}"

else
    echo "\n++ NOT removing temporary axialization working dir: '$wdir'\n"
endif

echo ""
echo "++ DONE.  View the finished, axialized product:"
echo "     $whereout"
echo ""

goto GOOD_EXIT

# ========================================================================
# ========================================================================

SHOW_HELP:
cat << EOF
-------------------------------------------------------------------------

SLOMOCO: slicewise motion correction script based on AFNI commands

run_slomoco.tcsh [option] 

Required options:
 -dset_epi input     = input data is non-motion corrected 4D EPI images. 
                       DO NOT apply any motion correction on input data.
                       It is not recommended to apply physiologic noise correction on the input data
                       Physiologoc noise components can be regressed out with -phyio option 
 -tfile 1Dfile       = 1D file is slice acquisition timing info.
                       For example, 5 slices, 1s of TR, ascending interleaved acquisition
                       [0 0.4 0.8 0.2 0.6]
      or 
 -jsonfile jsonfile  = json file from dicom2nii(x) is given
 -prefix output      = output filename
 
Optional:
 -volreg_base refvol = reference volume number, "MIN_ENORM" or "MIN_OUTLIER"
                       "MIN_ENORM" provides the volume number with the minimal summation of absolute volume shift and its derivatives 
                       "MIN_OUTLIER" provides [P.T will add]
                       Defaulty is "0"
 -workdir  directory = intermediate output data will be generated in the defined directory.
 -do_clean           = this option will delete working directory 

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
