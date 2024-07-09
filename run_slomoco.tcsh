#!/bin/tcsh

set version   = "0.0";  set rev_dat   = "May 30, 2024"
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
set moco_meth  = "W"  # 'AFNI_SLOMOCO': W -> 3dWarpDrive; A -> 3dAllineate
set vr_base    = "0" # select either "MIN_OUTLIER" or "MIN_ENORM", or integer
set vr_idx     = -1            # will get set by vr_base in opt proc

set epi      = ""   # base 3D+time EPI dataset to use to perform corrections
set epi_mask = ""   # (opt) mask dset name
set jsonfile = ""   # json file
set tfile = ""      # tshiftfile (sec)
set physiofile = "" # physio1D file, from RETROICOR or PESTICA
set regflag = "MATLAB" # MATLAB or AFNI
set qaflag = "MATLAB" # MATLAB or AFNI

set volregfirst = 0 # Slomoco on each aligned refvol.
set DO_CLEAN     = 0                       # default: keep working dir
set histfile = log_slomoco.txt

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

# define SLOMOCO directory
set fullcommand = "$0"
setenv SLOMOCO_DIR `dirname "${fullcommand}"`
setenv MATLAB_SLOMOCO_DIR $SLOMOCO_DIR/slomoco_matlab
setenv AFNI_SLOMOCO_DIR $SLOMOCO_DIR/afni_linux
setenv MATLAB_AFNI_DIR  $SLOMOCO_DIR/afni_matlab

# initialize a log file
echo "" >> $histfile
date >> $histfile
echo "" >> $histfile


# check OS system. In case of Mac, 3dAllineate is used after Volmoco
if ( "$OSTYPE" == "darwin" ) then
    set volregfirst = 1
    set moco_meth = "A"   
    echo "++ SLOMOCO is running on Mac OX" |& tee -a $histfile
    echo "++ 3dvolreg is applied and SLOMOCO is running on volume motion corrected images" |& tee -a $histfile
    echo "++ 3dAllineate is used for slicewise motion correction " |& tee -a $histfile
else
    echo "++ SLOMOCO is running on non-Mac OX" |& tee -a $histfile
    if  ( $volregfirst == "1" ) then
        echo "++ You select running SLOMOCO on volume motion corrected images" |& tee -a $histfile
        echo "++ SLOMOCO is recomended to be used on non-volume motion corrected images" |& tee -a $histfile
        echo "++ You should know what you are doing. I warn you. " |& tee -a $histfile
    else
        echo "++ MotSim data is used for the reference image of SLOMOCO" |& tee -a $histfile 
        echo "++ SLOMOCO is running on non-volume motion corrected images"  |& tee -a $histfile
    endif
    
    if  ( $moco_meth == "A"  ) then 
        echo "++ 3dAllineate is used for slicewise motion correction " |& tee -a $histfile
        echo "++ Our emperical result shows 3dWarpdrive performs better than 3dAllineate " |& tee -a $histfile
        echo "++ You should know what you are doing. I warn you. " |& tee -a $histfile
    else
        echo "++ 3dWarpDrive included in the package is used for slicewise motion correction " |& tee -a $histfile
    endif
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
    echo "** ERROR: need to provide output name with '-prefix ..'" |& tee -a $histfile
    goto BAD_EXIT
endif

# check output directory, use input one if nothing given
if ( ! -e "${odir}" ) then
    echo "++ Making new output directory: $odir" |& tee -a $histfile
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
    echo "++ Making working directory: ${owdir}" |& tee -a $histfile
    \mkdir -p "${owdir}"
else
    echo "+* WARNING:  Somehow found a premade working directory:" |& tee -a $histfile
    echo "      ${owdir}"
endif

# find slice acquisition timing
if ( "${jsonfile}" == "" && "${tfile}" == "" ) then
    echo "** ERROR: slice acquisition timing info should be given with -json or -tfile option" |& tee -a $histfile
    goto BAD_EXIT
else
  if ( ! -e "${jsonfile}" && "${jsonfile}" != "" ) then
    echo "** ERROR: Json file does not exist" |& tee -a $histfile
    goto BAD_EXIT
  endif
  if ( ! -e "${tfile}" && "${tfile}" != "" ) then
    echo "** ERROR: tshift file does not exist" |& tee -a $histfile
    goto BAD_EXIT
  endif
endif

# ----- find required dsets, and any properties

if ( "${epi}" == "" ) then
    echo "** ERROR: need to provide EPI dataset with '-dset_epi ..'" |& tee -a $histfile
    goto BAD_EXIT
else
    # verify dset is OK to read
    3dinfo "${epi}"  >& /dev/null
    if ( ${status} ) then
        echo "** ERROR: cannot read/open dset: ${epi}" |& tee -a $histfile
        goto BAD_EXIT
    endif

    # must have +orig space for input EPI
    set av_space = `3dinfo -av_space "${epi}" `
    if ( "${av_space}" != "+orig" ) then
        echo "** ERROR: input EPI must have +orig av_space, not: ${av_space}" |& tee -a $histfile
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
        echo "** ERROR: allowed volreg_base range is : [0, ${max_idx}]" |& tee -a $histfile
        echo "   but the user's value is outside this: ${vr_base}" |& tee -a $histfile
        echo "   Consider using (default, and keyword opt): MIN_OUTLIER" |& tee -a $histfile
        goto BAD_EXIT
    endif

    # just use that number
    set vr_idx = "${vr_base}"
endif
echo $vr_idx volume will be the reference volume |& tee -a $histfile

# save reference volume
3dcalc -a "${epi}[$vr_idx]" -expr 'a' -prefix "${owdir}"/epi_base -overwrite 

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
    echo "++ No mask provided, will make one" |& tee -a $histfile
    # remove skull (PT: could use 3dAutomask)
    3dSkullStrip                               \
        -input "${owdir}"/epi_base+orig        \
        -prefix "${owdir}/___tmp_mask0.nii.gz" \
        -overwrite

    # binarize
    3dcalc                                     \
        -a "${owdir}/___tmp_mask0.nii.gz"      \
        -expr 'step(a)'                        \
        -prefix "${owdir}/___tmp_mask1.nii.gz" \
        -datum byte -nscale                    \
        -overwrite

    # inflate mask; name must match wlab name for user mask, above
    3dcalc \
        -a "${owdir}/___tmp_mask1.nii.gz"         \
        -b a+i -c a-i -d a+j -e a-j -f a+k -g a-k \
        -expr 'amongst(1,a,b,c,d,e,f,g)'          \
        -prefix "${owdir}/epi_base_mask"          \
        -overwrite

    # clean a bit
    rm ${owdir}/___tmp*nii.gz
else
  echo "** Note that reference volume is selected $vr_idx volume of input **" |& tee -a $histfile
  echo "** IF input mask is not generated from $vr_idx volume, " |& tee -a $histfile
  echo "** SLOMOCO might underperform. "  |& tee -a $histfile
    3dcalc -a "${epi_mask}"                 \
           -expr 'step(a)'                        \
           -prefix "${owdir}/epi_base_mask" \
           -nscale                          \
           -overwrite
endif

# ----- save name to apply
set epi_mask = "${owdir}/epi_base_mask+orig"


# ----- check about physio/pestica regressors, cp to wdir if present

if ( "${physiofile}" != "" ) then
    if ( ! -e "${physiofile}" ) then 
        echo "** ERROR: cannot ${physiofile} " |& tee -a $histfile
        goto BAD_EXIT
    else
        1dcat $physiofile  > ${owdir}/physioreg.1D 
        echo "++ Second order SLOMOCO will be conducted with  ${physiofile} " |& tee -a $histfile

    endif

else
    echo "++ Second order SLOMOCO will be conducted without physiofile " |& tee -a $histfile
    rm -f ${owdir}/physioreg.1D
endif


# ----- slice timing file info
if ( "$jsonfile" != "" && "$tfile" != "")  then
  echo " ** ERROR:  Both jsonfile and tfile options should not be used." |& tee -a $histfile
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
    echo "** ERROR: bad moco method selected; must be one of: A, W." |& tee -a $histfile
    echo "   User provided: '${moco_meth}'" |& tee -a $histfile
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
echo "++ Run: gen_vol_pvreg.tcsh"  |& tee -a ../$histfile
gen_vol_pvreg.tcsh                 \
    -dset_epi  epi_00+orig         \
    -dset_mask "${epi_mask}"       \
    -vr_idx    "${vr_idx}"         \
    -prefix_pv epi_02_pvreg        \
    -prefix_vr epi_01_volreg       \
    |& tee     log_gen_vol_pvreg.txt
    
if ( $status ) then
    goto BAD_EXIT
endif


# ----- step 2 slicewise moco in xy plane
# script for inplane motion correction

if ( -d inplane ) then
    if ( $volregfirst == 1 ) then
        echo "++ Skip: adjunct_slomoco_slicemoco_xy.tcsh. inplane directory exists. " |& tee -a ../$histfile
    else
        echo "++ Skip: adjunct_slomoco_vol_slicemoco_xy.tcsh. inplane directory exists. " |& tee -a ../$histfile
    endif
        echo "++ If you need to redo slicewise inplane moco, delete inplane directory and re-run it. " |& tee -a ../$histfile
else
    if ( $volregfirst == 1 ) then
        echo "++ Run: adjunct_slomoco_slicemoco_xy.tcsh" |& tee -a ../$histfile
        adjunct_slomoco_slicemoco_xy.tcsh  ${do_echo}                       \
           -dset_epi    epi_01_volreg+orig                                     \
           -dset_mask   "${epi_mask}"                                          \
           -moco_meth   ${moco_meth}                                           \
           -workdir     inplane                                                \
           -volreg_mat  epi_01_volreg.aff12.1D                                 \
           -tfile       tshiftfile.1D                                          \
           -prefix      epi_03_slicemoco_xy                                    \
           -do_clean                                                           \
           |& tee       log_adjunct_slomoco_slicemoco_xy.txt
           
    else
        echo "++ Run: adjunct_slomoco_vol_slicemoco_xy.tcsh" |& tee -a ../$histfile
        adjunct_slomoco_vol_slicemoco_xy.tcsh  ${do_echo}                       \
           -dset_epi    epi_00+orig                                            \
           -dset_base   epi_motsim+orig                                        \
           -dset_mask   epi_motsim_mask4d+orig                                 \
           -moco_meth   ${moco_meth}                                           \
           -workdir     inplane                                                \
           -volreg_mat  epi_01_volreg.aff12.1D                                 \
           -tfile       tshiftfile.1D                                          \
           -prefix      epi_03_slicemoco_xy                                    \
           -do_clean                                                           \
           |& tee       log_adjunct_slomoco_vol_slicemoco_xy.txt
     endif
endif

if ( $status ) then
    goto BAD_EXIT
endif
    
# ----- step 3 slicewise out of plane moco

# script for out-of-plane motion correction
if ( -d outofplane ) then
    echo "++ Skip: adjunct_slomoco_inside_fixed_vol.tcsh. outofplane directory exists. " |& tee -a ../$histfile
    echo "++ If you need to redo slicewise out-of-plane moco, delete outofplane directory and re-run it. " |& tee -a ../$histfile

else
    echo "++ Run: adjunct_slomoco_inside_fixed_vol.tcsh" |& tee -a ../$histfile
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
if ( -d combined_slicemopa ) then
    echo "++ Skip: adjunct_slomoco_calc_slicemopa.tcsh. combined_slicemopa directory exists. " |& tee -a ../$histfile
    echo "++ If you need to redo in and out-of-plane motion parameter calculation, " |& tee -a ../$histfile
    echo "++   delete outofplane directory and re-run it. " |& tee -a ../$histfile
else
    echo "++ Run: adjunct_slomoco_calc_slicemopa.tcsh" |& tee -a ../$histfile
    adjunct_slomoco_calc_slicemopa.tcsh                                     \
        -dset_epi    epi_03_slicemoco_xy+orig                               \
        -indir       inplane                                                \
        -outdir      outofplane                                             \
        -workdir     combined_slicemopa                                     \
        -tfile       tshiftfile.1D                                          \
        -prefix      epi_slireg.1D                                          \
        |& tee       log_adjunct_slomoco_calc_slicemopa.txt
    
    if ( $status ) then
        goto BAD_EXIT
    endif

endif

# -----  step 5 second order regress out

# script for 2nd order regress-out
if ( $regflag == "MATLAB" ) then
    echo "++ Run: Nuisance regerssors are regress-out on SLOMOCO images" |& tee -a ../$histfile
    1dcat epi_polort_xmat.1D > rm_polort.1D
    1dcat epi_slireg.1D > rm_slireg.1D
    matlab -nodesktop -nosplash -r "addpath ${MATLAB_SLOMOCO_DIR}; addpath ${MATLAB_AFNI_DIR}; gen_regout('epi_03_slicemoco_xy+orig','epi_base_mask+orig','physio','physioreg.1D','polort','rm_polort.1D','volreg','epi_01_volreg.1D','slireg','epi_slireg.1D','voxreg','epi_02_pvreg+orig','out','epi_03_slicemoco_xy.slomoco'); exit;" 
    rm rm_*

else 
    echo "afni version of vol/sli/voxelwise regression pipeline is working in progress" |& tee -a ../$histfile
                
    1d_tool.py -infile epi_01_volreg.1D -demean -write volreg.demean.1D
    1dcat epi_polort_xmat.1D volreg.demean.1D > volreg.all.1D
        
    1d_tool.py -infile epi_slireg.1D -demean -write slireg.demean.1D
       
    if ( -e "physioreg.1D" ) then
        1d_tool.py -infile physioreg.1D -demean -write physioreg.demean.1D
        # add physio slice regressor with slireg.demean.1D here
        # [To P.T] How we can combine slireg.demean.1D with physioreg.1D file? 
    endif
  
    # 3dREMLfit does not run since slireg.demean.1D includes zero columns
    3dREMLfit                                \ 
        -input      epi_02_slicemoco_xy+orig \
        -matim      volreg.all.1D            \
        -mask       epi_base_mask+orig       \
        -addbase_sm slire.demean.1D          \
        -dsort      epi_01_pvreg+orig        \
        -Rerrt      errts_slomoco+orig       \
        -overwrite

endif   

if ( $status ) then
    goto BAD_EXIT
endif

# -----  step 6 QA SLOMOCO
if ( $qaflag == "MATLAB" ) then
    echo "++ Run: QA SLOMOCO, generating estimated in-/out-of-plane motion and motion indices " |& tee -a ../$histfile
    matlab -nodesktop -nosplash -r "addpath ${MATLAB_SLOMOCO_DIR}; addpath ${MATLAB_AFNI_DIR}; qa_slomoco('epi_03_slicemoco_xy+orig','epi_base_mask+orig','epi_01_volreg.1D','epi_slireg.1D'); exit;" 
else
    echo "afni version of qa display is working in progress" 
endif  
 
if ( $status ) then
    goto BAD_EXIT
endif


# move out of wdir to the odir
cd ..
set whereout = $PWD

# copy the final result
3dcalc                                     \
   -a "${owdir}"/epi_03_slicemoco_xy.slomoco+orig   \
   -expr 'a'                              \
   -prefix "${prefix}"                        \
   -overwrite

if ( $DO_CLEAN == 1 ) then
    echo "+* Removing the large size of temporary files in working dir: '$wdir' " |& tee -a $histfile

    # ***** clean
    rm -rf    "${owdir}"/epi_00+orig.*         \
          "${owdir}"/epi_motsim+orig.*      \
          "${owdir}"/epi_motsim_mask4d+orig.*   

else
    echo "++ NOT removing temporary axialization working dir: '$wdir' " |& tee -a $histfile
endif

echo "" 
echo "++ DONE.  View the finished, axialized product:" |& tee -a $histfile
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
find the case 2 with 3dWarpdrive works marginally better than case 2
with 3dAllineate and case 1 with 3dWarpdrive or 3dAllineate.  Even the
case 1 with 3dAllineate overfits in-/out-of-slice motion, resulting in
the bad alignment.  ** For this reason: case 2 with 3dWarpdrive is our
top choice. **

To do, -volregfirst should NOT be selected (default), and -moco_meth =
"W" (default).  Then the next prefered one would be case 1) with
3dAllineate or 3dWarpdrive.

However, the latest version of 3dWarpdrive stops supporting 2D slice
alignment (with "zero---ish" error).  We find the specific version of
3dWarpdrive (afni.afni.openmp.v18.3.16), included in this package only
works for linux.

In this reason, if you run SLOMOCO on Mac OS, the script selects
-volregfirst and runs with 3dAllineate from YOUR AFNI software
automatically.

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
