## SLOMOCO is a tcsh script to run slicewise motion correction on fMRI 2D EPI dataset ##

To run SLOMOCO, you need to add SLOMOCO path to your PATH in your shell environment.
If you download a SLOMOCO package in your home directory, e.g. /home/wyshin/SLOMOCO

export PATH=$PATH:/home/ccf/SLOMOCO # in your bash/zsh shell.
set PATH = $PATH:/home/ccf/SLOMOCO  # in your z/csh shell.

SLOMOCO requires AFNI
Set afni path in your shell environment. 
Open the terminal and type "afni" in your shell. It should work for SLOMOCO

SLOMOCO requires python
Set python path as "python" in your shell environment. 

If you are running run_slomoco.tcsh in linux or Mac OS, the result might be slightly different.
DO NOT mix up SLOMOCO results from Linux or Mac OS in your study.

We suggest running PESTICA (or RETROICOR) before SLOMOCO and to add physiologic nuisance
regressors to SLOMOCO motion nuisance regression model.
e.g. run_pestica.tcsh \
         -dset_epi epi+orig \
         -tfile tshiftfile.1D \
         -prefix epi.pestica \
	 -workdir PESTICA \
         -auto -do_clean
     run_slomoco.tcsh 	\
         -dset_epi epi+orig \
         -tfile tshiftfile.1D \
         -prefix epi.slomoco \
         -physio PESTICA/RetroTS.PESTICA.slibase.1D \
 	 -workdir SLOMOCO5 -do_clean

In addition, run_volmoco.tcsh provides voxelwise partial volume (PV) motion nuisance 
regress-out pipeline (After 3dvolreg, 6 rigid volume motion + PV regress-out)
The detail is found in Citation 1)

## SIMPACE data ##
SLOMOCO was validated using the simulated prospective acquisition correction (SIMPACE) 
dataset in which the volume-/slice-wise motion is injected during ex-vivo brain scan.
Single SIMPACE data is incldued in SLOMOCO package. All 10 single band SIMPACE data
is (will be) shared in https://dabi.loni.usc.edu/dsi/QEMFAPTWL9RO through MTA
or contact Wanyong Shin (shinw@ccf.org)

Citation
1) Shin W., Taylor P., Lowe MJ., Estimation and Removal of Residual Motion Artifact in 
Retrospectively Motion-Corrected fMRI Data: A Comparison of Intervolume and Intravolume 
Motion Using Gold Standard Simulated Motion Data. 2024 Neuro Aperture, 2024; 4
https://doi.org/10.52294/001c.123369

2) Beall EB, Lowe MJ. SimPACE: generating simulated motion corrupted BOLD data with 
synthetic-navigated acquisition for the development and evaluation of SLOMOCO: a new, 
highly effective slicewise motion correction. Neuroimage. 2014 Nov 1;101:21-34. 
