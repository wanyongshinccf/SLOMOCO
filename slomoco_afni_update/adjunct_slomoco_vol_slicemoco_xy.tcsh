#!/bin/tcsh

set version   = "0.0";  set rev_dat   = "Sep 20, 2023"
# + tcsh version of Wanyong Shin's 'run_correction_vol_slicemocoxy_afni.sh'
#
# ----------------------------------------------------------------

set this_prog = "adj_vol_slicemoco"
#set tpname    = "${this_prog:gas///}"
set here      = $PWD

# ----------------------- set defaults --------------------------

set prefix  = ""

set odir    = $here
set opref   = ""

set wdir    = ""

# --------------------- inputs --------------------

set epi      = ""   # base 3D+time EPI dataset to use to perform corrections
set unsatepi = ""   # unsaturated EPI image, usually Scout_gdc.nii.gz
set epi_mask = ""   # (opt) mask dset name

set moco_meth   = ""  # req, one of: A, W
set file_tshift = ""  # req, *.1D file

set vr_base     = ""  # opt, for setting vr_idx
set vr_idx      = 0   # opt, but sh/could come from MIN_OUTLIER in upper scr
set vr_mat      = ""  # req, need matrix from full volume volreg

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

    # --------- required

    else if ( "$argv[$ac]" == "-dset_base" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_mask" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_mask = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-moco_meth" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set moco_meth = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-volreg_base" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set vr_base = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-volreg_mat" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set vr_mat = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-file_tshift" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set file_tshift = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-prefix" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set prefix = "$argv[$ac]"
        set opref  = `basename "$argv[$ac]"`
        set odir   = `dirname  "$argv[$ac]"`

    # --------- opt

    else if ( "$argv[$ac]" == "-workdir" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set wdir = "$argv[$ac]"

        set tf = `python -c "print('/' in '${wdir}')"`
        if ( "${tf}" == "True" ) then
            echo ""
            echo "** ERROR: '-workdir ..' is a name only, no '/' allowed"
            echo ""
            goto BAD_EXIT
        endif

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
        -prefix "${owdir}/base_00"
endif

# ----- mask is required input

if ( "${epi_mask}" == "" ) then
    echo "** ERROR: must input a mask with '-dset_mask ..'"
    goto BAD_EXIT
endif

# ---- check other expected dsets; make sure they are OK and grid matches

echo "++ Work on other input datasets"

# these lists must have same length: input filenames and wdir
# filenames, respectively
set all_dset = ( "${epi_mask}" )
set all_wlab = ( mask.nii.gz )

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

# ----- moco method has allowed value

# value can only be one of a short list
if ( ${moco_meth} != "A" && \
     ${moco_meth} != "W" ) then
    echo "** ERROR: bad moco method selected; must be one of: A, W."
    echo "   User provided: '${moco_meth}'"
    goto BAD_EXIT
else if ( ${moco_meth} == "A" ) then
    set moco_prog = 3dAllineate
else if ( ${moco_meth} == "W" ) then
    set moco_prog = 3dWarpDrive
endif

# ----- check tshift file was entered

if ( "${file_tshift}" == "" ) then
    echo "** ERROR: Must use '-file_tshift ..' to input a tshift file"
    goto BAD_EXIT
else 
    if ( ! -e "${file_tshift}" ) then
        echo "** ERROR: file_tshift does not exist: ${file_tshift}"
        goto BAD_EXIT
    endif

    # copy to wdir
    \cp "${file_tshift}" "${owdir}/tshiftfile.1D"

endif

# ----- volreg base

# at present, there is no MIN_OUTLIER at this level; assume upper
# script did so, if desired.
if ( 1 ) then
    # not be choice, but hope user entered an int
    set max_idx = `3dinfo -nvi "${epi}"`
    
    if ( `echo "${vr_base} > ${max_idx}" | bc` || \
         `echo "${vr_base} < 0" | bc` ) then
        echo "** ERROR: allowed volreg_base range is : [0, ${max_idx}]}"
        echo "   but the user's value is outside this: ${vr_base}"
        goto BAD_EXIT
    endif

    # just use that number
    set vr_idx = "${vr_base}"
endif

# ----- check volreg_mat was entered

if ( "${vr_mat}" == "" ) then
    echo "** ERROR: Must use '-volreg_mat ..' to input a volreg matrix"
    goto BAD_EXIT
else 
    if ( ! -e "${vr_mat}" ) then
        echo "** ERROR: volreg_mat does not exist: ${vr_mat}"
        goto BAD_EXIT
    endif

    # copy to wdir
    \cp "${vr_mat}" "${owdir}/volreg.aff12.1D"
    # ... along with inverse
    cat_matvec "${vr_mat}" -I > "${owdir}/volreg_INV.aff12.1D"
    # ... and a transposed ver
    1dtranspose "${vr_mat}" > "${owdir}/volreg.aff12.T.1D"
endif


# =======================================================================
# =========================== ** Main work ** ===========================

cat <<EOF

++ Start main ${this_prog} work

EOF

# move to wdir to do work
cd "${owdir}"

# ----- get orient and parfix info 

# create ...
adjunct_slomoco_get_orient.tcsh  base_00+orig.HEAD  text_parfix.txt

if ( $status ) then
    echo "** ERROR: could get dset orient"
    goto BAD_EXIT
endif

# ... and read back in and store
set parfixline = `cat text_parfix.txt`

# ----- define variables

set dims = `3dAttribute DATASET_DIMENSIONS base_00+orig.HEAD`
set tdim = `3dnvals base_00+orig.HEAD`
set zdim = ${dims[3]}                           # tcsh uses 1-based counting

echo "++ Num of z-dir slices : ${zdim}"
echo "   Num of time points  : ${tdim}"

# ----- calculate SMS factor from slice timing

set SLOMOCO_SLICE_TIMING = `cat tshiftfile.1D`
set SMSfactor            = 0

# count the number of zeros in slice timings to get SMS factor
# [PT] *** probably avoid strict equality in this, bc of floating point vals?
foreach tval ( ${SLOMOCO_SLICE_TIMING} )
    if ( `echo "${tval} == 0" | bc` ) then
        @ SMSfactor += 1
    endif
end

if ( "$SMSfactor" == "0" ) then
    echo "** ERROR: slice acquisition timing does not have any zeros"
    goto BAD_EXIT
else if ( "$SMSfactor" == "${zdim}" ) then
    echo "** ERROR: slice acquisition timing was shifted to ALL zeros"
    goto BAD_EXIT
else
    echo "++ Num of zeros in timing file (hence SMS factor): ${SMSfactor}"
endif

# ----- define more/useful quantities

# this first quantity apparently should be the integer part of the div
set zmbdim  = `echo "scale=0; ${zdim}/${SMSfactor}" | bc`
@   tcount  = ${tdim} - 1                      # is for 0-based subbrick sel
@   zcount  = ${zmbdim} - 1                    # is for 0-based slice sel
@   kcount  = ${zdim} - 1
@   MBcount = ${SMSfactor} - 1                 # this should keep '- 1'

# ----- synthesize static images

# one-step method to get constant 3D+t dataset, matching [vr_idx] vol
3dcalc                                       \
    -a      base_00+orig.HEAD                \
    -b      base_00+orig.HEAD"[${vr_idx}]"   \
    -expr   'b'                              \
    -prefix base_03_static                   \
    >& /dev/null

# one-step method to get constant 3D+t mask dataset
3dcalc                                       \
    -a      base_00+orig.HEAD                \
    -b      mask.nii.gz                      \
    -expr   'b'                              \
    -prefix base_03_mask                     \
    >& /dev/null

# ----- inject volume motion (and inv vol mot) on static dsets

# [PT] why cubic here, and not wsinc5?
3dAllineate                                  \
    -prefix         base_04_static_volmotinj \
    -1Dmatrix_apply volreg_inv.aff12.1D      \
    -source         base_03_static+orig.HEAD \
    -final          cubic                    \
    >& /dev/null

# [PT] really use cubic here? output mask won't be binary; but later,
# I see we put "step()" on it, so might be OK
3dAllineate                                  \
    -prefix         base_04_mask_volmotinj   \
    -1Dmatrix_apply volreg_inv.aff12.1D      \
    -source         base_03_mask+orig.HEAD   \
    -final          cubic                    \
    >& /dev/null

3dcalc                                            \
    -a       base_04_static_volmotinj+orig.HEAD   \
    -b       base_04_mask_volmotinj+orig.HEAD     \
    -expr    'a*step(b)'                          \
    -prefix  base_05_vol_wt_ts

# ----- normalize vol pv regressor

# [PT] isn't this just a blurry version of base_03?
3dAllineate                                  \
    -prefix         base_06_vol_pvreg        \
    -1Dmatrix_apply volreg.aff12.1D          \
    -source         base_04_static_volmotinj+orig.HEAD \
    -final          cubic                    \
    >& /dev/null

3dTstat                                      \
    -mean                                    \
    -prefix base_06_vol_pvreg_MEAN           \
    base_06_vol_pvreg+orig.HEAD              \
    >& /dev/null

3dTstat                                      \
    -stdev                                   \
    -prefix base_06_vol_pvreg_STD            \
    base_06_vol_pvreg+orig.HEAD              \
    >& /dev/null

3dcalc \
    -a base_06_vol_pvreg_MEAN+orig.HEAD      \
    -b base_06_vol_pvreg_STD+orig.HEAD       \
    -c mask.nii.gz                           \
    -d base_06_vol_pvreg+orig.HEAD           \
    -expr 'step(c)*(d-a)/b'                  \
    -prefix base_07_vol_pvreg_norm+orig.HEAD \
    >& /dev/null


# ----- define non-zero voxel threshold

set delta = `3dinfo -ad3 base_00+orig.HEAD`    # get abs of signed vox dims
set xdim  = ${delta[1]}                        # tcsh uses 1-based counting
set ydim  = ${delta[2]}

# now 5cm x 5cm is the minimal size of 2d image to attempt image registration.
set nspace_min = 2500
set nvox_min   = `echo "${nspace_min}/${xdim}/${ydim}" | bc`

echo "++ Setting nvox_min to (units: mm**2): $nvox_min"

# ---------------------------------------------------------------------------

# new starts

set total_start_time = `date +%s.%3N`

# loop over each subbrick: 0-based count
foreach t ( `seq 0 1 ${tcount}` )
    set ttt = `printf "%04d" $t`
    set start_time = `date +%s.%3N`

    # ----- select the reference volume
    3dcalc \
        -overwrite                            \
        -a         "base_04_static_volmotinj+orig.HEAD[$t]" \
        -expr      'a' \
        -prefix    __temp_vol_base  #\
        #>& /dev/null

    # orig/input dset 
    3dcalc \
        -overwrite                            \
        -a         "base_00+orig.HEAD[$t]"    \
        -expr      'a' \
        -prefix    __temp_vol_input #\
        #>& /dev/null

    # masked motion-shifted vol
    3dcalc \
        -overwrite                            \
        -a         "base_05_vol_wt_ts+orig.HEAD[$t]" \
        -expr      'a' \
        -prefix    __temp_vol_weight #\
        #>& /dev/null

    # ----- select single time point of 3dvolreg transformation matrix

    1d_tool.py                               \
        -overwrite                           \
        -infile   "volreg.aff12.T.1D[$t]"    \
        -write    rm.vol.col.aff12.1D 

    1dtranspose rm.vol.col.aff12.1D > rm.vol.aff12.1D 

    # loop over each z-slice: 0-based count
    foreach z ( `seq 0 1 ${zcount}` )
        set zzz   = `printf "%04d" $z`
        set bname = "motion.allineate.slicewise_inplane.z${zzz}.t${ttt}"
        set zsimults = ""
        set kstart   = 1

        # [PT] below, this appears to assume that 'mb' will only ever
        # be single digit. Are we *sure* about this?
        foreach mb ( `seq 0 1 ${MBcount}` )   # really starts at 0
            # update slice index
            set k = `echo "${mb} * ${zmbdim} + ${z}" | bc`
            set zsimults = "${zsimults} $k"   # updating+accumulating

            # [PT] maybe come back and zeropad these mb-based names?

            # split off each slice
            3dZcutup \
                -keep $k $k \
                -prefix __temp_slc_$mb \
                __temp_vol_input+orig.HEAD  #\
                #>& /dev/null

            3dZcutup \
                -keep $k $k \
                -prefix __temp_slc_base_$mb \
                __temp_vol_base+orig.HEAD #\
                #>& /dev/null

            3dZcutup \
                -keep $k $k \
                -prefix __temp_slc_weight_$mb \
                __temp_vol_weight+orig.HEAD  # \
                #>& /dev/null
        end  # end mb loop

        # [PT] not *sure* this if condition is needed?
        if ( `echo "${SMSfactor} > 1" | bc` ) then
            3dZcat \
                -overwrite \
                -prefix __temp_slc \
                __temp_slc_?+orig.HEAD 

            3dZcat \
                -overwrite \
                -prefix __temp_slc_base  \
                __temp_slc_base_?+orig.HEAD 
                
            3dZcat \
                -overwrite \
                -prefix __temp_slc_weight \
                __temp_slc_weight_?+orig.HEAD 
        else
            3dcopy \
                -overwrite \
                __temp_slc_0+orig.HEAD  \
                __temp_slc 

            3dcopy \
                -overwrite \
                __temp_slc_base_0+orig.HEAD  \
                __temp_slc_base 

            3dcopy \
                -overwrite \
                __temp_slc_weight_0+orig.HEAD  \
                __temp_slc_weight
        endif

        # clean a bit
        \rm -f  __temp_slc_?+orig.*         \
                __temp_slc_base_?+orig.*    \
                __temp_slc_weight_?+orig.* 

        # -----  get number of nonzero voxels (test below)
        set nvox_nz = `3dBrickStat -non-zero -count \
                            __temp_slc_weight+orig.HEAD`

        # ----- disp some info in first loop
        if ( "$t" == "1" ) then
            echo "++ Num slices to simultaneously analyze: ${zsimults}"
      
            if ( `echo "${nvox_nz} < ${nvox_min}" | bc` ) then
                echo "+* WARN: too few nonzero voxels      : ${nvox_nz}"
                echo "   Wanted to have at least this many : ${nvox_min}"
                echo "   Null ${moco_prog} matrix will be generated"
                echo "   You can modify nvox_min if necessary"
                echo "   (def area: ${nspace_min} mm**2)"
            endif
        else
            if ( "$z" == "1" ) then
                echo "++ Proc first slice of vol: ${t}"
            endif
        endif

        # ----- alignment

        if ( `echo "${nvox_nz} >= ${nvox_min}" | bc` ) then
            if ( "${moco_meth}" == "W" ) then
                # [PT] what cost should be used here? specify explicitly
                3dWarpDrive \
                    -overwrite \
                    -affine_general -cubic -final cubic -maxite 300 -thresh 0.005 \
                    -prefix        __temp_9999 \
                    -base          __temp_slc_base+orig.HEAD  \
                    -input         __temp_slc+orig.HEAD \
                    -weight        __temp_slc_weight+orig.HEAD \
                    -1Dfile        ${bname}.1D \
                    -1Dmatrix_save ${bname}.aff12.1D \
                    ${parfixline} \
                    >& /dev/null

                if ( $status ) then
                    echo "** ERROR: failed in $moco_metho alignment"
                    goto BAD_EXIT
                endif
            else if ( "${moco_meth}" == "A" ) then
                3dAllineate \
                    -overwrite \
                    -interp cubic -final cubic -cost ls -conv 0.005 -onepass \
                    -prefix        __temp_9999 \
                    -base          __temp_slc_base+orig.HEAD  \
                    -input         __temp_slc+orig.HEAD \
                    -weight        __temp_slc_weight+orig.HEAD \
                    -1Dfile        ${bname}.1D \
                    -1Dmatrix_save ${bname}.aff12.1D \
                    ${parfixline} \
                    >& /dev/null

                if ( $status ) then
                    echo "** ERROR: failed in $moco_metho alignment"
                    goto BAD_EXIT
                endif
            endif
        else
            # this is the null case: create null data and 1D files
            3dcalc \
                -overwrite \
                -a __temp_slc+orig \
                -expr 'a' \
                -prefix __temp_9999 \
                >& /dev/null

# NB: do *not* indent these cats
cat <<EOF > ${bname}.aff12.1D
# null 3dAllineate matrix
1 0 0 0 0 1 0 0 0 0 1 0
EOF

# [PT] what are the dollar signs doing here? **have removed for now**
cat <<EOF > ${bname}.1D
# null 3dAllineate/3dWarpDrive parameters:
#  x-shift  y-shift  z-shift z-angle  x-angle y-angle x-scale y-scale z-scale y/x-shear z/x-shear z/y-shear
0 0 0 0 0 0 1 1 1 0 0 0
EOF
        endif

        # -----  generate partial volume regressors, and apply

        cat_matvec ${bname}.aff12.1D    > rm.sli.aff12.1D
        cat_matvec ${bname}.aff12.1D -I > rm.sli.inv.aff12.1D

        3dAllineate \
            -overwrite \
            -prefix            __temp_slc_pvreg1 \
            -1Dmatrix_apply    rm.sli.inv.aff12.1D \
            -source            __temp_slc_base+orig.HEAD \
            -final linear \
            >& /dev/null

        3dAllineate \
            -overwrite \
            -prefix            __temp_slc_pvreg2 \
            -1Dmatrix_apply    rm.sli.aff12.1D \
            -source            __temp_slc_pvreg1+orig.HEAD \
            -final linear \
            >& /dev/null
    
        if ( -f __temp_9999+orig.HEAD ) then

            # ----- break down

            foreach mb ( `seq 0 1 ${MBcount}` )   # really starts at 0
                set k    = `echo "${mb} * ${zmbdim} + ${z}" | bc`
                set kstr = `printf %04d $k`

                3dZcutup \
                    -keep $mb $mb \
                    -prefix __temp_slc_mocoxy.z${kstr} \
                    __temp_9999+orig.HEAD  \
                    >& /dev/null
                3dZcutup \
                    -keep $mb $mb \
                    -prefix  __temp_slc_pvreg.z${kstr} \
                    __temp_slc_pvreg2+orig.HEAD  \
                    >& /dev/null
            end
        else
            echo "** ERROR: in ${this_prog}"
            echo "   Unexpected error: Welcome to the coding world."
            goto BAD_EXIT
        endif

        # clean
        
        \rm __temp_9999+orig.* __temp_slc_pvreg?+orig.* 
        \rm __temp_slc+orig.*  __temp_slc_base+orig.*   __temp_slc_weight+orig.*   

    end  # end of z loop

    if ( "$t" == "1" ) then
        set end_time = `date +%s.%3N`
        set elapsed  = `echo "scale=3; (${end_time} - ${start_time}/1.0" | bc`
        echo "++ Slicewise moco done in ${elapsed} sec per volume"
    endif

    # ----- stack up slice images to volume image
    3dZcat \
        -prefix __temp_vol_pv+orig \
        __temp_slc_pvreg.z????+orig.HEAD \
        >& /dev/null

    3dZcat \
        -prefix __temp_vol_mocoxy+orig \
        __temp_slc_mocoxy.z????+orig.HEAD \
        >& /dev/null

    # clean
    \rm __temp_slc_pvreg.z????+orig.* __temp_slc_mocoxy.z????+orig.*

    # ----- move volume image back to baseline
    
    3dAllineate \
        -overwrite \
        -prefix __temp_vol_pv.t${ttt} \
        -1Dmatrix_apply rm.vol.aff12.1D \
        -source __temp_vol_pv+orig.HEAD \
        -final cubic \
        >& /dev/null

    3dAllineate \
        -overwrite \
        -prefix __temp_vol_mocoxy.t${ttt} \
        -1Dmatrix_apply rm.vol.aff12.1D \
        -final cubic \
        -input __temp_vol_mocoxy+orig.HEAD \
        >& /dev/null

    \rm     __temp_vol_pv+orig.* __temp_vol_mocoxy+orig.*

end  # end of t loop

# ----- calc+report time taken
set elapsed = `echo "scale=3; (${end_time} - ${total_start_time}/1.0" | bc`
echo "++ Total slicewise moco done in ${elapsed} sec"


# **** ADD MORE PARTS



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
