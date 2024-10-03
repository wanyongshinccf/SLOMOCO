function dv = calcDVARS(ep2d_filename, mask_filename, ep2d_mean_filename)
% DVARS in SLOMOCO 

% ep2d_filename='epi_03_slicemoco_xy.slomoco+orig';
% ep2d_mean_filename='epi_base_mean+orig';
% mask_filename='epi_base_mask+orig';

% read EPI input
[err, ep2d, ainfo, ErrMessage]  = BrikLoad(ep2d_filename);
xdim = size(ep2d,1);
ydim = size(ep2d,2);
zdim = size(ep2d,3);
tdim = size(ep2d,4);

% read mean EPI image AFTER motion correction
% note that it is baseline even before moco case
if exist('ep2d_mean_file','var')
  ep2d_mean = BrikLoad(ep2d_mean_filename);
else
  ep2d_mean = mean(ep2d,4);
end

% read mask
[err, mask, Info, ErrMessage]  = BrikLoad(mask_filename);
mask(find(mask))=1;


% convert to 2D matrix
mask_vec = mask(:);
nvox = length(mask_vec);

img_vec = reshape(ep2d,[xdim*ydim*zdim tdim]);
imgc_vec = img_vec(find(mask_vec),:);

avg_vec = ep2d_mean(:);
avgc_vec = avg_vec(find(mask_vec));

% normalize (%) based on WHOLE BRAIN contrast
% See 
avgc_vec_2d = repmat(avgc_vec,1,tdim);
imgc_vec_norm = 100*(imgc_vec-avgc_vec_2d)./mean(avg_vec);

% calculage whole brain si

% calcualge DV
dv = zeros(tdim,1); % W.S 20240611
for t = 2:tdim
  tmask_vec = isfinite(imgc_vec_norm(:,t));
  dc = imgc_vec_norm(find(tmask_vec),t)-imgc_vec_norm(find(tmask_vec),t-1);
  dv(t) = sqrt(sum(dc(isfinite(dc)).^2)/nvox);
end

