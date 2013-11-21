function [PDcombineInfo]=mrQ_BuildCoilsfitsPD(outDir,proclus,exsistFit,M0cfile,sqrtF,GEDIr)
%
% mrQ_BuildCoilsfitsPD(outDir,M0cfile,intervals,sqrtF,GEDIr)
%
% # Build the PD from the image boxes we fit before
% (mrQ_fitPD_multicoil.m).
% the function load the fitted image boxes find the box are off by a scalre
% we first try to estimate a scalere of all the boxes
% then we combine and avrage the overlap boxes (median). last we check for
% a smooth gain map between this fitted PD and the M0 image.
%
%
% INPUTS:
% outDir - The output directory - also reading file from there
%
% proclass - if to use procluss
%
% exsistFit - in case this function was runbefore and the coils waits
% are avilable we can continue from there
%
% M0cfile - The combined/aligned M0 data
%
% sqrtF - use the sqrt of the signal (defult is no zero)
%
% GEDIr -the directory where the fitLog.mat where saved. this structure have all the needed parameter to build the PD map.
%
% OUTPUTS
%we save a list of the path for the files we calculate the PD files the
%gain and water fraction (WF);


%% CHECK INPUTS AND SET DEFAULTS



if notDefined('exsistFit')
    exsistFit =[];
end
% if the M0cfile is not an input we load the file that was made by mrQ_multicoilM0.m (defult)

if notDefined('M0cfile')
    M0cfile = fullfile(outDir,'AligncombineCoilsM0.nii.gz');
end
 if ~exist(M0cfile,'file')
        disp(' can not find the multi coils M0 file')
        error
    end
% load the fit parameter and define a outDir1 where we will save the
% intermidate files
if(exist('GEDIr','var') && ~isempty(GEDIr))
    logname=[GEDIr '/fitLog.mat'];
    outDir1=GEDIr;
     load(logname);
     JBname=[GEDIr '/M0boxfit_iter'] ;


else
    
% outDir1=outDir;
    logname=[outDir '/fitLog.mat'];
     load(logname);
    JBname=opt{1}.name;%[dirname '/M0boxfit_iter'] ;
outDir1=fileparts(JBname);
end


if isfield(opt{1},'sqrtF')
    sqrtF=(opt{1}.sqrtF);
end
if(~exist('sqrtF','var') || isempty(sqrtF))
    sqrtF=0;
end

BMfile=fullfile(outDir,'brainMask.nii.gz');

if(exist(BMfile,'file'))
  % disp(['Loading brain Mask data from ' BMfile '...']);
    brainMask = readFileNifti(BMfile);
    xform=brainMask.qto_xyz;
    mmPerVox= brainMask.pixdim;
    brainMask=logical(brainMask.data);

else
    disp(['error , can not find the file: ' BMfile]);
end;


% Define the mask that will be used to find the boxes to fit
% Create morphological structuring element (STREL)
NHOOD=[0 1 0; 1 1 1; 0 1 0];
NHOOD1(:,:,2)=NHOOD;

NHOOD1(:,:,1)=[0 0 0; 0 1 0; 0 0 0];
NHOOD1(:,:,3)=NHOOD1(:,:,1);
SE = strel('arbitrary', NHOOD1);

% parameter of the image box we will load

jumpindex=opt{1}.jumpindex;
jobindexs=1:ceil(length(opt{1}.wh)/jumpindex);

%%
% This loop checks if all the outputs have been saved or waits until
% they are all done, it it's too long run again

if (exist(exsistFit,'file'))
    StopAndload=1;
else


StopAndload=0;
fNum=ceil(length(opt{1}.wh)/jumpindex);
sgename=opt{1}.SGE;
tic
while StopAndload==0
    % List all the files that have been created from the call to the
    % grid
    list=ls(outDir1);
    % Check if all the files have been made. If they are, then collect
    % all the nodes and move on.
    if length(regexp(list, '.mat'))>=fNum,
        StopAndload=1;
        % Once we have collected all the nodes we delete the sge outpust
        eval(['!rm -f ~/sgeoutput/*' sgename '*'])
    else
        qStatCommand = [' qstat | grep -i job_' sgename(1:6)];
        [status result] = system(qStatCommand);
               tt=toc;
            if (isempty(result) && tt>60)
            % then the are no jobs running we will need to re run it.
            
            %we will rerun only the one we need
            reval=[]
            ch=[1:jumpindex:length(opt{1}.wh)]; %the sge nude files name
            k=0;
            reval=[];
            for ii=1:length(ch),
                ex=['_' num2str(ch(ii)) '_'];
                if length(regexp(list, ex))==0, %lets find which files are missing
                    k=k+1;
                    reval(k)=(ii); % list of file for sge reavaluation
                end
            end;
            if length(find(reval))>0
                
                % clean the sge output dir and run the missing fit
                    eval(['!rm -f ~/sgeoutput/*' sgename '*'])
                    if proclus==1
                      for kk=1:length(reval)
                sgerun2('FitM0_sanGrid_v2(opt,jumpindex,jobindex);',[sgename num2str(kk)],1,reval(kk),[],[],5000);% we run the missing oupput again
                      end
                    else
                sgerun('FitM0_sanGrid_v2(opt,jumpindex,jobindex);',sgename,1,reval,[],[],5000);% we run the missing oupput again
                    end
                end
                
% eval(['!rm /home/avivm/sgeoutput/*' sgename '*']) % we delete all our relevant grid jobs
% sgerun('FitM0_sanGrid_v2(opt,jumpindex,jobindex);',sgename,1,reval,[],[],5000);% we run the missing oupput again
%
            else
           % keep waiting
            end
        end
        
    end
end
 %% load the fit
     [opt{1}.Poly,str] = constructpolynomialmatrix3d(opt{1}.boxS,find(ones(opt{1}.boxS)),opt{1}.degrees);

%initilaized the parameters
    Fits=zeros(opt{1}.numIn,size(opt{1}.Poly,2),length(opt{1}.wh));
    resnorms=zeros(length(opt{1}.wh),1);
    exitflags=zeros(length(opt{1}.wh),1);
    CoilsList=zeros(length(opt{1}.wh),opt{1}.numIn);

    opt{1}.brainMask=brainMask;


% loop over the fitted box files and load the parameters to matrixs
    for i=1:length(jobindexs);



        st=1 +(jobindexs(i)-1)*jumpindex;
        ed=st+jumpindex-1;
        if ed>length(opt{1}.wh), ed=length(opt{1}.wh);end;

        Cname=[JBname '_' num2str(st) '_' num2str(ed)];
        load(Cname);
        ss=length(resnorm);
        if isempty(res)
            res=0;
        end

         Fits(:,:,st:st+ss-1)=res;
        resnorms(st:st+ss-1)=resnorm;
        exitflags(st:st+ss-1)=exitflag;
        
        CoilsList(st:st+ss-1,:)= coilList(:,1:ss)';

    end;
%%
% load the M0 imaged that was used to the fit (multi coils 4D)
    M=readFileNifti(M0cfile);
    coils=size(M.data,4);
    
    
    
    %% combine the fitted boxes
        disp(' combine the PD image parts ')

     if (exist(exsistFit,'file'))
         load (exsistFit)
    else
    % first crate a matrix (mat) that build for liniaer eqation estimation
    % the function mrQ_BoxsAlignment look for the gain that each box need
    % to mach it nibohor.
    % one books Reference are arbitrary made to be equal one
    % mat is build that we add one box and substracting the other box so it
    % the eqation equal zero.
    %we have box/box matrix that eqal zerow beside one box that equal one
    
    
   
    [mat err Reference matdc]= mrQ_BoxsAlignment(M,opt,Fits,CoilsList,sqrtF);

       name=[outDir1 '/tmpFit' date];
    %toc
     save(name,'mat', 'err', 'Reference', 'matdc')
    
 
PDcombineInfo.boxAlignfile=name;
    end
  
  % we can try to solve the mat eqation as set of lalinear eqation
  % this will find the best boxs scaler that when we add it to the other that overlap to it they will cancel wach other.
  %and the Reference will equal one.
% mat*C=y
  % y is zeors (box X 1) with a single 1 in the reference box location
  % mat is the eqtions of adding the niboring boxes
  % C is the scals of the box (that we try to find)
  
%y=mat(Reference,:);
%y=y';
y=zeros(size(err,1),1);
y(Reference)=1;
%solve it as multi linear eqation
C=pinv(mat'*mat)*mat'*y;
% the C we need is one over the one we fit
C1=1./C;

% now when we have the scales we can combine the boxes
%we like to exlude crazy boxs (very high or low scale
% we know that C sepuuse to be around 1 if every thing went right

wh1=find(C1>0.1 & C1<2);
%
%in orther to avrage we need to keep track of the nmber of estimation of
%each voxel (overlaping boxes makes it grater then one). we will keep
%records on that by Avmap
Avmap=zeros(size(M.data(:,:,:,1)));
%we will save the avrage in M0f
M0f=zeros(size(M.data(:,:,:,1)));
%we will save the values for median avrage in M0full
M0full=M0f(:);

%loop over the boxs
for jj=1:length(wh1),
   % jj
    clear BB do_now fb Xx Yy Zz skip inDat In use G Gain1 Val W t ResVal wh whh mask bm c SS SD MR Val1
    %what box to use
    BB=(wh1(jj));
do_now=opt{1}.wh(BB);

%set mask
mask=zeros(size(M.data(:,:,:,1)));
%get the location of the box in x,y,z cordinate
[fb(1,1) fb(1,2) fb(1,3)]=ind2sub(size(opt{1}.X),do_now);
[Xx Yy Zz,skip]=MrQPD_boxloc(opt{1},fb);

%get the coil list we used in the box
In=CoilsList(BB,:);
use=(find(In));
use=(find(CoilsList(BB,:)));

%load the raw M0 data that was fitted
if sqrtF==1
    %for the case of sqrt on theM0 images (not the defult)
    inDat(:,:,:,:)=double(sqrt(M.data(Xx(1):Xx(2),Yy(1):Yy(2),Zz(1):Zz(2),In(use))));
else
    inDat(:,:,:,:)=double(M.data(Xx(1):Xx(2),Yy(1):Yy(2),Zz(1):Zz(2),In(use)));
end
% get the fitted coefisent of the coil gain estimated by polynomials
G=Fits(use,:,BB);

%calculate PD (val1) from raw M0 images and coils gain
for i=1:size(inDat,4),%opt.numIn
    %
    Gain1(:,:,:,i) = reshape(opt{1}.Poly*G(i,:)',opt{1}.boxS);
    Val1(:,:,:,i) = inDat(:,:,:,i)./Gain1(:,:,:,i);
end;

% we can wait the PD by SNR% we desice not to do that becouse it can bias
% the fits
% W=inDat; %lets wait by coils
% for i=1:size(inDat,4)
% t=inDat(:,:,:,i);
% W(:,:,:,i)=mean(t(:));
% end
% W=W./sum(W(1,1,1,:));
%ResVal=sum(Val1.*W ,4); %waited the coils by SNR

% get the avrage PD fit of the different coils
ResVal=mean(Val1,4); %


% get the brain mask of the boxs in box space
bm=opt{1}.brainMask(Xx(1):Xx(2),Yy(1):Yy(2),Zz(1):Zz(2));
% get the brain mask of the boxs in full imaging space
mask(Xx(1):Xx(2),Yy(1):Yy(2),Zz(1):Zz(2))=opt{1}.brainMask(Xx(1):Xx(2),Yy(1):Yy(2),Zz(1):Zz(2));
mask=logical(mask);

%control for outlayers
c=((std(Val1,[],4)));
wh=find(mask);
SS=c(bm);
Val=ResVal(bm);
SD=std(ResVal(bm));
MR=mean(ResVal(bm));

if (any(Val<0)) %if we still have few nagative values we won't use them for alighnment (happan in the edge of the brain air or noise voxels
        whh=find(Val>0);
        Val=Val(whh);
        wh=wh(whh);
        SS=SS(whh);
    end
    if any(Val>(MR+3*SD)) %if we have very high values e won't use them (happan in the edge of the brain air or noise voxels or some csf voxel that have very low SNR)
        whh=find(Val<(MR+3*SD));
        Val=Val(whh);
        wh=wh(whh);
        SS=SS(whh);
        
    end
    if any(Val<(MR-3*SD))%if we still have few very low value (happan in the edge of the brain air or noise voxels or some csf voxel that have very low SNR)
        whh=find(Val>(MR-3*SD));
        Val=Val(whh);
        wh=wh(whh);
        SS=SS(whh);
        
    end
    
    if any(SS>0.06)% if part of this box is unconclusive so the std between the different coils is very high we better not use it. that happean it the edge of the boxs becouse of miss fit; or when single to noise is low like csf or air edge
        whh=find(SS<0.06);
        Val=Val(whh);
        wh=wh(whh);
    end
    
%add this box data to the other

% mutipal the result by it scaler
ResVal=ResVal.*C1(BB);
% for mean avraging
M0f(wh)=M0f(wh)+Val.*C1(BB);
Avmap(wh)=Avmap(wh)+1;

%this is to mesure the median avraging
szz1=size(M0full,2);
Raw=max(max(Avmap(:)),szz1);
Col=length(M0f(:));
szz=[Col,Raw ];

tmp=zeros(szz);
tmp(:,1:szz1)=M0full;

wh0= sub2ind(szz,wh,Avmap(wh));
tmp(wh0)=Val.*C1(BB);
M0full=tmp;

end
%%
% mean avrage the PD values
M0f(find(M0f))=M0f(find(M0f))./Avmap(find(M0f));

%median avrage the PD values
M0full(M0full==0)=nan;
M0full=nanmedian(M0full,2);
M0full=reshape(M0full,size(M0f));

%% save the median and mean PD
PDfile2=fullfile(outDir1,['PD_fitGboxMedian.nii.gz']);

PDfile1=fullfile(outDir1,['PD_fitGboxmean.nii.gz']);

if sqrtF==1
    %if sqrt was applied we will undo it now
 dtiWriteNiftiWrapper(single(M0f).^2, xform, PDfile1);
  dtiWriteNiftiWrapper(single(M0full).^2, xform, PDfile2);

else
    dtiWriteNiftiWrapper(single(M0f), xform, PDfile1);
    dtiWriteNiftiWrapper(single(M0full), xform, PDfile2);

 
end
PDcombineInfo.meanFile=PDfile1;
PDcombineInfo.meadianFile=PDfile2;

%% finalizing the PD fits
% the fitted PD is still not complited becouse some area add cruzy fits or
% no fits for different reason. the saved PD are therefore still with holls
% also some time the edged between the boxes can still appear (not a
% perfect scale estimation or boxs fits).
%the last step
% in the last step % we will derive the gain by devide M0/pd=Gain for each coil.
%we will asume that the gain must be smooth (we now it is, realy) so we
%will smooth it and get a full PD. and WF maps.


 [PDcombineInfo.WFfile1,PDcombineInfo.Gainfile1]=mrQ_WFsmooth(outDir,[],PDfile2,[],[],[],outDir);

%
              % [M0f,donemask,Avmap,errVal] =mrQM0fiti_Res1(opt{1},fb,G,inDat,M0f,donemask,known,Avmap,resnorms(BB),exitflags(BB),errVal);
% [M0f,donemask,Avmap,errVal] =mrQM0fiti_Res2(opt{1},fb,G,inDat,M0f,donemask,known,Avmap,resnorms(BB),exitflags(BB),errVal);

          
    

    
    
   % a=1;
    return
    
  