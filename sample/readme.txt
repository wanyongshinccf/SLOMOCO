simpace5.slimot.nii.gz file is EPI images of ex-vivo brain, and slicewise motion was 
injected during EPI acquisition altering the imagigng plane at each slice acquisition.

10 SIMPACE data with different inter-/intra-volume motion patterns injected is (will be)
shared in https://osf.io/95dxr (see the citation below)

Test runs slomoco with the following commands in your shell

After include SLOMOCO package path to your shell environment,
run_slomoco.tcsh -dset_epi simpace5.slimot.nii.gz \
     -tfile tshiftfile \
     -prefix epi.slomoco \
     -workdir SLOMOCO \
     -do_clean


1) Shin W., Taylor P., Lowe MJ., Estimation and Removal of Residual Motion Artifact in 
Retrospectively Motion-Corrected fMRI Data: A Comparison of Intervolume and Intravolume 
Motion Using Gold Standard Simulated Motion Data. 2024 Neuro Aperture, 2024; 4
https://doi.org/10.52294/001c.123369