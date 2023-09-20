function qa_slomoco(ep2d_filename,mask_filename,vol_filename, sli_filename,maxscale)
%function qa_slomoco(ep2d_filename,filestr_out,filestr_in,slice_timing,filter_width,sub_xy_offsets)
% script reads in SLOMOCO files and fit data in local directory (currently inside pestica/ subdirectory)
% plot motion parameters, histograms of excessive motion, histograms of motion coupling t-score (sum across model)

% BrikInfo only works on AFNI BRIK format files
[err,ainfo] = BrikInfo(ep2d_filename);
xdim=ainfo.DATASET_DIMENSIONS(1);
ydim=ainfo.DATASET_DIMENSIONS(2);
zdim=ainfo.DATASET_DIMENSIONS(3);
tdim=ainfo.DATASET_RANK(2);
dx=ainfo.DELTA(1);
dy=ainfo.DELTA(2);
dz=ainfo.DELTA(3);
TR=double(ainfo.TAXIS_FLOATS(2));
slice_timing=load('tshiftfile.1D'); slice_timing=1000*slice_timing; %ms

% check time unit
[TRsec TRms] = TRtimeunitcheck(TR);
[slice_timing_sec slice_timing_ms] = TRtimeunitcheck(slice_timing);
[MB zmbdim uniq_slice_timing_ms uniq_acq_order] = SMSacqcheck(TRms, zdim, slice_timing_ms);

% read mask and set the scale factor for out-of-plane
[err, mask, Info, ErrMessage]  = BrikLoad(mask_filename);
mask(find(mask))=1;
slivxno=zeros(zdim,1);
for z = 1:zdim
  mask_s = squeeze(mask(:,:,z));
  slivxno(z) = sum(mask_s(:));
end

for z = 1:zmbdim
  slivxnoSMS(z) = sum(slivxno(z:zmbdim:end));
end

% add another outlier based on slicemoco matrix
exclude_addition = [];
for z = 1: zmbdim
  if slivxnoSMS(z) < 2500/abs(dx)/abs(dy)
    exclude_addition=[exclude_addition z];
  end
end   

% get scan orientation from header
[rx,cx]=find(ainfo.Orientation=='R');  % for axial == 1
[ry,cy]=find(ainfo.Orientation=='A');  % for axial == 2
[rz,cz]=find(ainfo.Orientation=='I');  % for axial == 3

% apparently its not uncommon for DELTA to be negative on one or more axes, but don't know why that would be...
voxsize=abs(prod(ainfo.DELTA));

%% reading volreg parameter 
% 3dvolreg motion parametner
% z-rot, x-rot, y-rot, z-shift, x-shift, y-shift
% 3dallineate motion parameter
% -xshift, -y-shift, -z-shift, z-rot, x-rot, y-rot
% Jiang's motion parameter
% -xshift, -y-shift, -z-shift, x-rot, y-rot, z-rot

% read volumetric params first (assume AFNI 3dvolreg)
volmot_volreg = load(vol_filename); % z-/x-/y-rots z-/x-/y-shift

% re-order volumetric params to x-/y-/z-shift & x-/y-/z-rot, w.r.t. 3dWarpDrive
volmot_jiang=volmot_volreg(:,[5 6 4 2 3 1]); % dL dP dS pitch(R-L) yaw(A-P) roll(I-S)

% demean vol
volmot_jiang_demean = volmot_jiang - repmat(mean(volmot_jiang),size(volmot_jiang,1),1);

%% reading slice parameter
% read in/out-of-plane motion parameters
% note that slicebase motion has full z dim, 
% in which slicewise motion in SMS slices are
% identical. slice motion within zmbdim wil be selected 
slimot_volreg = load(sli_filename); % tdim x zdim*6
    
% resample based on slice acq order
% temp stores only upto zmbdim
slimot_tzmopa = zeros(tdim,zmbdim,6);
for t = 1:tdim
  for m = 1:6
    slimot_tzmopa(t,:,m) = slimot_volreg(t,m:6:zmbdim*6);   % [tdim,zmbdim,6]
  end
end

% re-write slice motion in time series
slimot_volreg = zeros(tdim*zmbdim,6);
for t = 1:tdim
  for zmb = 1:zmbdim
    acqsliorder = uniq_acq_order(zmb);
    tsli = (t-1)*zmbdim + zmb;
    slimot_volreg(tsli,:) = squeeze(slimot_tzmopa(t,acqsliorder,:));  
  end
end

% re-order volumetric params to x-/y-/z-shift & x-/y-/z-rot, w.r.t. 3dWarpDrive
slimot_jiang = slimot_volreg(:,[5 6 4 2 3 1]); %  [dL dP dS pitch yaw roll]] 

%% 
% correct for scan axis orientation: 
% axial [rx ry rz]=[1 2 3], sagittal=[3 1 2], coronal=[1 3 2]
axisz=find([rx ry rz]==3);
if (axisz==2)
  slimot_jiang=slimot_jiang(:,[3 1 2 6 4 5]);
  slimot_jiang_scaled=slimot_jiang_scaled(:,[3 1 2 6 4 5]);
  disp('Swapping axes for coronal acquisition');
elseif (axisz==1)
  slimot_jiang=slimot_jiang(:,[3 2 1 6 5 4]);
  slimot_jiang_scaled=slimot_jiang_scaled(:,[3 2 1 6 5 4]);
  % 1, 4 are inverted
  slimot_jiang(:,[1 4])=-1*slimot_jiang(:,[1 4]);
  slimot_jiang_scaled(:,[1 4])=-1*slimot_jiang_scaled(:,[1 4]);
  disp('Swapping axes for sagittal acquisition');
end

% step 2, define two outer slices in case of single band acq
% identify outer-most slices according to slice timing
% [tmp acq_order] = sort(slice_timing);
exclude_slices_one=[]; exclude_slices_two=[];

if MB == 1
  endslices_two = [find(uniq_acq_order == 1) find(uniq_acq_order == zmbdim)  find(uniq_acq_order == 2)  find(uniq_acq_order == zmbdim-1)]; 
  endslices_one = [find(uniq_acq_order == 1) find(uniq_acq_order == zmbdim)];
  for n = 1:length(exclude_addition)
    endslices_two = [endslices_two find(uniq_acq_order == exclude_addition(n))];
    endslices_one = [endslices_one find(uniq_acq_order == exclude_addition(n))];
  end
else
  endslices_two = exclude_addition; endslices_one = exclude_addition;
end
endslices_two = unique(endslices_two,'stable');
endslices_one = unique(endslices_one,'stable');
if ~isempty(endslices_one)
    for i=1:size(slimot_volreg,1)/zmbdim
        exclude_slices_one=[exclude_slices_one [((zmbdim*(i-1))+endslices_one)]];
        exclude_slices_two=[exclude_slices_two [((zmbdim*(i-1))+endslices_two)]];
    end
end

% step 3: combine/compare vol vs vol+sli motion
for i=1:6
  volmot_jiang_slires(:,i)=reshape(repmat(volmot_jiang(:,i)',[zmbdim 1]),[zmbdim*tdim 1]);
  volmot_volreg_slires(:,i)=reshape(repmat(volmot_volreg(:,i)',[zmbdim 1]),[zmbdim*tdim 1]);
end
volslimot_volreg = volmot_volreg_slires + slimot_volreg;    
volslimot_jiang = volmot_jiang_slires + slimot_jiang;    

% Step 4: interpolate over outer two end slices (two on each end) for
inputmesh_two=setxor(1:size(slimot_jiang,1),exclude_slices_two);
inputmesh_one=setxor(1:size(slimot_jiang,1),exclude_slices_one);

for i=1:6
  volslimot_jiang_fit(:,i)=pchip(inputmesh_two,volslimot_jiang(inputmesh_two,i),1:size(slimot_jiang,1));
  volmot_jiang_slires_fit(:,i)=pchip(inputmesh_two,volmot_jiang_slires(inputmesh_two,i),1:size(slimot_jiang,1));
end

% handling the discontinuty of fit
slimot_jiang_fit = volslimot_jiang_fit - volmot_jiang_slires_fit;
slimot_jiang_fit(:,end-1:end) = slimot_jiang(:,end-1:end);

% % step 5: add back to vol motion
 
% make TD metric
[td_volmoco,tdz_volmoco] = parallelepiped_jiang(volmot_jiang);
[td_volmoco_slires,tdz_volmoco_slires] = parallelepiped_jiang(volmot_jiang_slires);
[td_slomoco,tdz_slomoco] = parallelepiped_jiang(slimot_jiang_fit);
[td_volslimoco,tdz_volslimoco]=parallelepiped_jiang(volslimot_jiang_fit);
    
% save volmoco td(z)             
fp=fopen('volmotion.TDmetric.txt','w');  fprintf(fp,'%g\n',td_volmoco);  fclose(fp);
fp=fopen('volmotion.TDzmetric.txt','w'); fprintf(fp,'%g\n',tdz_volmoco); fclose(fp); 

% save slomoco td(z)
fp=fopen('slomoco.TDmetric.txt','w');  fprintf(fp,'%g\n',td_slomoco);  fclose(fp);
fp=fopen('slomoco.TDzmetric.txt','w'); fprintf(fp,'%g\n',tdz_slomoco); fclose(fp);

% save slomoco td(z)
fp=fopen('volslimoco.TDmetric.txt','w');  fprintf(fp,'%g\n',td_volslimoco);  fclose(fp);
fp=fopen('volslimoco.TDzmetric.txt','w'); fprintf(fp,'%g\n',tdz_volslimoco); fclose(fp);

% for a volumetric metric of motion corruption, use the max across slices within a volume
fp=fopen('slomoco.volumetric.TDzmetric.txt','w'); fprintf(fp,'%g\n',max(reshape(tdz_slomoco,[zmbdim tdim]))); fclose(fp);
fp=fopen('slomoco.volumetric.TDmetric.txt','w');  fprintf(fp,'%g\n',max(reshape(td_slomoco, [zmbdim tdim]))); fclose(fp);

% save Jiang's parameter, repeated over slices
fp=fopen('volmotion.Jiang.txt','w');    fprintf(fp,'%g\t%g\t%g\t%g\t%g\t%g\n',volmot_jiang_slires'); fclose(fp);
fp=fopen('slimotion.Jiang.txt','w'); fprintf(fp,'%g\t%g\t%g\t%g\t%g\t%g\n',slimot_jiang_fit'); fclose(fp);
fp=fopen('volslimotion.Jiang.txt','w'); fprintf(fp,'%g\t%g\t%g\t%g\t%g\t%g\n',volslimot_jiang_fit'); fclose(fp);

figure
subplot(3,1,1);
% plot(0:tdim*zmbdim-1,td_volmoco_slires,0:tdim*zmbdim-1,td_volslimoco)
plot(0:tdim*zmbdim-1,td_volmoco_slires,0:tdim*zmbdim-1,tdz_volmoco_slires)

xlim([0 tdim*zmbdim]);
legend('vol TD','vol TDz');
title('TD & TDz (Volume motion only)');

subplot(3,1,2);
plot(0:tdim*zmbdim-1,td_volslimoco,0:tdim*zmbdim-1,tdz_volslimoco)
xlim([0 tdim*zmbdim]);
legend('vol+sli TD','vol+sli TDz');
title('TD & TDz (Volume + slice motion)');

subplot(3,1,3);
plot(0:tdim*zmbdim-1,td_slomoco,0:tdim*zmbdim-1,tdz_slomoco)
xlim([0 tdim*zmbdim]);
legend('sli TD','sli TDz');
title('TD and TDz (Slice motion only)');
saveas(gcf,'qa_TD_TDz_metrics.jpg');

figure
subplot(3,1,1)
plot(volmot_jiang_slires)
xlim([0 tdim*zmbdim]);
legend('x-trans','y-trans','z-trans','x-rot','y-rot','z-rot');
title('volumetric params');  
subplot(3,1,2)
plot(volslimot_jiang_scaled_fit)
xlim([0 tdim*zmbdim]);
legend('x-trans','y-trans','z-trans','x-rot','y-rot','z-rot');
title('volumetric + slice params');
subplot(3,1,3);
plot(slimot_jiang_scaled_fit)
xlim([0 tdim*zmbdim]);
title(sprintf('in/out-of-plane params'));
legend('x-trans','y-trans','z-trans','x-rot','y-rot','z-rot');
saveas(gcf,'qa_slomoco_motionvectors.jpg');


