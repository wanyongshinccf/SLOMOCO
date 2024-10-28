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

set epi        = ""   # base 3D+time EPI dataset to use to perform corrections
set epi_mask   = ""   # mask 3D+time images
set vr_idx     = 0
set prefix_vr  = ""
set prefix_pv  = "vol_pvreg"
set prefix_out = ""
set physiofile = ""
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
        set do_echo = "-echo"

    # --------- required

    else if ( "$argv[$ac]" == "-dset_epi" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-prefix_vr" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set prefix_vr = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-prefix_out" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set prefix_out = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_mask" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_mask = "$argv[$ac]"
       
    # --------- optional    

    else if ( "$argv[$ac]" == "-vr_idx" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set vr_idx = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-prefix_pv" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set prefix_pv = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-physio" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set physiofile = "$argv[$ac]"
    
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

if ( "${prefix_vr}" == "" ) then
    echo "** ERROR: need to provide output name with '-prefix_vr ..'"
    goto BAD_EXIT
endif

if ( "${prefix_out}" == "" ) then
    echo "** ERROR: need to provide output name with '-prefix_out ..'"
    goto BAD_EXIT
endif

if ( "${epi_mask}" == "" ) then
    echo "** ERROR: need to provide output name with '-epi_mask ..'"
    goto BAD_EXIT
endif


# =======================================================================
# =========================== ** Main work ** ===========================

cat <<EOF

++ Start main ${this_prog} work

EOF


# ----- step 1 voxelwise time-series PV regressor
# volreg output is also generated.
gen_vol_pvreg.tcsh              \
	-dset_epi  "${epi}"         \
    -dset_mask "${epi_mask}"    \
    -vr_idx    "${vr_idx}"      \
    -prefix_pv "${prefix_pv}"   \
    -prefix_vr "${prefix_vr}"       
    
if ( $status ) then
    goto BAD_EXIT
endif


# ----- step 2 second order 

# volmoco + 6 mopa + PV
# demean motion parameters
1d_tool.py -infile "${prefix_vr}".1D -demean -write mopa6.demean.1D -overwrite

3dDeconvolve                                                            \
    -input  "${epi}"                                                    \
    -mask   "${epi_mask}"                                               \
    -polort 1                                                           \
    -num_stimts 6                                                       \
    -stim_file 1 mopa6.demean.1D'[0]' -stim_label 1 mopa1 -stim_base 1 	\
    -stim_file 2 mopa6.demean.1D'[1]' -stim_label 2 mopa2 -stim_base 2 	\
    -stim_file 3 mopa6.demean.1D'[2]' -stim_label 3 mopa3 -stim_base 3 	\
    -stim_file 4 mopa6.demean.1D'[3]' -stim_label 4 mopa4 -stim_base 4 	\
    -stim_file 5 mopa6.demean.1D'[4]' -stim_label 5 mopa5 -stim_base 5 	\
    -stim_file 6 mopa6.demean.1D'[5]' -stim_label 6 mopa6 -stim_base 6 	\
    -x1D mopa6.demean.det.1D                                            \
    -x1D_stop -overwrite
    	  

if ( $physiofile == "" ) then
 	# 6 Vol-mopa + PV + linear detrending terms 
    3dREMLfit                       \
        -input  "${prefix_vr}"+orig	\
        -mask   "${epi_mask}"       \
        -matrix mopa6.demean.det.1D \
        -dsort  "${prefix_pv}"+orig \
        -Oerrts errt.mopa6.pvreg    \
        -overwrite                  

else
	echo " 8 regressors for RETROICOR or 5 regressors for PESTICA" |& tee -a ../$histfile

	3dMREMLfit                      \
        -input  "${prefix_vr}"+orig	\
        -mask   "${epi_mask}"       \
        -matrix mopa6.demean.det.1D \
        -dsort  "${prefix_pv}"+orig \
        -Oerrts errt.mopa6.pvreg    \
        -slibase_sm $physiofile		\
        -overwrite                  

endif
 
# adding back the tissue contrast
3dcalc                              \
    -a      errt.mopa6.pvreg+orig   \
    -b      epi_base_mean+orig      \
    -expr   'a+b'                   \
    -prefix ${prefix_out}           \
    -overwrite

\rm -f errt.*

if ( $DO_CLEAN == 1 ) then
    echo "\n+* Removing temporary axialization working dir: '$wdir'\n"

    # ***** clean
    # rm -rf 

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
 -compact            = this option will delete the large size of files under working directory
	  
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
