SLOMOCO is a tcsh script to run slicewise motion correction on fMRI 2D EPI dataset

To run SLOMOCO, you need to add SLOMOCO path to your PATH in your shell environment.
If you download a SLOMOCO package in your home directory, e.g. /home/wyshin/SLOMOCO

export PATH=$PATH:/home/wyshin/SLOMOCO # in your bash/zsh shell.
set PATH = $PATH:/home/wyshin/SLOMOCO  # in your z/csh shell.

SLOMOCO requires AFNI
Set afni path in your shell environment. 
Open the terminal and type "afni" in your shell. It should work for SLOMOCO

SLOMOCO requires matlab.
Set matlab path in your shell environment. 
Open the terminal and type "matlab" in your shell. It should work for SLOMOCO

If you are running run_slomoco.tcsh in linux or Mac OS, the result is slightly different.
DO NOT mix up SLOMOCO results from Linux or Mac OS in your study.

In addition, run_volmoco.tcsh provides voxelwise partial volume (PV) motion nuisance 
regress-out pipeline (After 3dvolreg, 6 rigid volume motion + PV regress-out)
The detail is found in Citation 1)

======= technical detail =======
For Linux, slicewise motion correction is running;
1) volume motion correction -> averaged -> referece volume
2) reference volume for SLOMOCO is defined at each volume by reverse alignment of the reference volume 
3) 3dWarpDrive (afni.afni.openmp.v18.3.16) included in this package is running.

For Mac OS, slicewise motion correction is running;
1) volume motion correction is applied
2) volmoco images are slicewise motion corrected on the reference volume
3) 3dAllineate (in your AFNI version) is running 

Empirically, we find that 3dWarpdrive pipeline works slightly better. 
However, the specific version of 3dWarpdrive works for 2d image alignment. 
Other newer version 3dWarpDrive stop running with "zero---ish..." error.
We cannot distribute the pre-complied 3dWarpdrive for Mac.
=================================

Citation
1) Shin W., Taylor P., Lowe MJ., Estimation and Removal of Residual Motion Artifact in 
Retrospectively Motion-Corrected fMRI Data: A Comparison of Intervolume and Intravolume 
Motion Using Gold Standard Simulated Motion Data. 2024 Neuro Aperture (in revision), 2024

2) Beall EB, Lowe MJ. SimPACE: generating simulated motion corrupted BOLD data with 
synthetic-navigated acquisition for the development and evaluation of SLOMOCO: a new, 
highly effective slicewise motion correction. Neuroimage. 2014 Nov 1;101:21-34. 