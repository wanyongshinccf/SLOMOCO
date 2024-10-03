function [fdJ fdP ifdJ ifdP ifdJ_out ifdP_out] = calcFD_adv(vol_filename,sli_filename)
 % fdJ: FD Jenkinson (RMS)
 % fdP: FD Power, Neuroimage, 2012

% read rigid volume motion parameters
volmot = load(vol_filename);
slimot = load(sli_filename);
% volregstr={'z-rot','x-rot','y-rot','z-trans','x-trans','y-trans'};

%
tdim = size(volmot,1);
zdim = size(slimot,1)/tdim;

% define radius
r = 50; %mm

% calculate FD(Power)
dxyz =volmot(:,[5 6 4]);
rxyz = volmot(:,[2 3 1]);

% difference
ddxyz = diff(dxyz);
drxyz = diff(rxyz);

% calculate FD (Power)
fdP = zeros(tdim,1);
fdP(2:end) = mean(abs(ddxyz),2) + r*mean(abs(drxyz),2);

% calculate FD(Jenkinson)

% constant from radion to degree
d2r=0.01745329;

fdJ = zeros(tdim,1);
for rep = 2:tdim
  dxyz_rep = ddxyz(rep-1,:);
  
  %
  rx = drxyz(rep-1,1)*d2r;
  ry = drxyz(rep-1,2)*d2r;
  rz = drxyz(rep-1,3)*d2r;
  
  xrot = [1 0 0; 0 cos(rx) -sin(rx); 0 sin(rx) cos(rx)];
  yrot = [cos(ry) 0 sin(ry); 0 1 0; -sin(ry) 0 cos(ry)];
  zrot = [cos(rz) -sin(rz) 0; sin(rz) cos(rz) 0; 0 0 1];
  M = zrot*yrot*xrot;
  
  fdJ(rep) = sqrt(r * r / 5.0 * trace((M-eye(3))'*(M-eye(3))) + sum(dxyz_rep.^2) );
end          

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% new intra-volume FD calculation

% calculate FD(Power)
dxyz =slimot(:,[5 6 4]);
rxyz = slimot(:,[2 3 1]);

% difference
ddxyz = diff(dxyz);
drxyz = diff(rxyz);

% calculate intravolume FD (Power)
ifdP = zeros(tdim,1);
ifdP_sli = zeros(tdim*zdim,1);

ifdP_sli(2:end,:) = mean(abs(ddxyz),2) + r*mean(abs(drxyz),2);
temp = reshape(ifdP_sli,[zdim,tdim]);
ifdP(:) = mean(temp,1);

% calculate intravolume FD (Jenkinson)

ifdJ_sli = zeros(tdim*zdim,1);
for rep = 2:tdim*zdim
  dxyz_rep = ddxyz(rep-1,:);
  
  %
  rx = drxyz(rep-1,1)*d2r;
  ry = drxyz(rep-1,2)*d2r;
  rz = drxyz(rep-1,3)*d2r;
  
  xrot = [1 0 0; 0 cos(rx) -sin(rx); 0 sin(rx) cos(rx)];
  yrot = [cos(ry) 0 sin(ry); 0 1 0; -sin(ry) 0 cos(ry)];
  zrot = [cos(rz) -sin(rz) 0; sin(rz) cos(rz) 0; 0 0 1];
  M = zrot*yrot*xrot;
  
  ifdJ_sli(rep) = sqrt(r * r / 5.0 * trace((M-eye(3))'*(M-eye(3))) + sum(dxyz_rep.^2) );
end          

ifdJ = zeros(tdim,1);
temp = reshape(ifdJ_sli,[zdim,tdim]);
ifdJ(:) = mean(temp,1);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% calculate out-of-plane intravolume FD (Power)
dxyz =zeros(tdim*zdim,3);
dxyz(:,3) =slimot(:,4);
rxyz =zeros(tdim*zdim,3);
rxyz(:,1) =slimot(:,2);
rxyz(:,2) =slimot(:,3);

% difference
ddxyz = diff(dxyz);
drxyz = diff(rxyz);

% calculate intravolume FD (Power)
ifdP_out = zeros(tdim,1);
ifdP_sli = zeros(tdim*zdim,1);

ifdP_sli(2:end,:) = mean(abs(ddxyz),2) + r*mean(abs(drxyz),2);
temp = reshape(ifdP_sli,[zdim,tdim]);
ifdP_out(:) = mean(temp,1);

% calculate FD(Jenkinson)

% constant from radion to degree
d2r=0.01745329;

ifdJ_sli = zeros(tdim*zdim,1);
for rep = 2:tdim*zdim
  dxyz_rep = ddxyz(rep-1,:);
  
  %
  rx = drxyz(rep-1,1)*d2r;
  ry = drxyz(rep-1,2)*d2r;
  rz = drxyz(rep-1,3)*d2r;
  
  xrot = [1 0 0; 0 cos(rx) -sin(rx); 0 sin(rx) cos(rx)];
  yrot = [cos(ry) 0 sin(ry); 0 1 0; -sin(ry) 0 cos(ry)];
  zrot = [cos(rz) -sin(rz) 0; sin(rz) cos(rz) 0; 0 0 1];
  M = zrot*yrot*xrot;
  
  ifdJ_sli(rep) = sqrt(r * r / 5.0 * trace((M-eye(3))'*(M-eye(3))) + sum(dxyz_rep.^2) );
end          

ifdJ_out = zeros(tdim,1);
temp = reshape(ifdJ_sli,[zdim,tdim]);
ifdJ_out(:) = mean(temp,1);
