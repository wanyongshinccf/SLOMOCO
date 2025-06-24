#!/bin/tcsh

# set version   = "0.0";  set rev_dat   = "May 30, 2024"
# + tcsh version of Wanyong Shin's voxelwise PV regressor'
# set version   = "1.0";  set rev_dat   = "Dec 20, 2024"
# + Absolute path is available
# set version   = "2.0";  set rev_dat   = "June 23, 2025"
# HCP pipeline compatitablity - reference (scout) scan option
# ----------------------------------------------------------------

set this_prog_full = "gen_vol_pvreg.tcsh"
set this_prog = "gen_pvreg"
#set tpname    = "${this_prog:gas///}"
set cdir      = $PWD

# ----------------------- set defaults --------------------------

set prefix  = ""
set odir    = $cdir
set opref   = ""

# --------------------- inputs --------------------

set epi         = ""   # base 3D+time EPI dataset to use to perform corrections
set epi_mask    = ""   # mask 3D+time images
set vr_idx      = -1
set epi_base    = ""   # reference (scout) scan (HCP)
set prefix_vr   = ""
set prefix_pv   = "vol_pvreg"

set DO_CLEAN = 0                       # default: keep working dir


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

    else if ( "$argv[$ac]" == "-prefix_pv" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set prefix_pv = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_base" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_base = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_mask" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_mask = "$argv[$ac]"
        set maskflag = 1
        
    # --------- optional    
    else if ( "$argv[$ac]" == "-vr_idx" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set vr_idx = "$argv[$ac]"

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

# conflict (HCP)
if ( $epi_base != "" ) then
    set basestr = "-base $epi_base"
else if ( $vr_idx != "-1" ) then
    set basestr = "-base ${vr_idx}"
else
    echo "Error: both epi_base and vr_idx are provided"
    exit
endif
echo $basestr

# handle the file name
set prefix = "${prefix_vr:r}"
set postfix = "${prefix_vr:e}"
if ( $postfix == "" ) then # xxx+orig format (witout HEAD)
    set prefix_vr_nosuffix = "${prefix_vr}"
else if ( $postfix == "gz" ) then # xxx.nii.gz or xxx+orig.BRIK.gz
    set prefix_vr_nosuffix = "${prefix_vr:r:r}"
else if ( $postfix == "nii" ) then # xxx.nii
    set prefix_vr_nosuffix = "${prefix_vr:r}"
else # xxx.yyy+orig
    set prefix_vr_nosuffix = `echo $prefix_vr | sed 's/\+orig$//'`
endif

# do work 
# calc 6 DF (rigid) alignment pars
3dvolreg                                                                \
    -verbose                                                            \
    -prefix         "${prefix_vr}"                                      \
    -dfile          "${prefix_vr_nosuffix}".txt                         \
    -1Dfile         "${prefix_vr_nosuffix}".1D                          \
    -1Dmatrix_save  "${prefix_vr_nosuffix}".aff12.1D                    \
    -maxdisp1D      "${prefix_vr_nosuffix}".maxdisp.1D                  \
    $basestr                                                            \
    -zpad           2                                                   \
    -maxite         60                                                  \
    -x_thresh       0.005                                               \
    -rot_thresh     0.008                                               \
    -heptic                                                             \
    -overwrite                                                          \
    ${epi}

# inverse affine matrix
cat_matvec "${prefix_vr_nosuffix}".aff12.1D -I > "${prefix_vr_nosuffix}"_INV.aff12.1D

# generating motsim
3dTstat	-mean                      \
     	-prefix epi_base_mean.nii \
     	-overwrite                 \
     	"${prefix_vr}" 


# concatenate images
echo "++ Generating MotSim dataset; running 3dcalc; no msg ++"
set tdim = `3dnvals ${epi}`

# clean up
\rm -f ___temp_static.nii ___temp_mask.nii 

# Make 1D file of $tdim zeros for indexing (A.N)
seq 1 ${tdim} | xargs -I {} echo 0 > __idx.1D
3dTcat -prefix ___temp_static.nii  epi_base_mean.nii'[1dcat __idx.1D]'
3dTcat -prefix ___temp_mask.nii    ${epi_mask}'[1dcat __idx.1D]'
rm -f __idx.1D

# inject inverse volume motion on static images
3dAllineate                                     \
    -prefix epi_motsim_mask4d.nii               \
    -1Dmatrix_apply "${prefix_vr_nosuffix}"_INV.aff12.1D \
    -source ___temp_mask.nii                    \
    -final NN                                   \
    -overwrite
3dAllineate                                     \
    -prefix epi_motsim.nii                      \
    -1Dmatrix_apply "${prefix_vr_nosuffix}"_INV.aff12.1D \
    -source ___temp_static.nii                  \
    -final cubic                                \
    -float                                      \
    -overwrite 
3dAllineate                                     \
    -prefix ___temp_vol_pvreg.nii               \
    -1Dmatrix_apply "${prefix_vr_nosuffix}".aff12.1D     \
    -source epi_motsim.nii                      \
    -final cubic                                \
    -overwrite

# mask (A.N) 
# 3dcalc -a ___temp_mask4d.nii         \
#        -expr 'step(a)'               \
#        -prefix epi_motsim_mask4d     \
#        -nscale                       \
#       -overwrite

# normalize vol pv regressor  
3dTstat                                 \
    -mean                               \
    -prefix ___temp_vol_pvreg_mean.nii  \
    ___temp_vol_pvreg.nii               \
    -overwrite

3dTstat                                 \
    -stdev                              \
    -prefix ___temp_vol_pvreg_std.nii   \
    ___temp_vol_pvreg.nii               \
    -overwrite

3dcalc                              \
    -a ___temp_vol_pvreg_mean.nii   \
    -b ___temp_vol_pvreg_std.nii    \
    -c ___temp_mask.nii             \
    -d ___temp_vol_pvreg.nii        \
    -expr 'step(b)*step(c)*(d-a)/b' \
    -prefix "${prefix_pv}"          \
    -overwrite
\rm -f ___temp* 

# copy header
3drefit -saveatr -atrcopy ${epi} TAXIS_NUMS   "${prefix_vr}" 
# 3drefit -saveatr -atrcopy ${epi} TAXIS_FLOATS "${prefix_vr}"+orig 

# add info
3dNotes -h "Time series volume motion partial volume regressor"   "${prefix_vr}"

# Removing unnecessary files
if ( $DO_CLEAN == 1 ) then
    echo "+* Removing temporary image files "
    echo "+* DO NOT DELETE motin 1D files in working dir "
    echo "+* 1D files will be required to generate slice motion nuisance regressor " 
    \rm -f epi_base_mean* 
        # ***** clean

else
    echo "++ NOT removing temporary axialization files"
endif

echo ""
echo "++ DONE.  Finished generating voxelwise PV regressor:"
echo ""

goto GOOD_EXIT

# ========================================================================
# ========================================================================

SHOW_HELP:
cat << EOF
-------------------------------------------------------------------------

Voxelwise partial volume regressor
Time sereries of motion nuisance regresors is generated based on 3d rigid 
volume motion
Citation: Wanyong Shin and Mark J. Lowe, "Effectove removal of the residual 
head motion artifact after motion correction in fMRI data", International 
Society of Magnetic Resonance in Medicine, 2023 #1821

EOF

# ----------------------------------------------------------------------


BAD_EXIT:
    exit 1

GOOD_EXIT:
    exit 0
