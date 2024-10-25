function [volslimot_final slimot_final_jiang] =  qa_moco(volmoco_fn, slomoco_fn, mask_fn, vol_fn, sli_fn)
%function [volslimot_final slimot_final_jiang] =  qa_moco(volmoco_fn, slomoco_fn, mask_fn, vol_fn, sli_fn)
% script generates FD(Power), FD(Jenkinson), iFD(P), iFD(J),
% iFD(P/J)_outofplane, DVARS, and QS ifgures
 
volmoco_fn='epi_03_volmoco+orig';
slomoco_fn='epi_03_slicemoco_xy.slomoco+orig';
mask_fn='epi_base_mask+orig';
vol_fn='epi_01_volreg.1D';
sli_fn='slimot_py_fit.txt';

% calculate FD(Power), FD(Jenkinson), iFD(P/J), iFD_out-of-plane (P/J)
[FDJ FDP iFDJ iFDP ioFDJ ioFDP] = calcFD_adv(vol_fn,sli_fn);

% calculage DVARS
% note that DVARS is calculated AFTER motion correction
dv_volmoco= calcSSTD(volmoco_fn,mask_fn);
dv_slomoco= calcSSTD(slomoco_fn,mask_fn);

% save figure 
tdim = length(dv_volmoco);

figure
subplot(4,1,1);
[ax,h1,h2]=plotyy(2:tdim,dv_volmoco(2:end),2:tdim,dv_slomoco(2:end));
title('SSTD after motion correction (blue/red = VOLMOCO/SLOMOCO)')
set(h1,'color','b')
set(h2,'color','r')
ylabel(ax(1),'VOLMOCO') % left y-axis 
ylabel(ax(2),'SLOMOCO') % right y-axis

subplot(4,1,2);
[ax,h1,h2]=plotyy(2:tdim,FDJ(2:end),2:tdim,FDP(2:end));
title('FD (blue/red = Jenkinson / Power)')
set(h1,'color','b')
set(h2,'color','r')
ylabel(ax(1),'FDJ') % left y-axis 
ylabel(ax(2),'FDP') % right y-axis


subplot(4,1,3);
[ax,h1,h2]=plotyy(2:tdim,iFDJ(2:end),2:tdim,iFDP(2:end));
title('intra-volume FD (blue/red = Jenkinson / Power)')
set(h1,'color','b')
set(h2,'color','r')
ylabel(ax(1),'iFDJ') % left y-axis 
ylabel(ax(2),'iFDP') % right y-axis


subplot(4,1,4);
[ax,h1,h2]=plotyy(2:tdim,ioFDJ(2:end),2:tdim,ioFDP(2:end));
title('intra-volume out-of-plane FD (blue/red = Jenkinson / Power)')
set(h1,'color','b')
set(h2,'color','r')
ylabel(ax(1),'ioFDJ') % left y-axis 
ylabel(ax(2),'ioFDP') % right y-axis

x= dv_volmoco(2:end);
Cmat(1,1) = corr(x,FDJ(2:end));
Cmat(1,2) = corr(x,FDP(2:end));
Cmat(1,3) = corr(x,iFDJ(2:end));
Cmat(1,4) = corr(x,iFDP(2:end));
Cmat(1,5) = corr(x,ioFDJ(2:end));
Cmat(1,6) = corr(x,ioFDP(2:end));
x= dv_slomoco(2:end);
Cmat(2,1) = corr(x,FDJ(2:end));
Cmat(2,2) = corr(x,FDP(2:end));
Cmat(2,3) = corr(x,iFDJ(2:end));
Cmat(2,4) = corr(x,iFDP(2:end));
Cmat(2,5) = corr(x,ioFDJ(2:end));
Cmat(2,6) = corr(x,ioFDP(2:end));

saveas(gcf,'qa_volslimoco_metrics.jpg');
 
% save motion index
fp=fopen('DVARS_volmoco.txt','w'); fprintf(fp,'%g\n',dv_volmoco); fclose(fp);
fp=fopen('DVARS_slomoco.txt','w'); fprintf(fp,'%g\n',dv_slomoco); fclose(fp);
fp=fopen('FDJ.txt','w'); fprintf(fp,'%g\n',FDJ); fclose(fp);
fp=fopen('FDP.txt','w'); fprintf(fp,'%g\n',FDP); fclose(fp);
fp=fopen('iFDP.txt','w'); fprintf(fp,'%g\n',iFDP); fclose(fp);
fp=fopen('iFDJ.txt','w'); fprintf(fp,'%g\n',iFDJ); fclose(fp);
fp=fopen('ioFDJ.txt','w'); fprintf(fp,'%g\n',ioFDJ); fclose(fp);
fp=fopen('ioFDP.txt','w'); fprintf(fp,'%g\n',ioFDP); fclose(fp);
fp=fopen('CC_volmocoDVtoFD.txt','w'); fprintf(fp,'%g\n',Cmat(1,:)); fclose(fp);
fp=fopen('CC_slomocoDVtoFD.txt','w'); fprintf(fp,'%g\n',Cmat(2,:)); fclose(fp);