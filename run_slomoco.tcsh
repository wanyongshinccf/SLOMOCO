#!/bin/tcsh

#set version   = "0.0";  set rev_dat   = "May 30, 2024"
# + tcsh version of Wanyong Shin's SLOMOCO program
#
#set version   = "0.1";  set rev_dat   = "Jul 09, 2024"
# + use nifti for intermed files, simpler scripting (stable to gzip BRIK)
#
#set version   = "0.2";  set rev_dat   = "Jul 18, 2024"
# + formatting/indenting/spacing, and more status-check exits
#
#set version   = "0.3";  set rev_dat   = "Jul 18, 2024"
# + remove Darwin/macOS check; switch to using possible local 3dWarpDrive 
#
#set version   = "0.4";  set rev_dat   = "Sep 23, 2024"
# + check AFNI version (but not failing/stopping yet)
#
#set version   = "0.5";  set rev_dat   = "Sep 23, 2024"
# + add AFNI_IS_OLD env var, to act more strictly on old/modern AFNI ver
#   check
#
# set version   = "0.51";  set rev_dat   = "Sep 23, 2024"
# + add macOS-based check for case of old AFNI
#
# set version   = "0.6";  set rev_dat   = "Sep 27, 2024"
# + add AFNI version of regress-out 
#
# set version   = "0.7";  set rev_dat   = "Oct 27, 2024"
# + add AFNI version of the part of QA (still running matlab) 
# + 3dvolreg output with 6 mopa + PV regressors 
#
# set version  = "0.8";    set rev_dat   = "Dec 18, 2024"
# + debugging a log file issue
set version  = "0.9";    set rev_dat   = "Jan 16, 2025"
# + debugging the conflict of two run_regout_nuisance.tcsh scripts in PESTICA/SLOMOCO

#
# ----------------------------------------------------------------

# -------------------- set environment vars -----------------------

setenv AFNI_MESSAGE_COLORIZE     NO         # so all text is simple b/w
setenv AFNI_IS_OLD               0          # pre-3dWarpDrive update?

# this is the minimal version to use to be able to work with the
# AFNI-distributed 3dWarpDrive; this is the first build after updating
# the internal mask erosion to work work with 2D slices.
set AFNI_MIN_VNUM = "AFNI_24.2.02"

# ----------------------- set defaults --------------------------

set this_prog = "run_slomoco"

set prefix    = ""
set odir      = $PWD
set opref     = ""
set wdir      = ""

# --------------------- slomoco-specific inputs --------------------

# all allowed slice acquisition keywords                    
set moco_meth  = "W"        # 'AFNI_SLOMOCO': W -> 3dWarpDrive; A -> 3dAllineate
set vr_base    = "0"        # select either "MIN_OUTLIER", "MIN_ENORM" or integer
set vr_idx     = -1         # will get set by vr_base in opt proc

set epi        = ""         # base 3D+time EPI dset to use to perform corrections
set epi_mask   = ""         # (opt) mask dset name
set jsonfile   = ""         # json file
set tfile      = ""         # tshiftfile (sec)

set physiofile = ""         # physio1D file, from RETROICOR or PESTICA
set regflag    = "AFNI"     # MATLAB or AFNI
set qaflag     = "AFNI"     # MATLAB or AFNI

set allow_old_afni = 0      # user *should* update code, but can use old

set volregfirst = 0         # Slomoco on each aligned refvol.
set DO_CLEAN    = 0         # default: keep working dir
set histfile    = log_slomoco.txt

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

    else if ( "$argv[$ac]" == "-prefix" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set prefix = "$argv[$ac]"
        set opref  = `basename "$argv[$ac]"`
        set odir   = `dirname  "$argv[$ac]"`
        set odir   = `realpath $odir`

    # --------- required either of tfile or json option
    else if ( "$argv[$ac]" == "-tfile" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set tfile = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-json" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set jsonfile = "$argv[$ac]"

    # --------- opt

    else if ( "$argv[$ac]" == "-dset_mask" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_mask = "$argv[$ac]"
        set maskflag = 1

    else if ( "$argv[$ac]" == "-physio" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set physiofile = "$argv[$ac]"

    # below, checked that only allowed keyword is used
    else if ( "$argv[$ac]" == "-dset_unsat_epi" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set unsatepi = "$argv[$ac]"

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

    else if ( "$argv[$ac]" == "-volregfirst" ) then
        set volregfirst     = 1

    # manage having non-modern AFNI: user must EXPLICITLY set this
    else if ( "$argv[$ac]" == "-allow_old_afni" ) then
        set allow_old_afni  = 1

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
# AFNI version check

# make sure AFNI is not *very, very* old
set vnum   = `afni -vnum`
set vstart = `echo ${vnum} | tr '_' ' ' | awk '{print $1}'`
if ( "${vstart}" != "AFNI" ) then
    echo "** ERROR: AFNI version is too old to even check vnum"
    echo "   Please update AFNI to use this program."
    set aver = `afni -ver`
    echo "   version info: ${aver}"
    goto BAD_EXIT
endif

# check for 'modern' AFNI (compare via Python); note a local env var
# can be reset here
set cstr = "'${vnum}' >= '${AFNI_MIN_VNUM}'"
set cval = `python -c "print(int(${cstr:q}))"`
if ( ${cval} ) then
    echo "++ AFNI version is good for modern SLOMOCO: ${cstr}"
else if ( ${allow_old_afni} ) then
    echo "+* WARN: AFNI version too old for modern SLOMOCO,"
    echo "   based on 'afni -vnum', this is False: ${cstr}."
    echo "   Updating AFNI is recommended, but user says push on 'as is'."
    setenv AFNI_IS_OLD 1
else 
    echo "** ERROR: AFNI version too old for modern SLOMOCO,"
    echo "   based on 'afni -vnum', this is False: ${cstr}."
    echo "   Either update your AFNI version (**strongly recommended**),"
    echo "   or add opt '-allow_old_afni' to use older prog version here."
    goto BAD_EXIT
endif

# the 'OSTYPE == darwin' check is now only necessary for a user with
# old AFNI
if ( ${AFNI_IS_OLD} ) then
    if ( ${?OSTYPE} ) then
        set os = $OSTYPE
        if (( "${os}" == "linux" ) || ( "${os}" == "linux-gnu" )) then
            # LINUX 
	        if ( "${moco_meth}" == "W" ) then
            	echo "+* WARN: 3dWarpDrive command in the package (afni.afni.openmp.v18.3.16) will be used" 
            endif
        else 
	        if ( ${os} == "darwin"  ) then
                if ( "$moco_meth" == "W" ) then
                    echo "** ERROR: SLOMOCO (with old AFNI) is running with -moco_meth W on macOS" 
                    echo "   Either update your AFNI version (**strongly recommended**),"
                    echo "   or add opt '-moco_meth A' and '-volreg_first' "
                    goto BAD_EXIT
		        else
		            echo "** Warning: SLOMOCO (with old AFNI) is running with -moco_meth A on macOS" 
        	        if ( "$volregfirst" == "0" ) then
		                echo "   Update your AFNI version (**strongly recommended**)"
                        echo "   or '-volreg_first' "
                        goto BAD_EXIT
                    endif 
		        endif
	        endif
    	endif
    endif
endif

# =======================================================================
# ======================== ** Verify + setup ** =========================

# define SLOMOCO directory
set fullcommand = "$0"
set fullcommandlines = "$argv"
setenv SLOMOCO_DIR         `dirname "${fullcommand}"`
setenv MATLAB_SLOMOCO_DIR  $SLOMOCO_DIR/slomoco_matlab
setenv AFNI_SLOMOCO_DIR    $SLOMOCO_DIR/afni_linux
setenv MATLAB_AFNI_DIR     $SLOMOCO_DIR/afni_matlab

# initialize a log file
echo ""                             >> $odir/$histfile
echo $fullcommand $fullcommandlines >> $odir/$histfile
date                                >> $odir/$histfile
echo ""                             >> $odir/$histfile

if  ( $volregfirst == "1" ) then
    echo "+* WARNING: You select running SLOMOCO on volume motion corrected images"     |& tee -a $odir/$histfile
    echo "+* SLOMOCO is recommended to be used on non-volume motion corrected images"   |& tee -a $odir/$histfile
    echo "+* You should know what you are doing. I warn you."                           |& tee -a $odir/$histfile
else
    echo "++ MotSim data is used for the reference image of SLOMOCO"                    |& tee -a $odir/$histfile 
    echo "++ SLOMOCO is running on non-volume motion corrected images"                  |& tee -a $odir/$histfile
endif
    
if  ( $moco_meth == "A"  ) then 
    echo "+* WARNING: 3dAllineate is used for slicewise motion correction"              |& tee -a $odir/$histfile
    echo "+* Our empirical result shows 3dWarpDrive performs better than 3dAllineate."  |& tee -a $odir/$histfile
    echo "+* You should know what you are doing. I warn you."                           |& tee -a $odir/$histfile
endif     


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
    echo "** ERROR: need to provide output name with '-prefix ..'"  |& tee -a $odir/$histfile
    goto BAD_EXIT
endif

# check output directory, use input one if nothing given
if ( ! -e "${odir}" ) then
    echo "++ Making new output directory: $odir"                    |& tee -a $odir/$histfile
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
    echo "++ Making working directory: ${owdir}"                    |& tee -a $odir/$histfile
    \mkdir -p "${owdir}"
else
    echo "+* WARNING:  Somehow found a premade working directory:"  |& tee -a $odir/$histfile
    echo "      ${owdir}"
endif

# find slice acquisition timing
if ( "${jsonfile}" == "" && "${tfile}" == "" ) then
    echo "** ERROR: slice acquisition timing info should be given with -json or -tfile option" |& tee -a $odir/$histfile
    goto BAD_EXIT
else
    if ( ! -e "${jsonfile}" && "${jsonfile}" != "" ) then
        echo "** ERROR: Json file does not exist"                   |& tee -a $odir/$histfile
        goto BAD_EXIT
    endif
    if ( ! -e "${tfile}" && "${tfile}" != "" ) then
        echo "** ERROR: tshift file does not exist"                 |& tee -a $odir/$histfile
        goto BAD_EXIT
    endif
endif

# ----- find required dsets, and any properties

if ( "${epi}" == "" ) then
    echo "** ERROR: need to provide EPI dataset with -dset_epi "    |& tee -a $odir/$histfile
    goto BAD_EXIT
else
    # verify dset is OK to read
    3dinfo "${epi}"  >& /dev/null
    if ( ${status} ) then
        echo "** ERROR: cannot read/open dset: ${epi} "             |& tee -a $odir/$histfile
        goto BAD_EXIT
    endif

    # must have +orig space for input EPI
    set av_space = `3dinfo -av_space "${epi}" `
    if ( "${av_space}" != "+orig" ) then
        echo "** ERROR: input EPI must have +orig av_space, not: ${av_space}" |& tee -a $odir/$histfile
        goto BAD_EXIT
    endif

    # copy to wdir
    3dcalc                        \
        -a "${epi}"               \
        -expr 'a'                 \
        -prefix "${owdir}/epi_00" \
        -overwrite
endif

# ----- volreg base: MIN_OUTLIER

if ( "${vr_base}" == "MIN_OUTLIER" ) then
    # count outliers, as afni_proc.py would
    3dToutcount                                           \
        -automask                                         \
        -fraction -polort 3 -legendre                     \
        "${epi}"                                          \
        > "${owdir}/outcount_rall.1D"

    # get TR index for minimum outlier volume
    set vr_idx = `3dTstat -argmin -prefix - "${owdir}"/outcount_rall.1D\'`
    echo "++ MIN_OUTLIER vr_idx : $vr_idx"              | tee "${owdir}/out.min_outlier.txt"

else if ( "${vr_base}" == "MIN_ENORM" ) then

    3dvolreg                                    \
        -1Dfile "${owdir}"/___temp_volreg.1D    \
        -prefix "${owdir}"/___temp_volreg.nii   \
        -overwrite                              \
        "${epi}"

    1d_tool.py -infile "${owdir}"/___temp_volreg.1D          \
               -derivative                                   \
               -collapse_cols euclidean_norm                 \
               -write "${owdir}"/enorm_deriv.1D              \
               -overwrite
    1d_tool.py -infile "${owdir}"/___temp_volreg.1D          \
               -collapse_cols euclidean_norm                 \
               -write "${owdir}"/enorm.1D                    \
               -overwrite
    1d_tool.py -infile "${owdir}"/enorm.1D                   \
               -demean                                       \
               -write "${owdir}"/enorm_demean.1D             \
               -overwrite
    1deval     -a "${owdir}"/enorm_demean.1D                 \
               -b "${owdir}"/enorm_deriv.1D                  \
               -expr 'abs(a)+b'                              \
               > "${owdir}"/min_enorm_disp_deriv.1D

    set vr_idx = `3dTstat -argmin -prefix - "${owdir}"/min_enorm_disp_deriv.1D\'`

    \rm -f "${owdir}"/___temp_volreg*
else 
    # not be choice, but hope user entered an int
    set max_idx = `3dinfo -nvi "${epi}"`
    
    if ( `echo "${vr_base} > ${max_idx}" | bc` || \
         `echo "${vr_base} < 0" | bc` ) then
        echo "** ERROR: allowed volreg_base range is : [0, ${max_idx}]"     |& tee -a $odir/$histfile
        echo "   but the user's value is outside this: ${vr_base}"          |& tee -a $odir/$histfile
        echo "   Consider using (default, and keyword opt): MIN_OUTLIER"    |& tee -a $odir/$histfile
        goto BAD_EXIT
    endif

    # just use that number
    set vr_idx = "${vr_base}"
endif
echo "   $vr_idx volume will be the reference volume"                       |& tee -a $odir/$histfile

# save reference volume
3dcalc -a "${epi}[$vr_idx]"            \
       -expr 'a'                       \
       -prefix "${owdir}"/epi_base     \
       -overwrite 

# ---- check dsets that are optional, to verify (if present)
# unsaturated EPI image might be useful for high SMS accelrated dataset, e.g. HCP
# the below is commmented (out 20231208, W.S)
# these lists must have same length: input filenames and wdir
# filenames, respectively
# set all_dset = ( "${unsatepi}" "${epi_mask}" )
# set all_wlab = ( unsatepi_00.nii.gz epi_mask )

# if ( ${#all_dset} != ${#all_wlab} ) then
    
#    echo "** ERROR in script: all_set and all_wlab must have same len"
#    goto BAD_EXIT
# endif

# finally go through list and verify+copy any that are present
# foreach ii ( `seq 1 1 ${#all_dset}` )
    # must keep :q here, to keep quotes, in case fname is empty
#     set dset = "${all_dset[$ii]:q}"
#     set wlab = "${all_wlab[$ii]:q}"
#     if ( "${dset}" != "" ) then
#         # verify dset is OK to read
#         3dinfo "${dset}"  >& /dev/null
#         if ( ${status} ) then
#             echo "** ERROR: cannot read/open dset: ${dset}"
#             goto BAD_EXIT
#         endif
# 
        # # must have same grid as input EPI
#         set same_grid = `3dinfo -same_grid "${epi}" "${dset}"`
#         if ( "${same_grid}" != "1 1" ) then
#             echo "** ERROR: grid mismatch between input EPI and: ${dset}"
#             goto BAD_EXIT
#         endif

#         # at this point, copy to wdir
#         3dcalc                                \
#             -a "${dset}"                      \
#             -expr 'a'                         \
#             -prefix "${owdir}/${wlab}" 
#     endif
# end

# ----- make automask, if one is not provided

if ( "${epi_mask}" == "" ) then
    echo "++ No mask provided, will make one" |& tee -a $odir/$histfile

    # remove skull (PT: could use 3dAutomask)
    3dSkullStrip                               \
        -input "${owdir}"/epi_base+orig        \
        -prefix "${owdir}/___tmp_mask0.nii"    \
        -overwrite

    # binarize
    3dcalc                                     \
        -a "${owdir}/___tmp_mask0.nii"         \
        -expr 'step(a)'                        \
        -prefix "${owdir}/___tmp_mask1.nii"    \
        -datum byte -nscale                    \
        -overwrite

    # inflate mask; name must match wlab name for user mask, above
    3dcalc \
        -a "${owdir}/___tmp_mask1.nii"            \
        -b a+i -c a-i -d a+j -e a-j -f a+k -g a-k \
        -expr   'amongst(1,a,b,c,d,e,f,g)'        \
        -prefix "${owdir}/epi_base_mask"          \
        -overwrite

    # clean a bit
    \rm -f ${owdir}/___tmp*nii
else
    echo "** Note that reference volume is selected $vr_idx volume of input **" \
        |& tee -a $odir/$histfile
    echo "** IF input mask is not generated from $vr_idx volume, " \
        |& tee -a $odir/$histfile
    echo "** SLOMOCO might underperform. " \
        |& tee -a $odir/$histfile

    3dcalc -a       "${epi_mask}"               \
           -expr    'step(a)'                   \
           -prefix  "${owdir}/epi_base_mask"    \
           -nscale                              \
           -overwrite
endif


# ----- check about physio/pestica regressors, cp to wdir if present

if ( "${physiofile}" != "" ) then
    if ( ! -e "${physiofile}" ) then 
        echo "** ERROR: cannot find ${physiofile} " |& tee -a $odir/$histfile
        goto BAD_EXIT
    else
        1dcat $physiofile  > ${owdir}/rm.physio.1D 
        echo "++ Physiologic nuisance regressor will be included: ${physiofile} " \
            |& tee -a $odir/$histfile
    endif
else
    echo "++ Physiologic nuisnance regressor will NOT be includled. " \
        |& tee -a $odir/$histfile
    
    \rm -f ${owdir}/rm.physio.1D 

endif


# ----- slice timing file info
if ( "$jsonfile" != "" && "$tfile" != "")  then
    echo " ** ERROR:  Both jsonfile and tfile options should not be used." \
        |& tee -a $odir/$histfile
    goto BAD_EXIT
else if ( "$jsonfile" != "")  then
    abids_json_info.py -json $jsonfile -field SliceTiming | sed "s/[][]//g" \
        | sed "s/,//g" | xargs printf "%s\n" > ${owdir}/__tshiftfile.1D
else if ( "$tfile" != "")  then
    \cp $tfile ${owdir}/__tshiftfile.1D
endif

# replace colomn vector to row vector
set dims = `1d_tool.py -infile  ${owdir}/__tshiftfile.1D -show_rows_cols -verb 0`
if ( ${dims[1]} == 1 ) then
    1dcat ${owdir}/__tshiftfile.1D > ${owdir}/tshiftfile.1D
else
    1dtranspose ${owdir}/__tshiftfile.1D > ${owdir}/tshiftfile.1D -overwrite
endif
\rm -f ${owdir}/__tshiftfile.1D

# ----- moco method has allowed value

# value can only be one of a short list
if ( ${moco_meth} != "A" && ${moco_meth} != "W" ) then
    echo "** ERROR: bad moco method selected; must be one of: A, W." \
        |& tee -a $odir/$histfile
    echo "   User provided: '${moco_meth}'" |& tee -a $odir/$histfile
    goto BAD_EXIT
endif


# =======================================================================
# =========================== ** Main work ** ===========================
# move to wdir to do work
cd "${owdir}"


# slibase.1D format of physio file
if ( "${physiofile}" == "" ) then
    set physiostr = "" 
else
    set physiostr = "-slireg rm.physio.1D "
endif

# ----- step 1 voxelwise time-series PV regressor & volmoco
# volreg output is also generated.
if ( -f epi_02_pvreg+orig.HEAD ) then
    echo "++ Skip: gen_vol_pvreg.tcsh. epi_02_pvreg+orig.HEAD exists. " |& tee -a $odir/$histfile
    echo "++ If you need to regenerate PV regressor, "                  |& tee -a $odir/$histfile
    echo "++   delete epi_02_pvreg+orig.HEAD/BRIK and re-run it. "      |& tee -a $odir/$histfile

else
    echo "++ Run: gen_vol_pvreg.tcsh"                                   |& tee -a $odir/$histfile
    
    # ----- step 1.1 voxelwise time-series PV regressor
    # volreg output is also generated.
    gen_vol_pvreg.tcsh ${do_echo}           \
	-dset_epi   epi_00+orig             \
        -dset_mask  epi_base_mask+orig      \
        -vr_idx     ${vr_idx}               \
        -prefix_vr  epi_01_volreg           \
        -prefix_pv  epi_02_pvreg            \
        -do_clean                           \
        |& tee      log_gen_vol_pvreg.txt

    # step 1.2 regression: 6 volmopa + physio (if any) for QA later        
    run_regout_nuisance.tcsh ${do_echo}     \
        -dset_epi   epi_01_volreg+orig      \
        -dset_mask  epi_base_mask+orig      \
        -volreg     epi_01_volreg.1D        \
        -polort     1                       \
        -prefix     epi_03_volmoco          \
        -do_clean                           \
        $physiostr                          \
        |& tee      log_run_regout_volmoco.txt

    # step 1.3 regression: 6 volmopa + PV + physio (if any) for QA later        
    run_regout_nuisance.tcsh ${do_echo}     \
        -dset_epi   epi_01_volreg+orig      \
        -dset_mask  epi_base_mask+orig      \
        -volreg     epi_01_volreg.1D        \
        -polort     1                       \
        -voxreg     epi_02_pvreg+orig       \
        -prefix     epi_03_volmoco_pvreg    \
        -do_clean                           \
        $physiostr                          \
        |& tee      log_run_regout_volmoco.txt

    if ( $status ) then
        goto BAD_EXIT
    endif
endif


# ----- step 2 slicewise moco in xy plane
# script for inplane motion correction

if ( -d inplane ) then
    if ( $volregfirst == 1 ) then
        echo "++ Skip: adjunct_slomoco_slicemoco_xy.tcsh. inplane directory exists. "               |& tee -a $odir/$histfile
    else
        echo "++ Skip: adjunct_slomoco_vol_slicemoco_xy.tcsh. inplane directory exists. "           |& tee -a $odir/$histfile
    endif
    echo "++ If you need to redo slicewise inplane moco, delete inplane directory and re-run it. "  |& tee -a $odir/$histfile
else
    if ( $volregfirst == 1 ) then
        echo "++ Run: adjunct_slomoco_slicemoco_xy.tcsh"                \
            |& tee -a $odir/$histfile

        adjunct_slomoco_slicemoco_xy.tcsh  ${do_echo}                   \
           -dset_epi    epi_01_volreg+orig                              \
           -dset_mask   epi_base_mask+orig                              \
           -moco_meth   ${moco_meth}                                    \
           -workdir     inplane                                         \
           -volreg_mat  epi_01_volreg.aff12.1D                          \
           -tfile       tshiftfile.1D                                   \
           -prefix      epi_03_slicemoco_xy                             \
           -do_clean                                                    \
           |& tee       log_adjunct_slomoco_slicemoco_xy.txt
           
        if ( $status ) then
            goto BAD_EXIT
        endif
    else
        echo "++ Run: adjunct_slomoco_vol_slicemoco_xy.tcsh"            \
            |& tee -a $odir/$histfile

        adjunct_slomoco_vol_slicemoco_xy.tcsh  ${do_echo}               \
           -dset_epi    epi_00+orig                                     \
           -dset_base   epi_motsim+orig                                 \
           -dset_mask   epi_motsim_mask4d+orig                          \
           -moco_meth   ${moco_meth}                                    \
           -workdir     inplane                                         \
           -volreg_mat  epi_01_volreg.aff12.1D                          \
           -tfile       tshiftfile.1D                                   \
           -prefix      epi_03_slicemoco_xy                             \
           -do_clean                                                    \
           |& tee       log_adjunct_slomoco_vol_slicemoco_xy.txt

        if ( $status ) then
            goto BAD_EXIT
        endif
     endif
endif

if ( $status ) then
    goto BAD_EXIT
endif
    

# ----- step 3 slicewise out of plane moco

# script for out-of-plane motion correction
if ( -d outofplane ) then
    echo "++ Skip: adjunct_slomoco_inside_fixed_vol.tcsh. outofplane directory exists. " |& tee -a $odir/$histfile
    echo "++ If you need to redo slicewise out-of-plane moco, delete outofplane directory and re-run it. " |& tee -a $odir/$histfile
else
    echo "++ Run: adjunct_slomoco_inside_fixed_vol.tcsh" |& tee -a $odir/$histfile

    adjunct_slomoco_inside_fixed_vol.tcsh  ${do_echo}                       \
        -dset_epi    epi_03_slicemoco_xy+orig                               \
        -dset_mask   epi_base_mask+orig                                     \
        -workdir     outofplane                                             \
        -tfile       tshiftfile.1D                                          \
        |& tee       log_adjunct_slomoco_inside_fixed_vol.txt

    if ( $status ) then
        goto BAD_EXIT
    endif
endif


# ----- step 4 generate slicewise 6 rigid motion parameter regressor 

# script for slice mopa nuisance regressor
#if ( -d combined_slicemopa ) then
#    echo "++ Skip: adjunct_slomoco_calc_slicemopa.tcsh. combined_slicemopa directory exists. " |& tee -a $odir/$histfile
#    echo "++ If you need to redo in and out-of-plane motion parameter calculation, " |& tee -a $odir/$histfile
#    echo "++   delete combined_slicemopa directory and re-run it. " |& tee -a $odir/$histfile
#else
    echo "++ Run: adjunct_slomoco_calc_slicemopa.tcsh" |& tee -a $odir/$histfile
    
    adjunct_slomoco_calc_slicemopa.tcsh ${do_echo}                          \
        -dset_epi    epi_00+orig                               \
        -indir       inplane                                                \
        -outdir      outofplane                                             \
        -workdir     combined_slicemopa                                     \
        -tfile       tshiftfile.1D                                          \
        -prefix      rm.slimopa.1D                                          \
        |& tee       log_adjunct_slomoco_calc_slicemopa.txt
    
    if ( $status ) then
        goto BAD_EXIT
    endif
#endif


# -----  step 5 second order regress out
# regression: 6 volmopa + 6 slimopa + voxel PV + physio (if any)
echo "++ Run: run_regout_nuisance.tcsh "                            |& tee -a $odir/$histfile
echo "   Motion nuisance regressors: 6 vol-/sli-mopa & 1 vox-PV"    |& tee -a $odir/$histfile

# step 5.1 combine physio 1D with slireg  
\rm -f rm.slimopa.physio.1D  
if ( $physiofile == "" ) then
    echo "copying rm.slimocp.1D to rm.slimopa.physio.1D"
    cp rm.slimopa.1D rm.slimopa.physio.1D
else
    echo "combining physio 1D with slicemopa.1D"
    python $SLOMOCO_DIR/combine_physio_slimopa.py  \
        -slireg rm.slimopa.1D                      \
        -physio rm.physio.1D                       \
        -write  rm.slimopa.physio.1D  
endif

# step 5.2 then run regression
run_regout_nuisance.tcsh ${do_echo}             \
    -dset_epi   epi_03_slicemoco_xy+orig        \
    -dset_mask  epi_base_mask+orig              \
    -volreg     epi_01_volreg.1D                \
    -slireg     rm.slimopa.physio.1D            \
    -voxreg     epi_02_pvreg+orig               \
    -prefix     epi_03_slicemoco_xy.slomoco     \
    -polort     1                    
    
    if ( $status ) then
        goto BAD_EXIT
    endif
    
endif   


# -----  step 6 QA SLOMOCO
echo "++ Run: qa_slomoco.tcsh ++" |& tee -a $odir/$histfile
echo "   Generating estimated in-/out-of-plane motion and motion indices" 
qa_slomoco.tcsh ${do_echo}                              \
    -dset_volmoco   epi_03_volmoco+orig                 \
    -dset_slomoco   epi_03_slicemoco_xy.slomoco+orig    \
    -dset_mask      epi_base_mask+orig                  \
    -tfile          tshiftfile.1D                       \
    -volreg1D       epi_01_volreg.1D                    \
    -slireg1D       rm.slimopa.1D                       \
    |& tee          log_qa_slomoco.txt

if ( $status ) then
    goto BAD_EXIT
endif  
      

# copy the final result
3dcalc                                              \
    -a "${owdir}"/epi_03_slicemoco_xy.slomoco+orig  \
    -expr 'a'                                       \
    -prefix "${odir}/${opref}"                      \
    -overwrite

if ( $DO_CLEAN == 1 ) then
    echo "+* Removing several temp files in slomoco working dir: '$wdir'" \
        |& tee -a $odir/$histfile

    \rm -rf                                             \
        "${owdir}"/epi_00+orig.*                        \
        "${owdir}"/epi_01_volreg+orig.*                 \
        "${owdir}"/epi_02_pvreg+orig.*                  \
        "${owdir}"/epi_03_volmoco+orig.*                \
        "${owdir}"/epi_03_volmoco_pvreg+orig.*          \
#        "${owdir}"/epi_03_slicemoco_xy+orig.*           \
        "${owdir}"/epi_03_slicemoco_xy.slomoco+orig.*   \
        "${owdir}"/epi_motsim*                          \
        "${owdir}"/epi_base_mean.*              
        
            
else
    echo "++ NOT removing temp files in slomoco working dir: '$wdir'" \
        |& tee -a $odir/$histfile
endif

echo "" 
echo "++ DONE.  View the finished, axialized product:" |& tee -a $odir/$histfile
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
 -dset_epi input        = input data is non-motion corrected 4D EPI images. 
                          DO NOT apply any motion correction on input data.
                          It is not recommended to apply physiologic noise correction on the input data
                          Physiologoc noise components can be regressed out with -phyio option 
 -tfile 1Dfile          = 1D file is slice acquisition timing info.
                          For example, 5 slices, 1s of TR, ascending interleaved acquisition
                          [0 0.4 0.8 0.2 0.6]
      or 
 -jsonfile jsonfile     = json file from dicom2nii(x) is given
 -prefix output         = output filename
 
Optional:
 -volreg_base refvol    = reference volume number, "MIN_ENORM" or "MIN_OUTLIER"
                          "MIN_ENORM" provides the volume number with the minimal summation 
                          of absolute volume diplacement and its derivatives. 
                          "MIN_OUTLIER" selects the minimal absolute derivative of the 
                          volume displacement.
                          Default is "0"
 -workdir  directory    = intermediate output data will be generated in the defined directory.
 -physio   1Dfile       = slicebase 1D file. For example, RETROICOR or PESTICA 1D file.
                          For example, 3 slices, 2 time series regressors (reg0 & reg1)
                          reg0@sli0 reg1@sli0 reg0@sli1 reg1@sli1 reg0@sli2 reg1@sli2
                          , where regX@sliY is the colume vector.
                          PESTICA 1D file (RetroTS.PESTICA5.slicebase.1D) or RETROICOR 1D file 
                          (RetroTS.PMU.slicebase.1D) could be input.
 -do_clean              = this option will delete the large size of files in working directory 
 -moco_meth "W" or "A"  = "W" for 3dWarpdrive, "A" for 3dAllineate. Defaulty is "W"
 -volregfirst           = 3dvolreg (Volmoco) is applied to the input, if defined. 
                          Default is 0
                    
Slicewise motion correction could be done in two ways.
   case 1) 3d volume motion (Volmoco) correction first then Slicewise
           motion correction (Slimoco) on Volmoco reference images( 0
           volume )
   case 2) the reference image is defined at each slice using the
           inverse motion afine matrix to the referece image (0
           volume), then Slimoco is applied.

In short, case 1 aligned source slice to the reference image vs case 2
native source slice to the aligned reference image.  Emperically, we
find the case 2 with 3dWarpDrive works marginally better than case 2
with 3dAllineate and case 1 with 3dWarpdrive or 3dAllineate.  Even the
case 1 with 3dAllineate overfits in-/out-of-slice motion, resulting in
the bad alignment.  ** For this reason: case 2 with 3dWarpDrive is our
top choice. ** 

To do, -volregfirst should NOT be selected (default), and -moco_meth =
"W" (default).  Then the next prefered one would be case 1) with
3dAllineate or 3dWarpdrive.

However, the certain version of 3dWarpdrive stops supporting 2D slice
alignment (with "zero---ish" error), and AFNI resolves this issue 
after "AFNI_24.2.02". If you see a warning that your AFNI is too old,
we strongly recommend updating your AFNI. If your OS is linux AND your
AFNI is older than 24.2.02, 3dWarpdrive (afni.afni.openmp.v18.3.16), 
included in this package will be used. 

To run SLOMOCO with too old AFNI on Mac OS, add an option '-moco_meth A'  
and '-volregfirst' (Why don't you update AFNI? See the note below)


NOTES

AFNI dependency and versioning

This version of SLOMOCO comes with some simultaneous updates in the
AFNI codebase.  To make fullest use of the updates, users should have
AFNI installed on their computer, with at least this version:
   'afni -vnum' >= ${AFNI_MIN_VNUM}.


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
