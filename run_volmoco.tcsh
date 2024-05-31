#!/bin/tcsh

set version   = "0.0";  set rev_dat   = "Nov 28, 2023"
# + tcsh version of Wanyong Shin's VOLMOCO program
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

# --------------------- volmoco-specific inputs --------------------

# all allowed slice acquisition keywords
set vr_base    = "0" # select either "MIN_OUTLIER" or "MIN_ENORM", or integer
set vr_idx     = -1            # will get set by vr_base in opt proc

set epi      = ""   # base 3D+time EPI dataset to use to perform corrections
set epi_mask = ""   # (opt) mask dset name
set roi_mask = ""   # (opt) tissue mask to report SD reduction after nuisance regress-out

set physiofile = "" # physio1D file, from RETROICOR or PESTICA
set regflag = "AFNI" # MATLAB or AFNI
set qaflag = "MATLAB" # MATLAB or AFNI

set DO_CLEAN     = 0                       # default: keep working dir

set histfile = log_volmoco.txt

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

    # --------- optional 
    else if ( "$argv[$ac]" == "-dset_mask" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_mask = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_mask" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set roi_mask = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-physio" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set physiofile = "$argv[$ac]"

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
$fullcommand -dset_epi $epi -prefix $prefix
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

    # copy to wdir
    3dcalc \
        -a "${epi}"               \
        -expr 'a'                 \
        -prefix "${owdir}/epi_00" \
        -overwrite
endif

# ----- The reference volume number for 3dvolreg & PV sanity check
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

# ----- Mask setting
if ( "${epi_mask}" == "" ) then
	3dcalc -a "${epi}[$vr_idx]" -expr 'step(a-200)' -prefix "${owdir}"/epi_base_mask
else
	3dcalc -a $epi_mask -expr 'a' -prefix "${owdir}"/epi_base_mask -overwrite
endif

if ( "${roi_mask}" == "" ) then
	set roi_mask = "epi_base_mask+orig" 
else
	set roi_mask = "${owdir}"/"${roi_mask}" 
endif

# ----- physio file sanity check

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

# ----- step 2 second order 

1d_tool.py -infile epi_01_volreg.1D -demean -write mopa6.demean.1D
3dDeconvolve 							\
	-input epi_01_volreg+orig 			\
	-mask epi_base_mask+orig 			\
  	-polort 1 							\
  	-x1D det.1D 						\
  	-x1D_stop 
 3dDeconvolve 															\
 	-input epi_01_volreg+orig 											\
 	-mask epi_base_mask+orig 											\
  	-polort 1 															\
  	-num_stimts 6 														\
  	-stim_file 1 mopa6.demean.1D'[0]' -stim_label 1 mopa1 -stim_base 1 	\
  	-stim_file 2 mopa6.demean.1D'[1]' -stim_label 2 mopa2 -stim_base 2 	\
  	-stim_file 3 mopa6.demean.1D'[2]' -stim_label 3 mopa3 -stim_base 3 	\
  	-stim_file 4 mopa6.demean.1D'[3]' -stim_label 4 mopa4 -stim_base 4 	\
  	-stim_file 5 mopa6.demean.1D'[4]' -stim_label 5 mopa5 -stim_base 5 	\
  	-stim_file 6 mopa6.demean.1D'[5]' -stim_label 6 mopa6 -stim_base 6 	\
  	-x1D mopa6.1D 														\
  	-x1D_stop 
  
# Linear detrending terms only 
3dREMLfit 						\
	-input 	epi_01_volreg+orig 	\
	-mask 	epi_base_mask+orig 	\
 	-matrix det.1D 				\
  	-Oerrts errt.det			\
  	|& tee     log_gen_vol_pvreg.txt	
  	  
if ( $physiofile == "") then
 	# 6 Vol-mopa + PV + linear detrending terms 
	3dREMLfit 						\
		-input epi_01_volreg+orig 	\
		-mask epi_base_mask+orig 	\
  		-matrix mopa6.1D 			\
  		-dsort epi_01_pvreg+orig 	\
  		-dsort_nods					\
  		-Oerrts errt.mopa6.pvreg	\
  		|& tee     log_gen_vol_pvreg.txt

else
	# 6 Vol-mopa + PV + linear detrending terms + Physio file (1D)  
	3dREMLfit 						\
		-input epi_01_volreg+orig 	\
		-mask epi_base_mask+orig 	\
  		-matrix mopa6.1D 			\
  		-dsort epi_01_pvreg+orig 	\
  		-slibase_sm $physiofile		\
  		-dsort_nods					\
  		-Oerrts errt.mopa6.pvreg	\
  		|& tee     log_gen_vol_pvreg.txt

endif
 
cat <<EOF >> ${histfile}
++ Nuisance regressros are regressed out.
EOF
 
# present SD reduction (optional)
3dTstat -stdev 						\
	-prefix errt.det.std	\
	errt.det+orig
3dTstat -stdev 						\
	-prefix errt.mopa6.pvreg.std	\
	errt.mopa6.pvreg+orig
3dTstat -stdev 						\
	-prefix errt.mopa6.std 			\
	errt.mopa6.pvreg_nods+orig

# ROIstats
3dROIstats -quiet					\
	mask "${roi_mask}"				\
	errt.det.std+orig > SDreduction.1D

3dROIstats -quiet					\
	mask "${roi_mask}"				\
	errt.mopa6.pvreg_nods.std+orig	>> SDreduction.1D

3dROIstats -quiet					\
	mask "${roi_mask}"				\
	errt.mopa6.pvreg.std+orig	>> SDreduction.1D

echo +++++++++++++++++++++	
if ( $physiofile == "" ) then
	echo ++ average SD in a mask (baseline, 6 Vol-mopa, 6 vol-mopa + PV )	
else
	echo ++ average SD in a mask (baseline, 6 Vol-mopa + physio, 6 vol-mopa + physio + PV )	
endif
cat SDreduction.1D
echo +++++++++++++++++++++

rm errt.det+orig.* errt.mopa6.pvreg_nods+orig.* _.*   


# move out of wdir to the odir
cd ..
set whereout = $PWD

# copy the final result
3dcalc -a "${owdir}"/errt.mopa6.pvreg+orig -expr 'a' \
	-prefix "${prefix}" . # output only
 

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

VOLMOCO: volumewise motion correction script based on 3dvolreg AFNI commands
		 Nuisance modeling
		 	6 rigid volume motion parameters
		 	voxelwise partial volume regressor
		 	linear detrending
		 	slicewise physio regressors (RETROICOR or PESTICA)

run_volmoco.tcsh [option] 

Required options:
 -dset_epi input     = 	input data is non-motion corrected 4D EPI images. 
                       	DO NOT apply any motion correction on input data.
                       	It is not recommended to apply physiologic noise correction on the input data
                       	Physiologoc noise components can be regressed out with -phyio option 
 -prefix output      = 	output filename
 
Optional:
 -volreg_base refvol = 	reference volume number, "MIN_ENORM" or "MIN_OUTLIER"
                       	"MIN_ENORM" provides the volume number with the minimal summation of absolute volume shift and its derivatives 
                       	"MIN_OUTLIER" provides [P.T will add]
                       	Defaulty is "0"
 -physio physiofile  = 	slicewise RETROICOR or PESTICA 1D file
 						identical to the option input of -slice_sm in 3dREMLfit
                       	1D file should include; (e.g. 2 regressors w/ 3 slices)
                       	bb[0] --> slice #0 matrix, regressor 0
                		bb[1] --> slice #0 matrix, regressor 1
                     	bb[2] --> slice #1 matrix, regressor 0
                     	bb[3] --> slice #1 matrix, regressor 1
                     	bb[4] --> slice #2 matrix, regressor 0
                     	bb[5] --> slice #2 matrix, regressor 1  
 -workdir  directory = intermediate output data will be generated in the defined directory.\
 
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
