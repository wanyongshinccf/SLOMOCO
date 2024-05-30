#!/bin/tcsh

# user provides 1 req and 1 opt arg:
# + (req) input 3D+t filename
# + (opt) filename for storing string of interest (line to add to 3dAllineate)
#   -> if no 2nd opt is given, then the text will just be displayed in term

set inp   = "$1"
set ofile = "$2"

if ( "$1" == "" ) then
    echo "** ERROR: need to use 1 or 2 command line arguments"
    exit 1
endif

echo "++ Get orient and parfix info"

# ----- get number of Z slices, and upper index

set qq  = `3dAttribute DATASET_DIMENSIONS "${inp}"`

if ( $#qq == 0 ) then
    echo "** ERROR: Dataset ${inp} missing DATASET_DIMENSIONS attribute."
    echo "   Exiting."
    exit 1
endif

set nz  = $qq[3]
@ nz1   = $nz - 1

# ---- find orientation of dataset

set qq = `3dAttribute ORIENT_SPECIFIC "${inp}"`
if ( $#qq == 0 ) then
    echo "** ERROR: Dataset ${inp} missing ORIENT_SPECIFIC attribute."
    echo "   Exiting."
    exit 1
endif

switch ( $qq[1] )
  case "0":
  case "1":
    set xxor = "R"
    breaksw
  case "2":
  case "3":
    set xxor = "A"
    breaksw
  case "4":
  case "5":
    set xxor = "I"
    breaksw
  default:
    echo '** ERROR: Illegal value in ORIENT_SPECIFIC[1] - exiting'
    exit 1
endsw

switch ( $qq[2] )
  case "0":
  case "1":
    set yyor = "R"
    breaksw
  case "2":
  case "3":
    set yyor = "A"
    breaksw
  case "4":
  case "5":
    set yyor = "I"
    breaksw
  default:
    echo '** ERROR: Illegal value in ORIENT_SPECIFIC[2] - exiting'
    exit 1
endsw

switch ( $qq[3] )
  case "0":
  case "1":
    set zzor = "R" ; set orient = "sagittal"
    breaksw
  case "2":
  case "3":
    set zzor = "A" ; set orient = "coronal"
    breaksw
  case "4":
  case "5":
    set zzor = "I" ; set orient = "axial"
    breaksw
  default:
    echo '** ERROR: Illegal value in ORIENT_SPECIFIC[3] - exiting'
    exit 1
endsw

echo "++ Detected slice orientation: $orient"

switch( $zzor )
  case "R":
    set shift = 1 ; set rota = 4  ; set rotb = 6 
    set scala = 7 ; set shra = 10 ; set shrb = 11
    breaksw

  case "A":
    set shift = 2 ; set rota = 4  ; set rotb = 5 
    set scala = 8 ; set shra = 10 ; set shrb = 12
    breaksw

  case "I":
    set shift = 3 ; set rota = 5  ; set rotb = 6 
    set scala = 9 ; set shra = 11 ; set shrb = 12
    breaksw

  default:
    echo "Illegal value of zzor = ${zzor} - exiting"
    exit 1
endsw

# ----- create text block to output (either print or write to file)

# which parameters will get fixed?
set otxt = "-parfix $shift 0 -parfix $rota 0 -parfix $rotb 0 "
set otxt = "${otxt} -parfix  7 1  -parfix  8 1  -parfix  9 1 "
set otxt = "${otxt} -parfix 10 0  -parfix 11 0  -parfix 12 0"

if ( "${ofile}" == "" ) then
    echo "${otxt}"
else
    echo "${otxt}" > "${ofile}"
endif

# done
exit 0
