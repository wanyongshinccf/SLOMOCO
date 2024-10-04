function sstd = calcSSTD(ep2d_fn, mask_fn)
% Variability measerues
% fMRI signal in r position at t timepoint = sig(r,t)
% norm_sig(r,t) = 100*(sig(r,t) - M(r))/M(r)
%, M(r) is temporally average signal in r
% spatical standard deviation (SSTD)
% SSTD(t) = sqrt(sum(norm_sig(r,t).^2)/N)
% Note that SSTD is not same as DAVAR
% see Afyouni and Nichols, Neuroimage, 
%2018 (291-312)

% ep2d_fn='epi_03_slicemoco_xy.slomoco+orig';
% mask_fn='epi_base_mask+orig';

% read EPI input
[err, ep2d, ainfo, ErrMessage]  = BrikLoad(ep2d_fn);
xdim = size(ep2d,1);
ydim = size(ep2d,2);
zdim = size(ep2d,3);
tdim = size(ep2d,4);

% read mask
[err, mask, Info, ErrMessage]  = BrikLoad(mask_fn);
mask(find(mask))=1;

% calculate mean
ep2d_mean = mean(ep2d,4);

% convert to 2D matrix
mask_vec = mask(:);
nvox = length(mask_vec);

img_vec = reshape(ep2d,[xdim*ydim*zdim tdim]);
imgc_vec = img_vec(find(mask_vec),:);

avg_vec = ep2d_mean(:);
avgc_vec = avg_vec(find(mask_vec));

% demeaned by average signal, 
% normalized by mean sign, not whole BRAIN
avgc_vec_2d = repmat(avgc_vec,1,tdim);
imgc_vec_norm = 100*(imgc_vec-avgc_vec_2d)./avgc_vec_2d;

% calcualge VARS
sstd = zeros(tdim,1);
for t = 2:tdim  
  tmask_vec = isfinite(imgc_vec_norm(:,t));
  nvox = sum(tmask_vec);
  tmp = imgc_vec_norm(find(tmask_vec),t);
  sstd(t) = sqrt(sum(tmp.^2)/nvox);
end

