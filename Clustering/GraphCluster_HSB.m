function stats=GraphCluster_HSB(rmat,params)

% This function is an adaptation of ngt.graphcluster that does not  
% access the directory structure, but rather is passed it from
% the MATLAB workspace. Similarly, it outputs to the workspace, not  
% the directory structure. Bootstrapping is not supported.
% This program is currently made to be run in the folder containing the
% *.roi file (or at least have it in your path).
% Inputs:
%   rmat            matrix, Nroi-Nroi-Nsubjm, of Pearson correlations
%   params...
%       .binary     binarize at threshold
%       .type       'r' or 'kden'
%       .lo         lower value of rval or kden
%       .step       step size for analyses parameter
%       .hi         high value for rval or kden
%       .xdist      if >0, kill edges where roi sep <= xdist
%       .roi        3D roi coords for xdist flag
%       .roifname   *.roi filename for infomap call 
%               -->(make sure folder with this is in the MATLAB path)
%       .pajekfname  pajek filename for infomap call
%       .writepath  absolute path for output files
%       .fig        to create a figure of basic graph data: 
%               -->all as f(Rth,Kdenth): Nedges(K), edge_density(kden),
%                   average edges per node(kave), modularity(Q), 
%                   assortativity(A), #comps(Nc), %n_in_giant_comp(NnBc)
%
% Outputs:
%   stats.clusters                  cluster solutions
%   stats.params                    params information
%   stats.MuMat                     mean matrix used for infomapping
%   stats.modularity                modularity for each solution
%   stats.rth                       rth
%   stats.kdenth                    kdenth
%   stats.Nedges                    Nedges     
%   stats.kave                      kave       
%   stats.A                         Assortativity         
%   stats.Nc                        Number of components         
%   stats.NnBc                      Number of nodes in largest component     
%   stats.Cdns                      Connectedness


%% Set up parameters and initialize stuff
here=pwd;
if ischar(rmat),load(rmat);rmat=corrmat;clear corrmat;end
if ~exist('params','var'), params=struct; end
if ~isstruct(params)            % If params is name of *.prm file, load in
    fname=params;
    fileID=fopen(fname);
    params=struct;
    stuff=textscan(fileID,'%s');                % read the prmfile
    params.prmfile = fileID;                    % name of prm file
    params.roifname=stuff{2,1};                 % name of roi file
    params.lo=str2double(stuff{6,1});           % lo r or kden
    params.step=str2double(stuff{7,1});         % step in r or kden
    params.hi=str2double(stuff{8,1});           % hi r or kden
    params.writepathbase=stuff{9,1};                % write path
    params.type=stuff{13,1};                    % r or kden
    fclose(fileID);
end
if ~isfield(params,'binary'), params.binary=0;end
if ~isfield(params,'type'), params.type='kden';end
if ~isfield(params,'lo'), params.lo=0.01;end % 0.005
if ~isfield(params,'step'), params.step=0.001;end %0.001
if ~isfield(params,'hi'), params.hi=0.10;end % 0.25, 0.1
if ~isfield(params,'xdist'), params.xdist=21;end % was 30, sri used 21

if ~isfield(params,'writepathbase') % this folder must already exist
    params.writepathbase=[pwd,'/'];
end

if params.xdist                   % exclusion distance?
if ~isfield(params,'roi')         % if yes, need coords of ROI centers
    foo=fopen(params.roifname);
    foob=textscan(foo,'%f %f %f %f %s %s %s %s %s','HeaderLines',1);
    params.roi=[foob{1,2},foob{1,3},foob{1,4}];
    fclose(foo);
    clear foo foob
end
end
if ~isfield(params,'fig'), params.fig=1;end

%% assertions
assert(sum(sum(isnan(rmat)))==0) % make sure NaNs have been removed already they should not contribute to the assignment or edge density
%% Initialize outputs
[~,Nroi,Nsubj]=size(rmat); 
assert(Nsubj==1); % make sure any averaging takes place before this
NPE=Nroi*(Nroi-1)/2;
th=params.lo:params.step:params.hi;
Nkden=length(th);
UDidx=find(triu(ones(Nroi),1)==1);      % indices of unique conns
mods=zeros(Nroi,Nkden,'single');       % Clustering labels
[modularity,rth,kdenth,SI]=deal(zeros(Nkden,1,'single'));    % Modularity % r threshold % kden threshold  % Silhouette index           

%% Organize file structure to a temp to kill folder tree
cd(params.writepathbase)
here0=pwd;
foobr=ceil(1e7*rand(1));
GCtempFname=['temp',num2str(foobr)];
mkdir(GCtempFname)
params.writepathbase=[params.writepathbase,GCtempFname,'/']; 
cd(params.writepathbase) 
writepath=params.writepathbase;

%% Calc mean matrix across subjects
rmat0=rmat.*(~eye(Nroi)); % remove diagonal correlation

%% Do clustering
if strcmp(params.type,'mst')
            [MST] =backbone_wu_mod(rmat); %N.B.: I modified the BCT backbone function so that it only gets the backbone itself now
end

for j=1:Nkden
    
    disp(['Model ',num2str(j),' of ',num2str(Nkden)])
    rmat=rmat0;    
    
    % threshold matrix
    switch params.type
        case 'r'
            rmat(rmat<th(j))=0;
            kdenth(j)=sum(rmat(UDidx)~=0)/NPE;
            rth(j)=min(rmat(UDidx));
        case 'kden'
            EL=ceil(th(j)*NPE);
            rmat=triu(rmat,1);
            [v,idx]=sort(rmat(:),'descend'); 
            v((EL+1):length(UDidx))=0;
            rmat(idx)=v;
            rmat=max(rmat,rmat');
            rth(j)=v(EL);
            kdenth(j)=EL/NPE;
        case 'mst'
            notintree = rmat.*~MST;
            v = sort(nonzeros(notintree),'descend');
            cutoff = ceil(th(j)*NPE)*2-sum(MST(:)>0);
            if cutoff>0
                rth(j) = v(cutoff);
                rmat = MST + notintree.*(notintree>=rth(j));
            else
                rth(j) = min(v);
            end
    end
    
    % Distance exclusion
    if isfield(params,'dmat')
        dmat=params.dmat>params.xdist;
        rmat=rmat.*repmat(dmat,[1,1,Nsubj]);
        clear dmat
    else params.xdist
        dmat=pdist2(params.roi,params.roi)>params.xdist;
        rmat=rmat.*repmat(dmat,[1,1,Nsubj]);
        clear dmat
    end

    % binarize matrix
    if params.binary, rmat=single(rmat>0); end

    % Write pajek file, do infomap, load and kill files
    pajekfname=['paj_col',num2str(j),'.net'];
    mods(:,j)=infomap_wrapper_HSB(rmat,writepath,pajekfname,params.repeats);
end

cd(here0)
rmdir(GCtempFname,'s')
cd(here);

stats.clusters=mods;            clear mods;
stats.params=params;            clear params;
stats.rth=rth;                  clear rth;        
stats.kdenth=kdenth;            clear kdenth;  
stats.MuMat=rmat0;              clear rmat0;