function [fd fdd fddz] = calcFD(vol_filename)

mopa6 = load(vol_filename);
% volregstr={'z-rot','x-rot','y-rot','z-trans','x-trans','y-trans'};

% convert degree to mm
img = zeros(120,120,120);
disphere = zeros(120,120,120);
cnt = [61 61 61];
raddeg=0.01745329;

dxyz = zeros(size(mopa6,1) -1,3);
fdd = zeros(size(mopa6,1) -1,1);
fddz = zeros(size(mopa6,1) -1,1);
for t = 2:size(mopa6,1)    
  drots = mopa6(t,[2 3 1])-mopa6(t-1,[2 3 1]);
  dshift = mopa6(t,[5 6 4])-mopa6(t-1,[5 6 4]);
  
  xr = drots(1)*raddeg;
  yr = drots(2)*raddeg;
  zr = drots(3)*raddeg;
  
  cz=cos(zr*raddeg);
  sz=sin(zr*raddeg);
  cx=cos(xr*raddeg);
  sx=sin(xr*raddeg);
  cy=cos(yr*raddeg);
  sy=sin(yr*raddeg);
    
  dxrot=0;dyrot=0;dzrot = 0;
  displ=0; displz=0;
  for z = 1:120
    for y = 1:120
      for x = 1:120
        dist = sqrt((x-61)^2+(y-61)^2+(z-61)^2);
        if abs(dist-50) < 1
          img(x,y,z)=1;
          xrot = [1 0 0; 0 cos(xr) -sin(xr); 0 sin(xr) cos(xr)];
          yrot = [cos(yr) 0 sin(yr); 0 1 0; -sin(yr) 0 cos(yr)];
          zrot = [cos(zr) -sin(zr) 0; sin(zr) cos(zr) 0; 0 0 1];
          dxrot = sqrt(sum(([x-61; y-61; z-61] - xrot*[x-61; y-61; z-61]).^2)) + dxrot;
          dyrot = sqrt(sum(([x-61; y-61; z-61] - yrot*[x-61; y-61; z-61]).^2)) + dyrot;
          dzrot = sqrt(sum(([x-61; y-61; z-61] - zrot*[x-61; y-61; z-61]).^2)) + dzrot;
          
          dx=(cz*cy-sz*sx*sy)*x + (sz*cy+cz*sx*sy)*y - (cx*sy)*z + dshift(1) - x;
          dy=        (-sz*cx)*x +          (cz*cx)*y +    (sx)*z + dshift(2) - y;
          dz=(cz*sy+sz*sx*cy)*x + (sz*sy-cz*sx*cy)*y + (cx*cy)*z + dshift(3) - z;

          displ  = displ + sqrt(dx^2+dy^2+dz^2);
          displz = displz + sqrt(dz^2);
      end
    end
    end
  end
  drot(t-1,1:3) = [dxrot dyrot dzrot];
  
  fdd(t-1) = displ;
  fddz(t-1) = displz;
end
drot = drot/sum(img(:));  
fdd = fdd/sum(img(:));
fddz = fddz/sum(img(:));

% disp
dxyz = zeros(size(mopa6,1)-1,3);
for t = 2:size(mopa6,1)    
dxyz(t-1,:) = abs(mopa6(t,[2 3 1])-mopa6(t-1,[2 3 1]));
end

fd = (mean(dxyz,2) + mean(drot,2));
