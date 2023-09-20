function gen_regout(ep2d_filename,mask_filename,varargin)
%function slicemoco_regout(ep2d_filename,mask_filename,filestr,polortMat,physiostr)
    
physiostr='';
Opt.Format = 'matrix';
for i=1:floor(length(varargin)/2)
  option=varargin{i*2-1};
  option_value=varargin{i*2};
  switch lower(option)
    case 'polort'
      polortmat=option_value;
    case 'physiostr'
      physiostr=option_value;
    case 'volreg'
      vol_filename=option_value  ;
    case 'slireg'
      sli_filename=option_value  ;
    case 'voxreg'
      vox_filename=option_value  ;
    case 'out'
      output_filename=option_value  
    otherwise
      fprintf('unknown option [%s]!\n',option);
      fprintf('error!\n');
      return;
  end;
end

if exist('polortmat')
  polort_reg = load(polortmat);
else
  polort_reg = [];
  disp('baseline and linear detrending regressors should be included')
  disp('result might not be trustable')
end
if strcmp(physiostr,'p')
  nreg = size(polort_reg,2) + 14 + 8;
  load ../PHYSIO/RetroTS.PMU.mat
elseif strcmp(physiostr,'r')
  load ../PESTICA5/RetroTS.PESTICA5.mat
  resp_vols=convert_timeseries_to_slicextime(RESP.v,uniq_acq_order);
else
  nreg = size(polort_reg,2) + 14 ;
end
if ~exist('output_filename')
  strn=strfind(ep2d_filename,'+orig');
  output_filename = [ep2d_filename(1:strn-1) '.slomoco+orig'];
end 
if exist('vol_filename')
  volreg=load(vol_filename);
  for n = 1:size(volreg,2)
    temp = volreg(:,n);
    temp = temp-mean(temp);
    absmax = max(abs(temp));
    volreg(:,n) = temp./absmax;
  end
else
  volreg=[];
end
if exist('sli_filename')
  slireg=load(sli_filename); % tdim x (zdim*6)
  for n = 1:size(slireg,2)
    temp = slireg(:,n);
    temp = temp-mean(temp);
    absmax = max(abs(temp));
    slireg(:,n) = temp./absmax;
  end
else
  slireg=[];
end
if exist('vox_filename')
  [err, voxreg, minfo, ErrMessage]=BrikLoad(vox_filename, Opt);
else
  voxreg=[];
end

%disp('warning, motionparams must be in form x y z then 9-element rotation matrix on oneline');
[err, im, ainfo, ErrMessage]=BrikLoad(ep2d_filename, Opt);
xdim=ainfo.DATASET_DIMENSIONS(1);
ydim=ainfo.DATASET_DIMENSIONS(2);
zdim=ainfo.DATASET_DIMENSIONS(3);
tdim=ainfo.DATASET_RANK(2);
dx=ainfo.DELTA(1);
dy=ainfo.DELTA(2);
dz=ainfo.DELTA(3);
TR=double(ainfo.TAXIS_FLOATS(2));

% check time unit
[TRsec TRms] = TRtimeunitcheck(TR);
slice_timing_sec = load('tshiftfile.1D');
[MB zmbdim uniq_slice_timing_sec uniq_acq_order] = SMSacqcheck(TRsec, zdim, slice_timing_sec);

% load mask file
[err, im_mask, minfo, ErrMessage]=BrikLoad(mask_filename, Opt);
im_mask(find(im_mask))=1;
                     
% sanity check
if ~isempty(polort_reg) && (size(polort_reg,1) ~= tdim )
  disp('the length of poloynomial detrending regressor does not match input EPI')
  return
end
if ~isempty(volreg) && (size(volreg,1) ~= tdim )
  disp('the length of volume 1D does not match input EPI')
  return
end
if ~isempty(slireg) && (size(slireg,1) ~= tdim )
  disp('the colume length of slice 1D does not match input EPI')
  return
elseif  ~isempty(slireg) && (size(slireg,2) ~= zdim*6 ) 
  disp('the row length of slice 1D does not match input EPI')
  return
end
if ~isempty(voxreg) && (size(voxreg,4) ~= tdim )
  disp('the length of pv regressor does not match input EPI')
  return
end

% define variables  
errtmap = zeros(xdim,ydim,zdim,tdim);

% start with volreg               
Avol = [polort_reg volreg];

% due to propensity for regressors to covary (and thus solution be ill-conditioned), use more robust least-squares methods  
warning off all

for k= 1:zdim
  if strcmp(physiostr,'p')  
    Pr = [squeeze(RESP.phz_slc_reg(:,1:2*2,k))];
    Pc = [squeeze(CARD.phz_slc_reg(:,1:2*2,k))];
  elseif strcmp(physiostr,'r')
    Pr = [resp_vols(k,:)'];
    Pc = [squeeze(CARD.phz_slc_reg(:,1:4,kmb)) ];
  else
    Pr = []; Pc = []; 
  end
  
  % if slicewise regressor exists
  if isempty(slireg)
    Asli = [Avol Pc Pr];
  else
    Asli = [Avol Pc Pr squeeze(slireg(:,6*(k-1)+1:k*6))];
  end
  
  for i=1:xdim
    for j=1:ydim
      if im_mask(i,j,k)
        errt = squeeze(im(i,j,k,:));
        SD=std(errt);
        if SD
            errt_norm = errt/SD;
            
            if isempty(voxreg)
                A = Asli;
            else
                A = [Asli squeeze(voxreg(i,j,k,:))];
            end
            
            % solve linear regression
            [p, std_err]  = lscov(A, errt_norm);
            res = errt_norm - A*p;    RSS  = res'*res;
            % regress out physiologic noise, but keep the trending lines
            p(1)=0;
            errt_errt = errt_norm - (A*p);
            errtmap(i,j,k,:) = errt_errt*SD;
        else
            errtmap(i,j,k,:) = errt;
        end
      end
    end
  end
  if k == zdim
    fprintf([num2str(k) '\n']);
  elseif k==1
    fprintf(['slice ' num2str(k) '.']);
  else
    fprintf('.');
  end
end
warning on all

% set Nan Inf value to zero
errtmap(~isfinite(errtmap(:)))=0;

% use same ainfo as we read in from the original data file
ainfo.BRICK_TYPES=3*ones(1,tdim); % 1=short, 3=float
ainfo.BRICK_FLOAT_FACS = [];      % automatically set
ainfo.BRICK_LABS = [];
ainfo.BRICK_KEYWORDS = [];
OptOut.Scale = 0;                 % no scaling
OptOut.OverWrite= 'y';            % overwrite if exists
OptOut.verbose = 0;
OptOut.Prefix = output_filename;
[err,ErrMessage,InfoOut]=WriteBrik(errtmap,ainfo,OptOut);
