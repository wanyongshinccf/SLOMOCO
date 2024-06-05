function gen_regout(ep2d_filename,mask_filename,varargin)
    
polortmat=''; 
phy_filename=''; 
vol_filename=''; 
sli_filename=''; 
vox_filename=''; 
output_filename='';
Opt.Format = 'matrix';
RVTflag = 0 % (W.S 20240605) set it to 1 if you like to include 5 RVT regressors

for i=1:floor(length(varargin)/2)
  option=varargin{i*2-1};
  option_value=varargin{i*2};
  switch lower(option)
    case 'polort'
      polortmat=option_value;
    case 'physio'
      phy_filename=option_value;
    case 'volreg'
      vol_filename=option_value  ;
    case 'slireg'
      sli_filename=option_value  ;
    case 'voxreg'
      vox_filename=option_value  ;
    case 'out'
      output_filename=option_value;  
    otherwise
      fprintf('unknown option [%s]!\n',option);
      fprintf('error!\n');
      return;
  end;
end

if exist(polortmat,'file')
  polort_reg = load(polortmat);
else
  polort_reg = [];
  disp('Baseline and linear detrending regressors is not included')
  msg=sprintf('echo Baseline and linear detrending regressors is not included >> slomoco_history.txt');
  system(msg);
  disp('Caution: You should know what you are doing')
  msg=sprintf('echo Caution: You should know what you are doing >> slomoco_history.txt');
  system(msg);
end

if exist(phy_filename,'file')
  P = load(phy_filename);
else
  disp('Physio regressor file is not provided or found')
  msg=sprintf('echo Physio regressor file is not provided or found >> slomoco_history.txt');
  system(msg);
  P = [];
end

if isempty(output_filename)
  disp('Output filename is not provided.')
  strn=strfind(ep2d_filename,'+orig');
  output_filename = [ep2d_filename(1:strn-1) '.slomoco+orig'];
end
 
if exist(vol_filename,'file')
  volreg=load(vol_filename);
  for n = 1:size(volreg,2)
    temp = volreg(:,n);
    temp = temp-mean(temp);
    absmax = max(abs(temp));
    volreg(:,n) = temp./absmax;
  end
else
  disp('Note that 6 volume motion parameters are not regressed out.')
  msg=sprintf('echo Note that 6 volume motion parameters are not regressed out >> slomoco_history.txt');
  system(msg);
  disp('Caution: You should know what you are doing')
  msg=sprintf('echo Caution: You should know what you are doing >> slomoco_history.txt');
  system(msg);
  volreg=[];
end

if exist(sli_filename,'file')
  slireg=load(sli_filename); % tdim x (zdim*6)
  for n = 1:size(slireg,2)
    temp = slireg(:,n);
    temp = temp-mean(temp);
    absmax = max(abs(temp));
    if absmax
      slireg(:,n) = temp./absmax;
    else
      disp(['Warning: Found all zero slice motion at ' num2str(n)])
      msg=sprintf('echo Warning: Found all zero motion in slice %d >> slomoco_history.txt', n);
      system(msg);
      slireg(:,n) = temp;
    end
  end
else
  disp('Note that slicewise motion parameters are not regressed out.')
  msg=sprintf('echo Note that slicewise motion parameters are not regressed out >> slomoco_history.txt');
  system(msg);
  disp('Caution: You should know what you are doing')
  msg=sprintf('echo Caution: You should know what you are doing >> slomoco_history.txt');
  system(msg);
  slireg=[];
end

if exist([vox_filename '.HEAD'],'file')
  [err, voxreg, minfo, ErrMessage]=BrikLoad(vox_filename, Opt);
else
  disp('Note that voxelwise PVs are not regressed out.')
  msg=sprintf('echo Note that voxelwise PVs are not regressed out >> slomoco_history.txt');
  system(msg);
  disp('Caution: You should know what you are doing')
  msg=sprintf('echo Caution: You should know what you are doing >> slomoco_history.txt');
  system(msg);
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
if ~isempty(P)
  [tdimp regn] = size(P); 
  regn=regn/zdim;
  if (regn == 13) && (RVTflag == 0) % we assumed RVT is included
    disp('RETROICOR regressors are included')
    disp('RVT is excluded from RetroTS.pmu.slicebase.1D')
    disp('If you like to include 5 RVT regressor, set RVTflat to one in gen_regout.m');
    P_temp = [];
    for z = 1:zdim
  	  P_temp = [P_temp P(:,13*z-7:13*z)];
  	end
  	P = P_temp;
  	[tdimp regn] = size(P);
  	if ( regn ~= 8)
  	  disp('Error: the number of RETROICOR regressors is expected to be 8')
  	  return
  	end
  elseif ( regn == 8 ) 
    disp('RETROICOR regressors are included')
  elseif (regn == 5 ) 
    disp('PESTICA regressors are included')
  else
  	disp('Error: the number of physio regressors is expected to be 8 or 5')
  	return
  end
  disp(['Number of physio regressors is ' num2str(regn) ]) 
end

% define variables  
errtmap = zeros(xdim,ydim,zdim,tdim);

% start with volreg               
Avol = [polort_reg volreg];

% due to propensity for regressors to covary (and thus solution be ill-conditioned), use more robust least-squares methods  
warning off all
dofdispflag=1;
for k= 1:zdim
  if isempty(P)  
    Psli=[];
  else
    Psli= P(:,regn*(k-1)+1:regn*k); 
  end
  
  % if slicewise regressor exists
  if isempty(slireg)
    Asli = [Avol Psli];
  else
    Asli = [Avol Psli squeeze(slireg(:,6*(k-1)+1:k*6))];
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
            if dofdispflag
              disp(['Number of all nuisance regressors is ' num2str(size(A,2))])
              dofdispflag = 0;
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
