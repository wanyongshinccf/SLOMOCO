#!/bin/tcsh

set version   = "0.0";  set rev_dat   = "May 30, 2024"
# + tcsh version of Wanyong Shin's voxelwise PV regressor'
#
# ----------------------------------------------------------------

set this_prog_full = "gen_vol_pvreg.tcsh"
set this_prog = "gen_pvreg"
#set tpname    = "${this_prog:gas///}"
set here      = $PWD

# ----------------------- set defaults --------------------------

set prefix  = ""

set odir    = $here
set opref   = ""

# --------------------- inputs --------------------

set epi      = ""   # base 3D+time EPI dataset to use to perform corrections
set epi_mask = ""   # mask 3D+time images
set vr_idx = 0
set prefix_vr = ""
set prefix_pv = "vol_pvreg"

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

    else if ( "$argv[$ac]" == "-prefix_pv" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set prefix_pv = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-vr_idx" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set vr_idx = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_mask" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_mask = "$argv[$ac]"
        set maskflag = 1
        
    # --------- optional    
    
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
 
# calc 6 DF (rigid) alignment pars
3dvolreg                                                                 \
    -verbose                                                             \
    -prefix         "${prefix_vr}"                                       \
    -dfile          "${prefix_vr}".txt                                   \
    -1Dfile         "${prefix_vr}".1D                                    \
    -1Dmatrix_save  "${prefix_vr}".aff12.1D                              \
    -maxdisp1D      "${prefix_vr}".maxdisp.1D                            \
    -base           "${vr_idx}"                                          \
    -zpad           2                                                    \
    -maxite         60                                                   \
    -x_thresh       0.005                                                \
    -rot_thresh     0.008                                                \
    -heptic                                                              \
    -overwrite                                                           \
    ${epi}

# inverse affine matrix
cat_matvec "${prefix_vr}".aff12.1D -I > "${prefix_vr}"_INV.aff12.1D

# generating motsim
3dTstat	-mean                      \
     	-prefix epi_base_mean+orig \
     	-overwrite                 \
     	"${prefix_vr}"+orig 

# concatenate images
echo "++ Generating MotSim dataset; running 3dcalc; no msg ++"
set tdim = `3dnvals ${epi}`
# set t = 0
# while ( $t < $tdim ) 
#  set tttt   = `printf "%04d" $t`
#  3dcalc -a epi_base_mean+orig 				\
#        -expr 'a'              				\
#        -prefix ___temp_static.${tttt}.nii >& /dev/null
#  3dcalc -a ${epi_mask}						\
#        -expr 'a'              				\
#        -prefix ___temp_mask.${tttt}.nii >& /dev/null
#  @ t++ 
# end

# # concatenate mask and static image
# 3dTcat -prefix ___temp_mask.nii   ___temp_mask.????.nii   
# 3dTcat -prefix ___temp_static.nii ___temp_static.????.nii  

# clean up
# \rm -f ___temp_static.????.nii ___temp_mask.????.nii 

# Make 1D file of $tdim zeros for indexing (A.N)
echo $tdim
seq 1 ${tdim} | xargs -I {} echo 0 > __idx.1D
3dTcat -prefix ___temp_static.nii  epi_base_mean+orig'[1dcat __idx.1D]'
3dTcat -prefix ___temp_mask.nii    ${epi_mask}'[1dcat __idx.1D]'
\rm -f __idx.1D

# inject inverse volume motion on static images
3dAllineate                                   \
  -prefix epi_motsim_mask4d                   \
  -1Dmatrix_apply "${prefix_vr}"_INV.aff12.1D \
  -source ___temp_mask.nii                    \
  -final NN                                   \
  -overwrite
3dAllineate                                   \
  -prefix epi_motsim                          \
  -1Dmatrix_apply "${prefix_vr}"_INV.aff12.1D \
  -source ___temp_static.nii                  \
  -final cubic                                \
  -float                                      \
  -overwrite 
3dAllineate                                   \
  -prefix ___temp_vol_pvreg.nii               \
  -1Dmatrix_apply "${prefix_vr}".aff12.1D     \
  -source epi_motsim+orig                     \
  -final cubic                                \
  -overwrite

# mask (A.N) 
# 3dcalc -a ___temp_mask4d.nii         \
#        -expr 'step(a)'               \
#        -prefix epi_motsim_mask4d     \
#        -nscale                       \
#       -overwrite

# normalize vol pv regressor  
3dTstat -mean  -prefix ___temp_vol_pvreg_mean.nii ___temp_vol_pvreg.nii 
3dTstat -stdev -prefix ___temp_vol_pvreg_std.nii  ___temp_vol_pvreg.nii  
3dcalc -a ___temp_vol_pvreg_mean.nii   \
       -b ___temp_vol_pvreg_std.nii    \
       -c ___temp_mask.nii             \
       -d ___temp_vol_pvreg.nii        \
       -expr 'step(b)*step(c)*(d-a)/b' \
       -prefix "${prefix_pv}"          \
       -overwrite
# \rm -f ___temp* 

# copy header
3drefit -saveatr -atrcopy ${epi} TAXIS_NUMS   "${prefix_vr}"+orig 
# 3drefit -saveatr -atrcopy ${epi} TAXIS_FLOATS "${prefix_vr}"+orig 

# add info
3dNotes -h "Time series volume motion partial volume regressor"   "${prefix_vr}"+orig

# Removing unnecessary files
if ( $DO_CLEAN == 1 ) then
    echo "+* Removing temporary image files "
    echo "+* DO NOT DELETE motin 1D files in working dir "
    echo "+* 1D files will be required to generate slice motion nuisance regressor " 
    \rm -f epi_base_mean* epi_motsim.*
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
