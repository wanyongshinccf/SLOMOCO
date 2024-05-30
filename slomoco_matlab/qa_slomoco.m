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
slice_timing=load('tshiftfile.1D');
slice_timing=1000*slice_timing; %ms

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
exclude_addition = [];
for z = 1: zmbdim
  slivxnoSMS(z) = sum(slivxno(z:zmbdim:end));
  if slivxnoSMS(z) < 2500/abs(dx)/abs(dy)
    exclude_addition=[exclude_addition z];
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
volmot_deriv1 = zeros(size(volmot));
volmot_deriv2 = zeros(size(volmot));
volmot_deriv1(1:end-1,:)=diff(volmot);
volmot_deriv2(2:end,:)=diff(volmot);

% volume motion to slicewise motion time points
for m=1:6
  volmot_ext(:,m)=reshape(repmat(volmot(:,m)',[zmbdim 1]),[zmbdim*tdim 1]);
end
 
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
 
% re-write slice motion in time series
slimot = zeros(tdim*zmbdim,6);
for t = 1:tdim
  for zmb = 1:zmbdim
    acqsliorder = uniq_acq_order(zmb);
    tsli = (t-1)*zmbdim + zmb;
    slimot(tsli,:) = squeeze(slimot_tzmopa(t,acqsliorder,:));  
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
slimot_b = zeros(tdim*zmbdim,6);
for t = 1:tdim
  for zmb = 1:zmbdim
    acqsliorder = uniq_acq_order(zmb);
    tsli = (t-1)*zmbdim + zmb;
    slimot_b(tsli,:) = squeeze(slimot_tzmopa_b(t,acqsliorder,:));  
  end
end
 
% Step 1, define two outer slices in case of single band acq
% identify outer-most slices according to slice timing
% [tmp acq_order] = sort(slice_timing);
exclude_slices_two=[];
% add another outlier based on slicemoco matrix
if MB == 1
  endslices_two = [find(uniq_acq_order == 1) find(uniq_acq_order == zmbdim)  find(uniq_acq_order == 2)  find(uniq_acq_order == zmbdim-1)];
  for n = 1:length(exclude_addition)
    endslices_two = [endslices_two find(uniq_acq_order == exclude_addition(n))];
  end
else
  endslices_two = exclude_addition;
end
 
endslices_two = unique(endslices_two,'stable');
if ~isempty(endslices_two)
    for i=1:tdim
        exclude_slices_two=[exclude_slices_two [((zmbdim*(i-1))+endslices_two)]];
    end
end
 
% Step 2: interpolate over outer two end slices (two on each end) for
% in-/out of plane motion
volslimot = volmot_ext + slimot; % z-rot, x-rot, y-rot, z-shift, x-shift, y-shift
volslimot_b = volmot_ext + slimot_b; % z-rot, x-rot, y-rot, z-shift, x-shift, y-shift
inputmesh_two=setxor(1:zmbdim*tdim,exclude_slices_two);
for m=1:6
  % can't trust the in-plane or out-of-plane motion in outer two slices - this may be dependent on # of voxels in those slices
  % this is worst when its slice #2 (half-way thru a stack of odd # of slices) and slice #30 (last even in stack of odds)
  % but the first and last odd is also modestly bad. This is entirely from out-of-plane motion
  % unfortunately, we cannot be sure whether a given motion is really in-plane or just apparent in-plane
  % so we have no choice unless we can obtain some other information
  volslimot_out(:,m)  =pchip(inputmesh_two,volslimot(inputmesh_two,m),1:zmbdim*tdim);
  volslimot_b_out(:,m)=pchip(inputmesh_two,volslimot_b(inputmesh_two,m),1:zmbdim*tdim);
  %   subplot(6,1,m);  plot(volslimot(:,m),'r');
end
   
% Step 3.   apply a Savitsky-Golay filter with 2 seconds of window
  % this should be turned off for data with really fast motion (like SimPACE data with motion on only one slice)
for m = 1:6
  volslimot_out_fit(:,m) = sgolayfilt(volslimot_out(:,m),3,zmbdim);
  volslimot_b_out_fit(:,m) = sgolayfilt(volslimot_b_out(:,m),3,zmbdim);
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

slimot_out          = volslimot_out - volmot_ext;
slimot_b_out      = volslimot_b_out - volmot_ext;
slimot_out_fit     = volslimot_out_fit - volmot_ext;
slimot_b_out_fit = volslimot_b_out_fit - volmot_ext;

% re-order volumetric params
slimot_jiang=slimot(:,[5 6 4 2 3 1]); % dL dP dS pitch(R-L) yaw(A-P) roll(I-S)
slimot_jiang(:,1:3) = -1*slimot_jiang(:,1:3);
slimot_b_out_jiang=slimot(:,[5 6 4 2 3 1]); % dL dP dS pitch(R-L) yaw(A-P) roll(I-S)
slimot_b_out_jiang(:,1:3) = -1*slimot_b_out_jiang(:,1:3);
slimot_b_out_fit_jiang=slimot(:,[5 6 4 2 3 1]); % dL dP dS pitch(R-L) yaw(A-P) roll(I-S)
slimot_b_out_fit_jiang(:,1:3) = -1*slimot_b_out_fit_jiang(:,1:3);

volslimot_b_out_jiang=volslimot_b_out(:,[5 6 4 2 3 1]); % dL dP dS pitch(R-L) yaw(A-P) roll(I-S)
volslimot_b_out_jiang(:,1:3) = -1*volslimot_b_out_jiang(:,1:3);
volslimot_b_out_fit_jiang=volslimot_b_out_fit(:,[5 6 4 2 3 1]); % dL dP dS pitch(R-L) yaw(A-P) roll(I-S)
volslimot_b_out_fit_jiang(:,1:3) = -1*volslimot_b_out_fit_jiang(:,1:3);

% % correct for scan axis orientation:
% % axial [rx ry rz]=[1 2 3], sagittal=[3 1 2], coronal=[1 3 2]
% axisz=find([rx ry rz]==3);
% if (axisz==2)
%   disp('Swapping axes for coronal acquisition');
%   volmot_jiang=volmot_jiang(:,[3 1 2 6 4 5]); % zsh xsh ysh zrot xrot yrot
%   slimot_jiang =slimot_jiang(:,[3 1 2 6 4 5]); %
%   volslimot_jiang =volslimot_jiang(:,[3 1 2 6 4 5]); % zsh xsh ysh zrot xrot yrot
%   volslimot_out_fit_jiang =volslimot_out_fit_jiang(:,[3 1 2 6 4 5]); %
%   volslimot_b_out_fit_jiang =volslimot_b_out_fit_jiang(:,[3 1 2 6 4 5]); %
% elseif (axisz==1)
%   disp('Swapping axes for sagittal acquisition');
%   volslimot_jiang=volslimot_jiang(:,[2 1 3 5 4 6]);
%   volslimot_jiang(:,[2 5])=-1*volslimot_jiang(:,[2 5]);
%   volslimot_out_fit_jiang=volslimot_out_fit_jiang(:,[2 1 3 5 4 6]);
%   volslimot_out_fit_jiang(:,[2 5])=-1*volslimot_out_fit_jiang(:,[2 5]);
%   volslimot_out_b_fit_jiang=volslimot_out_b_fit_jiang(:,[2 1 3 5 4 6]);
%   volslimot_b_out_fit_jiang(:,[2 5])=-1*volslimot_b_out_fit_jiang(:,[2 5]);
% end

% Framewise TD
dslimot_jiang = diff(slimot_jiang);
dslimot_b_out_jiang = diff(slimot_b_out_jiang);
dslimot_b_out_fit_jiang = diff(slimot_b_out_fit_jiang);
dvolslimot_b_out_jiang = diff(volslimot_b_out_jiang);
dvolslimot_b_out_fit_jiang = diff(volslimot_b_out_fit_jiang);

% finanl calculation of displacement
[iTD,iTDz]  =parallelepiped_jiang(slimot_jiang);

% save all
% fp=fopen('slimot_raw.txt','w');    fprintf(fp,'%g\t%g\t%g\t%g\t%g\t%g\n',slimot'); fclose(fp);
% fp=fopen('slimot_b_out.txt','w');    fprintf(fp,'%g\t%g\t%g\t%g\t%g\t%g\n',slimot_b_out'); fclose(fp);
% fp=fopen('slimot_b_out_fit.txt','w');    fprintf(fp,'%g\t%g\t%g\t%g\t%g\t%g\n',slimot_b_out_fit'); fclose(fp);
fp=fopen('volslimot_raw.txt','w');    fprintf(fp,'%g\t%g\t%g\t%g\t%g\t%g\n',volslimot'); fclose(fp);
fp=fopen('volslimot_fit1.txt','w'); fprintf(fp,'%g\t%g\t%g\t%g\t%g\t%g\n',volslimot_b_out'); fclose(fp);
fp=fopen('volslimot_fit2.txt','w'); fprintf(fp,'%g\t%g\t%g\t%g\t%g\t%g\n',volslimot_b_out_fit'); fclose(fp);
fp=fopen('volmot_ext.txt','w');    fprintf(fp,'%g\t%g\t%g\t%g\t%g\t%g\n',volmot_ext'); fclose(fp);

% test TDz here, will be commented out
[td_out,tdz_out]   =  parallelepiped_jiang(slimot_jiang);
fp=fopen('slomoco.iTDmetric.txt','w'); fprintf(fp,'%g\n',td_out); fclose(fp);
fp=fopen('slomoco.iTDzmetric.txt','w'); fprintf(fp,'%g\n',tdz_out); fclose(fp);

figure
for n = 1:6
  subplot(3,2,n);
  plot(volmot_ext(:,n),'k'); hold on
%   plot(injmot(:,n),'k'); hold on % will be commented out
  plot(volslimot_b_out(:,n),'b');
  plot(volslimot_b_out_fit(:,n),'r'); hold off
  xlim([0 zmbdim*tdim]);
  title( volregstr{n} );
end
saveas(gcf,'qa_volslimoco_metrics.jpg');
 
figure
subplot(3,1,1);
plot(td_out,'b');  hold on
plot(tdz_out,'r'); hold off
ymax = max(max(td_out),max(tdz_out));
title('SLOMOCO TD-0D (blue) TDz-0D (red)')
ylabel('TD'); xlabel('slice*vol number');
xlim([0 tdim*zmbdim]); ylim([0 ymax*1.1]);ylim([0 ymax*1.4])
td_out_max   = round(max(td_out)*100)/100;
td_out_mean = round(mean(td_out)*1000)/1000;
tdz_out_max = round(max(tdz_out)*100)/100;
tdz_out_mean = round(mean(tdz_out)*1000)/1000;
text(round(tdim*zmbdim/10),ymax*1.2,['TD max / mean = ' num2str(td_out_max) ' / '  num2str(td_out_mean)]);
text(round(tdim*zmbdim/10),ymax*1.0,['TDz max / mean = ' num2str(max(tdz_out_max)) ' / '  num2str(tdz_out_mean)]);
subplot(3,1,2);
plot(slimot_b_out_fit_jiang(:,[3 4 5]))
xlim([0 tdim*zmbdim]);
title(sprintf('out-of-plane params for %s',ep2d_filename));
legend('z-trans','x-rot','y-rot');
subplot(3,1,3);
plot(slimot_b_out_fit_jiang(:,[1 2 6]))
xlim([0 tdim*zmbdim]);
legend('x-trans','y-trans','z-rot');
title('in-plane params');
saveas(gcf,'qa_slomoco_iTD.jpg');