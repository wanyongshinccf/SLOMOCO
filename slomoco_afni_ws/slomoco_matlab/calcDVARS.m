function [dv idv] = calciDVARS(ep2d_filename,mask_filename,tshift_filename)

[err, ep2d, ainfo, ErrMessage]  = BrikLoad(ep2d_filename);
xdim=ainfo.DATASET_DIMENSIONS(1);
ydim=ainfo.DATASET_DIMENSIONS(2);
zdim=ainfo.DATASET_DIMENSIONS(3);
tdim=ainfo.DATASET_RANK(2);
dx=ainfo.DELTA(1); 
dy=ainfo.DELTA(2);
dz=ainfo.DELTA(3);
TR=double(ainfo.TAXIS_FLOATS(2));

slice_timing=load(tshift_filename); slice_timing=1000*slice_timing; %ms
[TRsec TRms] = TRtimeunitcheck(TR);
[slice_timing_sec slice_timing_ms] = TRtimeunitcheck(slice_timing);
[MB zmbdim uniq_slice_timing_ms uniq_acq_order] = SMSacqcheck(TRms, zdim, slice_timing_ms);

[err, mask, Info, ErrMessage]  = BrikLoad(mask_filename);

mask_vec = mask(:);
nvox = length(mask_vec);
img_vec = reshape(ep2d,[xdim*ydim*zdim tdim]);
imgc_vec = img_vec(find(mask_vec),:);

dv = zeros(tdim-1,1);
for t = 2:tdim
  tmask_vec = isfinite(imgc_vec(:,t));
  dc = 100*(imgc_vec(find(tmask_vec),t)-imgc_vec(find(tmask_vec),t-1))./imgc_vec(find(tmask_vec),t);
  dv(t-1) = sqrt(sum(dc(isfinite(dc)).^2)/nvox);
end

% idv
idv = zeros(zmbdim*(tdim-1),1); 
for t = 2:tdim
  for z = 1: zmbdim % slice time order index
    
    z_ordered = uniq_acq_order(z);
    mask_mb = mask(:,:,z_ordered:MB:zdim);
    mask_mb = mask_mb(:);
    img1 = squeeze(ep2d(:,:,z_ordered:MB:zdim,t)); img1 = img1(:);
    img2 = squeeze(ep2d(:,:,z_ordered:MB:zdim,t-1)); img2 = img2(:);
    
    dc_2d_vec = 100*(img1  - img2)./img1;
    dc_2d_masked = dc_2d_vec(find(mask_mb));
    tmask_vec = isfinite(dc_2d_masked);
    if sum(tmask_vec)
      idv((t-2)*zmbdim + z) = sqrt(sum(dc_2d_masked(find(tmask_vec)).^2)/sum(tmask_vec));
    end
  end
end
