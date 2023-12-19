#!/bin/tcsh

set version   = "0.0";  set rev_dat   = "Sep 20, 2023"
# + tcsh version of Wanyong Shin's 'run_correction_vol_slicemocoxy_afni.sh'
#
# ----------------------------------------------------------------

set this_prog_full = "adjunct_slomoco_vol_slicemoco_xy.tcsh"
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
set refvol   = ""   # reference 3D+time images
set epi_mask = ""   # mask 3D+time images

set moco_meth   = ""  # req, one of: A, W
set file_tshift = ""  # req, *.1D file
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

    else if ( "$argv[$ac]" == "-dset_epi" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_base" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set refvol = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-dset_mask" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set epi_mask = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-moco_meth" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set moco_meth = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-volreg_mat" ) then
        if ( $ac >= $#argv ) goto FAIL_MISSING_ARG
        @ ac += 1
        set vr_mat = "$argv[$ac]"

    else if ( "$argv[$ac]" == "-tfile" ) then
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
        -prefix "${owdir}/epi_00" \
        -overwrite
endif

echo "++ Work on reference volume datasets"

if ( "${refvol}" == "" ) then
    echo "** ERROR: need to provide EPI dataset with '-dset_epi ..'"
    goto BAD_EXIT
else
    # verify dset is OK to read
    3dinfo "${refvol}"  >& /dev/null
    if ( ${status} ) then
        echo "** ERROR: cannot read/open dset: ${refvol}"
        goto BAD_EXIT
    endif

    # must have +orig space for input EPI
    set av_space = `3dinfo -av_space "${refvol}" `
    if ( "${av_space}" != "+orig" ) then
        echo "** ERROR: input EPI must have +orig av_space, not: ${av_space}"
        goto BAD_EXIT
    endif

    # copy to wdir
    3dcalc \
        -a "${refvol}" \
        -expr 'a'   \
        -prefix "${owdir}/epi_01_refvol" \
        -overwrite
endif

# ----- mask is required input
# new update - 3D+t mask improves the result better, required. (W.S)
if ( "${epi_mask}" == "" ) then
    echo "** ERROR: must input a mask with '-dset_mask ..'"
    goto BAD_EXIT
else
    # verify dset is OK to read
    3dinfo "${epi_mask}"  >& /dev/null
    if ( ${status} ) then
        echo "** ERROR: cannot read/open dset: ${epi_mask}"
        goto BAD_EXIT
    endif

    # must have +orig space for input EPI
    set av_space = `3dinfo -av_space "${epi_mask}" `
    if ( "${av_space}" != "+orig" ) then
        echo "** ERROR: input EPI must have +orig av_space, not: ${av_space}"
        goto BAD_EXIT
    endif

    # copy to wdir
    3dcalc \
        -a "${epi_mask}" \
        -expr 'a'   \
        -prefix "${owdir}/epi_00_mask" \
        -overwrite
endif

# ---- check other expected dsets; make sure they are OK and grid matches

echo "++ Work on other input datasets"


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

echo " ${moco_prog} runs for inplane motion correction "

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
adjunct_slomoco_get_orient.tcsh  epi_00+orig.HEAD  text_parfix.txt

if ( $status ) then
    echo "** ERROR: could get dset orient"
    goto BAD_EXIT
endif

# ... and read back in and store
set parfixline = `cat text_parfix.txt`

# ----- define variables

set dims = `3dAttribute DATASET_DIMENSIONS epi_00+orig.HEAD`
set tdim = `3dnvals epi_00+orig.HEAD`
set zdim = ${dims[3]}                           # tcsh uses 1-based counting

echo "++ Num of z-dir slices : ${zdim}"
echo "   Num of time points  : ${tdim}"

# ----- calculate SMS factor from slice timing

set SLOMOCO_SLICE_TIMING = `cat tshiftfile.1D`
set SMSfactor            = 0

# count the number of zeros in slice timings to get SMS factor
# [PT] *** probably avoid strict equality in this, bc of floating point vals?
# [WS] Paul, are you talking about e.g. 0.000 ?
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

# ----- define non-zero voxel threshold

set delta = `3dinfo -ad3 epi_00+orig.HEAD`    # get abs of signed vox dims
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
        -a         "epi_01_refvol+orig.HEAD[$t]" \
        -expr      'a' \
        -prefix    __temp_vol_base  \
        >& /dev/null

    # orig/input dset 
    3dcalc \
        -overwrite                            \
        -a         "epi_00+orig.HEAD[$t]"    \
        -expr      'a' \
        -prefix    __temp_vol_input \
        >& /dev/null

    # mask
    3dcalc \
        -overwrite                            \
        -a         "epi_00_mask+orig.HEAD[$t]" \
        -expr      'a' \
        -prefix    __temp_vol_mask \
        >& /dev/null

   # masked motion-shifted vol
    3dcalc \
        -overwrite                            \
        -a         __temp_vol_base+orig \
        -b         __temp_vol_mask+orig \
        -expr      'a*step(b)' \
        -prefix    __temp_vol_weight \
        >& /dev/null

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
        # [W.S] maximum MB number in the sequence is 8 (if my rusty memory is correct)
        foreach mb ( `seq 0 1 ${MBcount}` )   # really starts at 0
            # update slice index
            set k = `echo "${mb} * ${zmbdim} + ${z}" | bc`
            set zsimults = "${zsimults} $k"   # updating+accumulating

            # [PT] maybe come back and zeropad these mb-based names?
            # [WS] I am okay to zeropad MB number for safety
            # split off each slice
            3dZcutup \
                -keep $k $k \
                -prefix __temp_slc_$mb \
                __temp_vol_input+orig.HEAD  \
                >& /dev/null

            3dZcutup \
                -keep $k $k \
                -prefix __temp_slc_base_$mb \
                __temp_vol_base+orig.HEAD \
                >& /dev/null

            3dZcutup \
                -keep $k $k \
                -prefix __temp_slc_weight_$mb \
                __temp_vol_weight+orig.HEAD   \
                >& /dev/null
        end  # end mb loop

        # [PT] not *sure* this if condition is needed?
        # [WS] 3dZcat does not allow runnng single input,
        # for example, 3dZcat -prefix test test1 -> error
        if ( `echo "${SMSfactor} > 1" | bc` ) then
            3dZcat \
                -overwrite \
                -prefix __temp_slc \
                __temp_slc_?+orig.HEAD \
                >& /dev/null

            3dZcat \
                -overwrite \
                -prefix __temp_slc_base  \
                __temp_slc_base_?+orig.HEAD \
                >& /dev/null
                
            3dZcat \
                -overwrite \
                -prefix __temp_slc_weight \
                __temp_slc_weight_?+orig.HEAD \
                >& /dev/null
        else
            3dcopy \
                -overwrite \
                __temp_slc_0+orig.HEAD  \
                __temp_slc \
                >& /dev/null                

            3dcopy \
                -overwrite \
                __temp_slc_base_0+orig.HEAD  \
                __temp_slc_base \
                >& /dev/null

            3dcopy \
                -overwrite \
                __temp_slc_weight_0+orig.HEAD  \
                __temp_slc_weight \
                >& /dev/null
        endif

        # clean a bit
        \rm -f  __temp_slc_?+orig.*         \
                __temp_slc_base_?+orig.*    \
                __temp_slc_weight_?+orig.* 

        # -----  get number of nonzero voxels (test below)
        set nvox_nz = `3dBrickStat -non-zero -count \
                            __temp_slc_weight+orig.HEAD`

        # ----- disp some info in first loop
       
        
        if ( "$z" == "0" ) then
	    echo "++ Proc first slice of vol: ${t}"
        endif

	if ( "$t" == "0" ) then
           echo "++ Num slices to simultaneously analyze: ${zsimults}"
        endif
        
        if ( `echo "${nvox_nz} < ${nvox_min}" | bc` ) then
            echo "+* WARN: too few nonzero voxels      : ${nvox_nz} at ${zsimults} slice(s)"
            if ( "$t" == "1" ) then
              echo "   Wanted to have at least this many : ${nvox_min}"
              echo "   Null ${moco_prog} matrix will be generated"
              echo "   You can modify nvox_min if necessary"
              echo "   (def area: ${nspace_min} mm**2)"
            endif
        endif

        # ----- alignment

        if ( `echo "${nvox_nz} >= ${nvox_min}" | bc` ) then
            if ( "${moco_meth}" == "W" ) then
                # [PT] what cost should be used here? specify explicitly
                $AFNI_SLOMOCO_DIR/3dWarpDrive \
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
                    echo "** ERROR: failed in $moco_meth alignment"
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
        set elapsed  = `echo "scale=3; (${end_time} - ${start_time})/1.0" | bc`
        echo "++ Slicewise moco done in ${elapsed} sec per volume"
    endif

    # ----- stack up slice images to volume image
    3dZcat \
        -prefix __temp_vol_mocoxy+orig \
        __temp_slc_mocoxy.z????+orig.HEAD \
        >& /dev/null

    # clean
    \rm  __temp_slc_mocoxy.z????+orig.*

    # ----- move volume image back to baseline
    3dAllineate \
        -overwrite \
        -prefix __temp_vol_mocoxy.t${ttt} \
        -1Dmatrix_apply rm.vol.aff12.1D \
        -final cubic \
        -input __temp_vol_mocoxy+orig.HEAD \
        >& /dev/null

    \rm     __temp_vol_pv+orig.* __temp_vol_mocoxy+orig.*

end  # end of t loop

set end_time = `date +%s.%3N`
set elapsed  = `echo "scale=3; (${end_time} - ${total_start_time})/1.0" | bc`
echo "++ Slicewise moco done in ${elapsed} sec"

# ----- concatenate outputs

3dTcat \
    -prefix epi_02_vol_mocoxy  \
    __temp_vol_mocoxy.t????+orig.HEAD  

# ----- update header info in new dsets

set all_atr  = ( TAXIS_NUMS TAXIS_FLOATS )
set all_dset = ( epi_02_vol_mocoxy+orig.HEAD  )

foreach dset ( ${all_dset} )
    # copy over and save t-axis nums and floats to new dsets
    foreach atr ( ${all_atr} ) 
        3drefit -saveatr -atrcopy epi_00+orig.HEAD ${atr} ${dset}
    end

    # add slice timing info to new dsets
    3drefit -Tslices `cat tshiftfile.1D` ${dset}
end

# add notes
3dNotes -h "${this_prog_full} ${argv}"   epi_02_vol_mocoxy+orig.HEAD

# ----- *** write primary output to main output location ***

3dcopy     \
    epi_02_vol_mocoxy+orig.HEAD \
    ../${opref}

# clean up
\rm -f /__temp_vol_pv.t????+orig.* \
     __temp_vol_mocoxy.t????+orig.*

# --------------------------------------------------------------------------
# let's play with motion parameters here 

# ----- make motion parameter time series file

# start of file name and comment
set mot_inplane_mat = motion.allineate.slicewise_inplane.header.1D
cat <<EOF >> ${mot_inplane_mat}
# null 3dAllineate/3dWarpdrive parameters:
#  x-shift  y-shift  z-shift z-angle  x-angle y-angle x-scale y-scale z-scale y/x-shear z/x-shear z/y-shear
EOF

# loop over each z-slice: 0-based count
foreach z ( `seq 0 1 ${zcount}` )
    set zzz = `printf "%04d" $z`

    # flip motion param 1D file for concatenation;
    # loop over each subbrick: 0-based count
    foreach t ( `seq 0 1 ${tcount}` )
        set ttt   = `printf "%04d" $t`
        set bname = "motion.allineate.slicewise_inplane.z${zzz}.t${ttt}"

        # copy to temp file
        1dcat ${bname}.1D > rm.inplane.add.1D
        # transpose
        1dtranspose rm.inplane.add.1D > rm.inplane.add.col.t${ttt}.1D

        # copy
        1dcat ${bname}.aff12.1D > rm.inplane.add.1D
        # transpose 
        1dtranspose rm.inplane.add.1D > rm.inplane.add.col.t${ttt}.aff12.1D
    end  # end of t loop

    # ----- concatenate rigid motion (6 par)

    # NB: 3dAllineate's 1D file is: x-/y-/z-shift, z-/x-/y-rotation, ...,
    # while 3dvolreg's 1D file is : z-/x-/y-rot, z-/x-/y-shift, and the shift
    # direction is flipped.
    # We store the inplane 1D file from 3dWarpDrive (3dAllineate),
    # while out-of-plane motion from 3dvolreg motion params are used
    # as regressors so that direction does not matter. The flipped
    # direction of x-/y-/z-shift and 3dAllineate's convention will be
    # handled in pre_slicemoco_regressor.sh and qa_slomoco.m

    # concatenate over time (1D file)
    1dcat rm.inplane.add.col.t????.1D \
        > rm.motion.allineate.slicewise_inplane.col.1D
    # ... and transpose from column
    1dtranspose rm.motion.allineate.slicewise_inplane.col.1D \
        > rm.motion.allineate.slicewise_inplane.1D
    # dump to text file
    # [PT] put letter 'z' before zzz variable here, like done above?
    cat ${mot_inplane_mat} \
        rm.motion.allineate.slicewise_inplane.1D \
        > motion.allineate.slicewise_inplane.${zzz}.1D 

    # concatenate over time (aff12 1D file)
    1dcat rm.inplane.add.col.t????.aff12.1D \
        > rm.motion.allineate.slicewise_inplane.col.aff12.1D
    # ... and transpose from column
    1dtranspose rm.motion.allineate.slicewise_inplane.col.aff12.1D \
        > rm.motion.allineate.slicewise_inplane.aff12.1D
    # format nicely for text file
    # [PT] put letter 'z' before zzz variable here, like done above?
    1d_tool.py \
        -overwrite \
        -infile rm.motion.allineate.slicewise_inplane.aff12.1D \
        -write motion.allineate.slicewise_inplane.${zzz}.aff12.1D
              
    # clean up
    \rm -f rm.*.1D

end  # end of z loop

# another clean up
\rm -f __temp_* motion.allineate.slicewise_inplane.z????.t????*1D  
# [PT] will this clean be necessary, given one a few lines up?
####\rm -f rm.*aff12.1D 

# ---------------------------------------------------------------------

# move out of wdir to the odir
cd ..
set whereout = $PWD

if ( $DO_CLEAN == 1 ) then
    echo "+* Removing temporary image files in working dir: '$wdir'"
    echo "+* DO NOT DELETE motin 1D files in working dir "
    echo "+* 1D files will be required to generate slice motion nuisance regressor " 
    rm "${owdir}"/epi*
        # ***** clean

else
    echo "++ NOT removing temporary axialization working dir: '$wdir'"
endif

echo ""
echo "++ DONE.  Finished slicewise in-plane motion correction:"
echo "     ${owdir}/${opref}*"
echo ""


goto GOOD_EXIT

# ========================================================================
# ========================================================================

SHOW_HELP:
cat << EOF
-------------------------------------------------------------------------

2d slice image is aligned to the refrence slice only considering inplane 
motion, e.g. x-/y-shift and z-rotation motion. Estimated inplane motion 
is saved and used for slicewise motion nuisance regressor.

+++ Compatibility issue with new version of 3dWarpDrive +++ 
adjunct_slomoco_vol_slicemoco_xy.tcsh does not work with the latest
version of AFNI 3dWarDrive command. In this reason, <<AFNI_SLOMOCO_DIR>>
/3dWarpdrive (afni.afni.openmp.v18.3.16, working version) is included
SLOMOCO package. 3dAllineate can be used for 2d image slice alignment
using -moco_meth option A. However, the output from 3dAllineate is not
good as the output from 3dWarpdrive. - under investigation.
3dWarpdrive is strongly recommnded to run SLOMOCO

++ For Mac User +++
Linux version 3dWaprdrive is only included in SLOMOCO. To run SLOMOCO in 
Mac, you need to compile old version of 3dWarpdrive.

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
