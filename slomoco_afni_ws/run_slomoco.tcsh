#!/bin/tcsh

set version   = "0.0";  set rev_dat   = "Nov 28, 2023"
# + tcsh version of Wanyong Shin's SLOMOCO program
#
# ----------------------------------------------------------------

# -------------------- set environment vars -----------------------

setenv AFNI_MESSAGE_COLORIZE     NO         # so all text is simple b/w

# ----------------------- set defaults --------------------------

set this_prog = "run_slomoco"
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

# find slice acquisition timing
if ( "${jsonfile}" == "" && "${tfile}" == "" ) then
    echo "** ERROR: slice acquisition timing info should be given with -json or -tfile option"
    goto BAD_EXIT
else
  if ( ! -e "${jsonfile}" && "${jsonfile}" != "" ) then
    echo "** ERROR: Json file does not exist"
    goto BAD_EXIT
  endif
  if ( ! -e "${tfile}" && "${tfile}" != "" ) then
    echo "** ERROR: tshift file does not exist"
    goto BAD_EXIT
  endif
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

    # copy to wdir
    3dcalc \
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
    echo "++ MIN_OUTLIER vr_idx : $vr_idx" \
        | tee "${owdir}/out.min_outlier.txt"

else if ( "${vr_base}" == "MIN_ENORM" ) then

    3dvolreg                                    \
        -1Dfile "${owdir}"/___temp_volreg.1D    \
        -prefix "${owdir}"/___temp_volreg+orig  \
        -overwrite                              \
        "${epi}"

    1d_tool.py -infile "${owdir}"/___temp_volreg.1D \
               -derivative \
               -collapse_cols euclidean_norm \
               -write "${owdir}"/enorm_deriv.1D -overwrite
    1d_tool.py -infile "${owdir}"/___temp_volreg.1D \
               -collapse_cols euclidean_norm \
               -write "${owdir}"/enorm.1D -overwrite
    1d_tool.py -infile "${owdir}"/enorm.1D \
               -demean \
               -write "${owdir}"/enorm_demean.1D -overwrite
    1deval     -a "${owdir}"/enorm_demean.1D \
               -b "${owdir}"/enorm_deriv.1D \
               -expr 'abs(a)+b' \
               > "${owdir}"/min_enorm_disp_deriv.1D
    set vr_idx = `3dTstat -argmin -prefix - "${owdir}"/min_enorm_disp_deriv.1D\'`
    rm "${owdir}"/___temp_volreg*
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
echo $vr_idx volume will be the reference volume

# save reference volume
3dcalc -a "${epi}[$vr_idx]" -expr 'a' -prefix "${owdir}"/epi_base -overwrite

cat <<EOF >> ${histfile}
++ epi_base+orig is the reference volume (basline), $vr_idx th volume of input
EOF

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
    echo "++ No mask provided, will make one" |& tee ${histfile}
    # remove skull (PT: could use 3dAutomask)
    3dSkullStrip \
        -input "${owdir}"/epi_base+orig \
        -prefix "${owdir}/___tmp_mask0.nii.gz" \
        -overwrite

    # binarize
    3dcalc  \
        -a "${owdir}/___tmp_mask0.nii.gz" \
        -expr 'step(a)' \
        -prefix "${owdir}/___tmp_mask1.nii.gz" \
        -datum byte -nscale \
        -overwrite

    # inflate mask; name must match wlab name for user mask, above
    3dcalc \
        -a "${owdir}/___tmp_mask1.nii.gz"  \
        -b a+i -c a-i -d a+j -e a-j -f a+k -g a-k \
        -expr 'amongst(1,a,b,c,d,e,f,g)' \
        -prefix "${owdir}/epi_base_mask" \
        -overwrite

    # clean a bit
    rm ${owdir}/___tmp*nii.gz
else
  echo "** Note that reference volume is selected $vr_idx volume of input **"
  echo "** IF input mask is not generated from $vr_idx volume, "
  echo "** SLOMOCO might underperform. " 
    3dcalc -a "${epi_mask}"                 \
           -expr 'a'                        \
           -prefix "${owdir}/epi_base_mask" \
           -nscale                          \
           -overwrite
endif

# ----- save name to apply
set epi_mask = "${owdir}/epi_base_mask+orig"


# ----- check about physio/pestica regressors, cp to wdir if present

if ( "${physiofile}" != "" ) then
    if ( ! -e "${physiofile}" ) then 
        echo "** ERROR: cannot ${physiofile} "
        goto BAD_EXIT
    else
        1dcat $physiofile  > ${owdir}/physioreg.1D 

cat <<EOF >> ${histfile}
++ Second order SLOMOCO will be conducted with  ${physiofile}
EOF

    endif

cat <<EOF >> ${histfile}
++ Second order SLOMOCO will be conducted without physiofile
EOF
    
endif


# ----- slice timing file info
if ( "$jsonfile" != "" && "$tfile" != "")  then
  echo " ** ERROR:  Both jsonfile and tfile options should not be used."
  goto BAD_EXIT
else if ( "$jsonfile" != "")  then
  abids_json_info.py -json $jsonfile -field SliceTiming | sed "s/[][]//g" | sed "s/,//g" | xargs printf "%s\n" > ${owdir}/tshiftfile.1D
else if ( "$tfile" != "")  then
  cp $tfile ${owdir}/tshiftfile.1D
endif

# ----- moco method has allowed value

# value can only be one of a short list
if ( ${moco_meth} != "A" && \
     ${moco_meth} != "W" ) then
    echo "** ERROR: bad moco method selected; must be one of: A, W."
    echo "   User provided: '${moco_meth}'"
    goto BAD_EXIT
endif



# =======================================================================
# =========================== ** Main work ** ===========================

# move to wdir to do work
cd "${owdir}"

# update mask file name
set epi_mask = "epi_base_mask+orig"

# linear detrending matrix
3dDeconvolve -polort 1 -input epi_00+orig -x1D_stop -x1D epi_polort_xmat.1D

# ----- step 1 voxelwise time-series PV regressor
# volreg output is also generated.
if ( $step1flag != 'skip' ) then
    gen_vol_pvreg.tcsh                 \
        -dset_epi  epi_00+orig        \
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

# ----- step 2 slicewise moco in xy plane

# script for inplane motion correction

if ( $step2flag != 'skip' ) then
    echo "++ Run: adjunct_slomoco_vol_slicemoco_xy.tcsh"
    adjunct_slomoco_vol_slicemoco_xy.tcsh  ${do_echo}                       \
        -dset_epi    epi_00+orig                                     \
        -dset_base   epi_motsim+orig                                     \
        -dset_mask   epi_motsim_mask4d+orig                                 \
        -moco_meth   ${moco_meth}                                           \
        -workdir     inplane                                                \
        -volreg_mat  epi_01_volreg.aff12.1D                                 \
        -tfile       tshiftfile.1D                                          \
        -prefix      epi_02_slicemoco_xy                                    \
        |& tee       log_adjunct_slomoco_vol_slicemoco_xy.txt

    if ( $status ) then
        goto BAD_EXIT
    endif

cat <<EOF >> ${histfile}
++ slicewise inplane motion correction is done.
EOF

endif


# ----- step 3 slicewise out of plane moco

# script for out-of-plane motion correction
if ( $step3flag != 'skip' ) then
    echo "++ Run: adjunct_slomoco_inside_fixed_vol.tcsh"
    adjunct_slomoco_inside_fixed_vol.tcsh  ${do_echo}                       \
        -dset_epi    epi_02_slicemoco_xy+orig                               \
        -dset_mask   epi_base_mask+orig                                     \
        -workdir     outofplane                                             \
        -tfile       tshiftfile.1D                                          \
        |& tee       log_adjunct_slomoco_inside_fixed_vol.txt

    if ( $status ) then
        goto BAD_EXIT
    endif

cat <<EOF >> ${histfile}
++ slicewise out-of-plane motion correction is done.
EOF

endif

# ----- step 4 generate slicewise 6 rigid motion parameter regressor 

# script for slice mopa nuisance regressor
if ( $step4flag != 'skip' ) then
    adjunct_slomoco_calc_slicemopa.tsch                                     \
        -dset_epi    epi_02_slicemoco_xy+orig                               \
        -indir       inplane                                                \
        -outdir      outofplane                                             \
        -workdir     combined_slicemopa                                     \
        -tfile       tshiftfile.1D                                          \
        -prefix      epi_slireg.1D                                       \
        |& tee       log_adjunct_slomoco_calc_slicemopa.txt
    
    if ( $status ) then
        goto BAD_EXIT
    endif

cat <<EOF >> ${histfile}
++ slicewise motion nuisance regressor is generated.
EOF

endif

# -----  step 5 second order regress out

# script for 2nd order regress-out
if ( $step5flag != "skip" ) then
    if ( $regflag == "MATLAB" ) then
        1dcat epi_polort_xmat.1D > rm_polort.1D
        1dcat epi_slireg.1D > rm_slireg.1D
        matlab -nodesktop -nosplash -r "addpath ${MATLAB_SLOMOCO_DIR};  gen_regout('epi_02_slicemoco_xy+orig','epi_base_mask+orig','physio','rm_physio.1D','polort','rm_polort.1D','volreg','epi_01_volreg.1D','slireg','rm_slireg.1D','voxreg','epi_01_pvreg+orig','out','${prefix}'); exit;"
        rm rm_*
    else 
        echo "afni version of vol/sli/voxelwise regression pipeline is working in progress" 
                
        1d_tool.py -infile epi_01_volreg.1D -demean -write volreg.demean.1D
        1dcat epi_polort_xmat.1D volreg.demean.1D > volreg.all.1D
        
        1d_tool.py -infile epi_slireg.1D -demean -write slireg.demean.1D
        
        if ( -e "physioreg.1D" ) then
            1d_tool.py -infile physioreg.1D -demean -write physioreg.demean.1D
            # add physio slice regressor with slireg.demean.1D here
            # [To P.T] How we can combine slireg.demean.1D with physioreg.1D file? 
        endif
  
        # [TO P.T] it does not run since slireg.demean.1D includes zero columns
        3dREMLfit \ 
            -input      epi_02_slicemoco_xy+orig \
            -matim      volreg.all.1D \
            -mask       epi_base_mask+orig \
            -addbase_sm slire.demean.1D \
            -dsort      epi_01_pvreg+orig \
            -Rerrt      errts_slomoco+orig
    
  
    endif   

    if ( $status ) then
        goto BAD_EXIT
    endif

cat <<EOF >> ${histfile}
++ The residual motion artifact is regressed out with motion nuisance parameters.
EOF

endif

# -----  step 6 QA SLOMOCO
if ( $step6flag != "skip" ) then
    if ( $qaflag == "MATLAB" ) then
        matlab -nodesktop -nosplash -r "addpath ${MATLAB_SLOMOCO_DIR}; qa_slomoco('epi_02_slicemoco_xy+orig','epi_base_mask+orig','epi_01_volreg.1D','epi_slireg.1D'); exit;"
    else
        echo "afni version of qa display is working in progress" 
    endif  
 
    if ( $status ) then
        goto BAD_EXIT
    endif

cat <<EOF >> ${histfile}
++ Quality Assurance of SLOMOCO is generated.
EOF

endif

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
