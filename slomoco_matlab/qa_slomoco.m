function [volslimot_final slimot_final_jiang] =  qa_slomoco(ep2d_filename,mask_filename,vol_filename, sli_filename)
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
 
% get scan orientation from header
[rx,cx]=find(ainfo.Orientation=='R');  % for axial == 1
[ry,cy]=find(ainfo.Orientation=='A');  % for axial == 2
[rz,cz]=find(ainfo.Orientation=='I');  % for axial == 3
 
% apparently its not uncommon for DELTA to be negative on one or more axes, but don't know why that would be...
voxsize=abs(prod(ainfo.DELTA));
 
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
 
% add another outlier based on slicemoco matrix
exclude_slices = [];
for z = 1: zmbdim
  slivxnoSMS(z) = sum(slivxno(z:zmbdim:end));
  if slivxnoSMS(z) < 2500/abs(dx)/abs(dy)
    exclude_slices=[exclude_slices z];
  end
end
 
% read volumetric params first (assume AFNI 3dvolreg)
% 3dvolreg motion parametner
% z-rot, x-rot, y-rot, z-shift, x-shift, y-shift
% 3dallineate motion parameter
% -xshift, -y-shift, -z-shift, z-rot, x-rot, y-rot
% Jiang's motion parameter
% -xshift, -y-shift, -z-shift, x-rot, y-rot, z-rot
volregstr={'z-rot','x-rot','y-rot','z-trans','x-trans','y-trans'};
jiangstr={'x-trans','y-trans','z-trans','x-rot','y-rot','z-rot'};
volmot = textread(vol_filename); % n roll(I-S) pitch(R-L) yaw(A-P) dS dL dP
volmot_deriv = zeros(size(volmot)); volmot_deriv(1:end-1,:)=diff(volmot);
volmot_deriv1 = zeros(size(volmot));
volmot_deriv2 = zeros(size(volmot));
volmot_deriv1(1:end-1,:)=diff(volmot);
volmot_deriv2(2:end,:)=diff(volmot);

% volume motion to slicewise motion time points
for m=1:6
  volmot_ext(:,m)=reshape(repmat(volmot(:,m)',[zmbdim 1]),[zmbdim*tdim 1]);
  volmot_deriv_ext(:,m)=reshape(repmat(volmot_deriv(:,m)',[zmbdim 1]),[zmbdim*tdim 1]);
end
 
% re-order volumetric params
volmot_jiang=volmot(:,[5 6 4 2 3 1]); % dL dP dS pitch(R-L) yaw(A-P) roll(I-S)
volmot_jiang(:,1:3) = -1*volmot_jiang(:,1:3);
volmot_deriv_jiang=volmot_deriv(:,[5 6 4 2 3 1]); % dL dP dS pitch(R-L) yaw(A-P) roll(I-S)
volmot_deriv_jiang(:,1:3) = -1*volmot_deriv_jiang(:,1:3);
 
% demean vol
volmot_deriv_ext_demean = volmot_deriv_ext - repmat(mean(volmot_deriv_ext),size(volmot_deriv_ext,1),1);
 
% make TD metric
[td_volmoco tdz_volmoco]                      =parallelepiped_jiang(volmot_jiang);
[td_volmoco_deriv tdz_volmoco_deriv ] =parallelepiped_jiang(volmot_deriv_jiang);
 
% read slicewise motion, following 3dvolreg convention
slimot_volreg = load(sli_filename);  % [tdim x (zdim x 6)]
 
% resample based on slice acq order
% temp stores only upto zmbdim
slimot_tzmopa = zeros(tdim,zmbdim,6);
for t = 1:tdim
  for m = 1:6
    slimot_tzmopa(t,:,m) = slimot_volreg(t,m:6:m+zmbdim*6-1);   % [tdim,zmbdim,6]
  end
end
 
% no more normalilzation, but checked bounced
% set the safety inandoutofplane motion factor as 10
slimot_factor = 2;
slimot_tzmopa_b = zeros(size(slimot_tzmopa));
for vol = 1:tdim
  for zmb = 1:zmbdim % not slice number, but slice acq
   acqsliorder = uniq_acq_order(zmb); % [1,3,5,...,2,4,..]
   inandoutofplane = squeeze(slimot_tzmopa(vol,acqsliorder,:));
   
   if zmb  > (zmbdim+1)/2 % 21slices -> ">11";   20slices -> ">10.5"
     volmot_bound = volmot_deriv1(vol,:)';
   elseif zmb <= (zmbdim)/2 % 21slicees -> "=<10.5", 20slices-> "=<10"
     volmot_bound = volmot_deriv2(vol,:)';
   else % center of odd number of slices
     volmot_bound = (volmot_deriv1(vol,:)'+volmot_deriv2(vol,:)')/2;
   end
 
   spiky = find( abs(inandoutofplane) > abs(slimot_factor.*volmot_bound));
   for t=1:length(spiky)
     if inandoutofplane(spiky(t)) > slimot_factor*abs(volmot_bound(spiky(t)))
       inandoutofplane(spiky(t)) = slimot_factor*abs(volmot_bound(spiky(t)));
     elseif inandoutofplane(spiky(t)) < -slimot_factor*abs(volmot_bound(spiky(t)))
       inandoutofplane(spiky(t)) = -slimot_factor*abs(volmot_bound(spiky(t)));
     end
   end
   slimot_tzmopa_b(vol,acqsliorder,:) = inandoutofplane;
  end
end

% re-write slice motion in time series
slimot = zeros(tdim*zmbdim,6);
for t = 1:tdim
  for zmb = 1:zmbdim
    acqsliorder = uniq_acq_order(zmb);
    tsli = (t-1)*zmbdim + zmb;
    slimot(tsli,:) = squeeze(slimot_tzmopa_b(t,acqsliorder,:));
  end
end
 
% correct for scan axis orientation:
% axial [rx ry rz]=[1 2 3], sagittal=[3 1 2], coronal=[1 3 2]
axisz=find([rx ry rz]==3);
if (axisz==2)
  disp('Swapping axes for coronal acquisition');
  volmot =volmot(:,[3 1 2 6 4 5]); % zsh xsh ysh zrot xrot yrot
  slimot =slimot(:,[3 1 2 6 4 5]); %
%   volmot_jiang=volmot_jiang(:,[3 1 2 6 4 5]); % zsh xsh ysh zrot xrot yrot
%   slimot_jiang=slimot_jiang(:,[3 1 2 6 4 5]); %
elseif (axisz==1)
  disp('Swapping axes for sagittal acquisition');
  volmot=volmot(:,[2 1 3 5 4 6]);
  slimot=slimot(:,[2 1 3 5 4 6]);
  volmot(:,[2 5])=-1*volmot(:,[2 5]);
  slimot(:,[2 5])=-1*slimot(:,[2 5]);
  %   volmot_jiang=volmot_jiang(:,[3 2 1 6 5 4]);
%   slimot_jiang=slimot_jiang(:,[3 2 1 6 5 4]);% 1, 4 are inverted
%   volmot_jiang(:,[1 4])=-1*volmot_jiang(:,[1 4]);
%   slimot_jiang(:,[1 4])=-1*slimot_jiang(:,[1 4]);
end
 
% Step 1, define two outer slices in case of single band acq
% identify outer-most slices according to slice timing
% [tmp acq_order] = sort(slice_timing);
exclude_slices_acq=[];
for n = 1:length(exclude_slices)
  exclude_slices_acq = [exclude_slices_acq find(uniq_acq_order == exclude_slices(n))];
end
exclude_slices_tp=[];
if ~isempty(exclude_slices_acq)
    for i=1:tdim
        exclude_slices_tp=[exclude_slices_tp [((zmbdim*(i-1))+exclude_slices_acq)]];
    end
end

% Step 2: interpolate over outer two end slices (two on each end) for
% in-/out of plane motion
volslimot = volmot_ext + slimot; % z-rot, x-rot, y-rot, z-shift, x-shift, y-shift
volslimot_raw = volslimot;
inputmesh_two=setxor(1:zmbdim*tdim,exclude_slices_tp);
for m=1:6
  % can't trust the in-plane or out-of-plane motion in outer two slices - this may be dependent on # of voxels in those slices
  % this is worst when its slice #2 (half-way thru a stack of odd # of slices) and slice #30 (last even in stack of odds)
  % but the first and last odd is also modestly bad. This is entirely from out-of-plane motion
  % unfortunately, we cannot be sure whether a given motion is really in-plane or just apparent in-plane
  % so we have no choice unless we can obtain some other information
  volslimot(:,m)=pchip(inputmesh_two,volslimot(inputmesh_two,m),1:zmbdim*tdim);
%   subplot(6,1,m);  plot(volslimot(:,m),'r');
end
 
% Step 3.   apply a Savitsky-Golay filter with 2 seconds of window
  % this should be turned off for data with really fast motion (like SimPACE data with motion on only one slice)
for m = 1:6
  volslimot_fit(:,m) = sgolayfilt(volslimot(:,m),3,floor(zmbdim/2)*2+1); % debugged (W.S) 20250611
  % in case of signal processing box is not availble, uncommnet the below
%   SGbin = round(Fs/2)*4+1;
%   i =  -2*round(Fs/2): 2*round(Fs/2);
%   C = (3*SGbin^2-7-20*i.^2)/4/(SGbin*(SGbin^2-4)/3);
%   volslimot_final(:,SGbin) = conv(volslimot_scaled(:,m),C,'same');  
%   volslimot_final(1:SGbin,m) = volslimot_scaled(1:SGbin,m:,m);
%   volslimot_final(tdim*zmbdim-SGbin + 1: tdim*zmbdim,m) = volslimot_scaled(tdim*zmbdim-SGbin + 1: tdim*zmbdim,m);
% % the edge of the values are not trustable.
% volslimot_final(1:round(Fs/2)*2,:) = volslimot_scaled(1:round(Fs/2)*2,:);
% volslimot_final(1-round(Fs/2)*2+1:end,:) = volslimot_scaled(end-round(Fs/2)*2+1:end,:);
end

slimot_fit          = volslimot_fit - volmot_ext;

% re-order volumetric params
slimot_jiang=slimot(:,[5 6 4 2 3 1]); % dL dP dS pitch(R-L) yaw(A-P) roll(I-S)
slimot_jiang(:,1:3) = -1*slimot_jiang(:,1:3);
slimot_fit_jiang=slimot_fit(:,[5 6 4 2 3 1]); % dL dP dS pitch(R-L) yaw(A-P) roll(I-S)
slimot_fit_jiang(:,1:3) = -1*slimot_fit_jiang(:,1:3);

volslimot_jiang=volslimot(:,[5 6 4 2 3 1]); % dL dP dS pitch(R-L) yaw(A-P) roll(I-S)
volslimot_jiang(:,1:3) = -1*volslimot_jiang(:,1:3);
volslimot_fit_jiang=volslimot_fit(:,[5 6 4 2 3 1]); % dL dP dS pitch(R-L) yaw(A-P) roll(I-S)
volslimot_fit_jiang(:,1:3) = -1*volslimot_fit_jiang(:,1:3);

% save all
% test TDz here, will be commented out
[td_slomoco,tdz_slomoco]   =  parallelepiped_jiang(slimot_jiang);
fp=fopen('slomoco.iTDmetric.txt','w'); fprintf(fp,'%g\n',td_slomoco); fclose(fp);
fp=fopen('slomoco.iTDzmetric.txt','w'); fprintf(fp,'%g\n',tdz_slomoco); fclose(fp);
 
% for a volumetric metric of motion corruption, use the mean across slices within a volume (W.S 20240611)
fp=fopen('slomoco.volumetric.iTDmetric.txt','w'); fprintf(fp,'%g\n',mean(reshape(td_slomoco,[zmbdim tdim]))); fclose(fp);
fp=fopen('slomoco.volumetric.iTDzmetric.txt','w'); fprintf(fp,'%g\n',mean(reshape(tdz_slomoco,[zmbdim tdim]))); fclose(fp);
 
% 3dvolreg motion x,y,z trans are inverted w.r.t. 3dWarpDrive
% [td_volmoco,tdz_volmoco]=parallelepiped_jiang(volmot_jiang);
% fp=fopen('volmoco.TDmetric.txt','w'); fprintf(fp,'%g\n',td_volmoco); fclose(fp);
% fp=fopen('volmoco.TDzmetric.txt','w'); fprintf(fp,'%g\n',tdz_volmoco); fclose(fp);
%
% 3dvolreg derivative motion x,y,z trans are inverted w.r.t. 3dWarpDrive
[td_volmoco_deriv,tdz_volmoco_deriv]=parallelepiped_jiang(volmot_deriv_jiang);
fp=fopen('volmoco.Deriv.TDmetric.txt','w'); fprintf(fp,'%g\n',td_volmoco_deriv); fclose(fp);
fp=fopen('volmoco.Deriv.TDzmetric.txt','w'); fprintf(fp,'%g\n',tdz_volmoco_deriv); fclose(fp);
 
% save the 3dvolreg volumetric motion, repeated over slices
fp=fopen('volslimot_fit.txt','w'); fprintf(fp,'%g\t%g\t%g\t%g\t%g\t%g\n',volslimot_fit'); fclose(fp);
fp=fopen('volslimot.txt','w'); fprintf(fp,'%g\t%g\t%g\t%g\t%g\t%g\n',volslimot'); fclose(fp);
fp=fopen('volslimot_raw.txt','w'); fprintf(fp,'%g\t%g\t%g\t%g\t%g\t%g\n',volslimot_raw'); fclose(fp);

% original commented by E.B
% to see the difference between volumetric motion and slice motion, plot(slomoco-volmotion)
% this is the residual motion left after volumetric correction, or what volmoco misses
% finally, if prospective motion is turned on (Thesen et al 2002), the volumetric motion is essentially
% subtracted from the data, delayed by one volume, so there will be sharp disruptions at the volume boundary
% we could obtain the true (free-space) motion by shifting the volumetric motion by one volume, and adding to slomoco
% this could also be used to improve the edge slice interpolations and could be done earlier, but many sites do not
% use PACE (the Siemens name, each vendor has their own, as far as I know), and is outside the scope of this work
% NOTE, it will be important to know the real free-space motion for applying RX field and B0 inhomogeneity motion corrections
 
figure
for n = 1:6
  subplot(4,2,n);
  plot(volmot_ext(:,n),'b'); hold on
%   plot(injmot(:,n),'k'); hold on % will be commented out
  plot(volslimot_fit(:,n),'r'); hold off
  xlim([0 zmbdim*tdim]);
  title([ volregstr{n} ' (vol: blue, vol+sli: red)']);
end
% saveas(gcf,'qa_vol_slimoco_metrics.jpg');
subplot(4,2,7);
plot(td_volmoco);xlim([0 tdim]);
legend('Avg Vox Disp');
title('Vol Mot TD (Jiang parallelepiped method)');
subplot(4,2,8);
plot(td_volmoco_deriv);xlim([0 tdim]);
legend('Avg Vox Disp');
title('Deriv of Vol Mot TD (Jiang parallelepiped method)');
saveas(gcf,'qa_volslimoco_metrics.jpg');
 
figure
subplot(3,1,1);
plot(td_slomoco,'b');  hold on
plot(tdz_slomoco,'r'); hold off
ymax = max(max(td_slomoco),max(tdz_slomoco));
title('SLOMOCO TD-0D (blue) TDz-0D (red)')
ylabel('TD'); xlabel('slice*vol number');
xlim([0 tdim*zmbdim]); ylim([0 ymax*1.1]);ylim([0 ymax*1.4])
td_slomoco_max   = round(max(td_slomoco)*100)/100;
td_slomoco_mean = round(mean(td_slomoco)*1000)/1000;
tdz_slomoco_max = round(max(tdz_slomoco)*100)/100;
tdz_slomoco_mean = round(mean(tdz_slomoco)*1000)/1000;
text(round(tdim*zmbdim/10),ymax*1.2,['iTD max / mean = ' num2str(td_slomoco_max) ' / '  num2str(td_slomoco_mean)]);
text(round(tdim*zmbdim/10),ymax*1.0,['iTDz max / mean = ' num2str(max(tdz_slomoco_max)) ' / '  num2str(tdz_slomoco_mean)]);
subplot(3,1,2);
plot(slimot_fit_jiang(:,[3 4 5]))
xlim([0 tdim*zmbdim]);
title(sprintf('out-of-plane params'));
legend('z-trans','x-rot','y-rot');
subplot(3,1,3);
plot(slimot_fit_jiang(:,[1 2 6]))
xlim([0 tdim*zmbdim]);
legend('x-trans','y-trans','z-rot');
title('in-plane params');
saveas(gcf,'qa_slomoco_motionvectors.jpg');

% DVARS and FD caclulation
DV = calcDVARS(ep2d_filename,mask_filename,slice_timing);
FD = calcFD(vol_filename);
fp=fopen('FD.txt','w'); fprintf(fp,'%g\n',FD); fclose(fp);
fp=fopen('DVARS.txt','w'); fprintf(fp,'%g\n',DV); fclose(fp);
 