#!/bin/tcsh

set epi = ""
set epi_mask = ""
set prefix_vr = ""
set prefix_pv = "vol_pvreg"
set refvol = 0
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
        set refvol = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_mask" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_mask = "$argv[$ac]"
        set maskflag = 1
        
    else
        echo ""
        echo "** ERROR: unexpected option #$ac = '$argv[$ac]'"
        echo ""
        goto BAD_EXIT
        
    endif
    @ ac += 1
end

echo $epi
# calc 6 DF (rigid) alignment pars
3dvolreg                                                                 \
    -verbose                                                             \
    -prefix         "${prefix_vr}"                                       \
    -dfile          "${prefix_vr}".txt                                   \
    -1Dfile         "${prefix_vr}".1D                                    \
    -1Dmatrix_save  "${prefix_vr}".aff12.1D                              \
    -maxdisp1D      "${prefix_vr}".maxdisp.1D                            \
    -base           "${refvol}"                                          \
    -zpad           2                                                    \
    -maxite         60                                                   \
    -x_thresh       0.005                                                \
    -rot_thresh     0.008                                                \
    -heptic                                                              \
    ${epi}

# inverse affine matrix
cat_matvec "${prefix_vr}".aff12.1D -I > "${prefix_vr}"_INV.aff12.1D

# generating motsim
set tdim = `3dnvals ${epi}`
set t = 0
while ( $t < $tdim ) 
  set tttt   = `printf "%04d" $t`
  3dcalc -a ${epi}'[0]' -expr 'a' -prefix ___temp_static.${tttt}+orig >& /dev/null
  3dcalc -a ${epi_mask} -expr 'a' -prefix ___temp_mask.${tttt}+orig  >& /dev/null
  @ t++ 
end

# concatenate mask and static image
3dTcat -prefix ___temp_mask+orig   ___temp_mask.????+orig.HEAD   >& /dev/null
3dTcat -prefix ___temp_static+orig ___temp_static.????+orig.HEAD  >& /dev/null

# clean up
rm -f ___temp_static.* ___temp_mask.*

# inject inverse volume motion on static images
3dAllineate                                  \
  -prefix ___temp_mask4d+orig          \
  -1Dmatrix_apply "${prefix_vr}"_INV.aff12.1D \
  -source ___temp_mask+orig                  \
  -final NN 
3dAllineate                                  \
  -prefix epi_motsim+orig                 \
  -1Dmatrix_apply "${prefix_vr}".aff12.1D \
  -source ___temp_static+orig                \
  -final cubic 
3dAllineate \
  -prefix ___temp_vol_pvreg+orig            \
  -1Dmatrix_apply "${prefix_vr}".aff12.1D    \
  -source epi_motsim+orig                \
  -final cubic 

# mask 
3dcalc -a ___temp_mask4d+orig -expr 'step(a)' -prefix epi_motsim_mask4d+orig -nscale        

# normalize vol pv regressor  
3dTstat -mean  -prefix ___temp_vol_pvreg_mean ___temp_vol_pvreg+orig 
3dTstat -stdev -prefix ___temp_vol_pvreg_std  ___temp_vol_pvreg+orig  
3dcalc -a ___temp_vol_pvreg_mean+orig          \
       -b ___temp_vol_pvreg_std+orig           \
       -c ${epi_mask}                          \
       -d ___temp_vol_pvreg+orig               \
       -expr 'step(b)*step(c)*(d-a)/b*step(b)' \
       -prefix "${prefix_pv}"
rm  ___temp* 

# copy header
3drefit -saveatr -atrcopy ${epi} TAXIS_NUMS   "${prefix_vr}"+orig 
3drefit -saveatr -atrcopy ${epi} TAXIS_FLOATS "${prefix_vr}"+orig 

