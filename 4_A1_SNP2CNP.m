          % %                                       % %
         % % %                                     % % % 
        % % % %    SNP2CNP created by MonaIsa     % % % %
         % % %        slight changes by Ari        % % %
          % %                                       % % 
         
%input: SNP/BCFSummary and corresponding CallSummary     
                                           
clearvars

                     %                      %
                    % %    Define input    % %
                     %                      %

donor = "Bval" % "W23", "Bval", "Batro"

if strcmp(donor, "Bval")
    % Bval donor
    masterlist = "/home/isabel/shared_Master/Matlab/mlBval2Bs166NCe_v1.txt"; 
    accgenome = "/home/isabel/shared_Master/Matlab/accBval2Bs166NCe.txt";
elseif strcmp(donor, "W23")
    % W23 donor
    masterlist = "H:\masterlistMapping\mlW232B166NCe_IR\mlW232Bs166NCe_v1.txt";
    accgenome = "H:\0_PhD\Bioinformatics\Dictionaries\accgens\accW232Bs166NCe.txt";
elseif strcmp(donor, "Batro")
    % BA donor
    masterlist = "H:\masterlistMapping\mlBatro2Bs166NCe\mlBatro2Bs166NCe_v1.txt";
    accgenome = "H:\0_PhD\Bioinformatics\Dictionaries\accgens\accBatro2Bs166NCe.txt";
else
    error("Something went wrong with your donor declaration.. Is your donor really %s?", donor);
end


mmlist = '/home/isabel/shared_Master/Matlab/Bs166NCe_mm.txt';
artefacts = '/home/isabel/shared_Master/Matlab/Artefacts_Bs1662BsNCe.vcf';
recipsize = 4215607;

%

SNPSource = "SNPSummary";     % Where do your variant lists come from? 
                              % "SNPSummary" (new) / "IndvMutLists" (old)
                              % Default: "SNPSummary" 
     
% You just need to specify samplenames if you use "IndvMutLists", otherwise
% you can leave it empty to choose ALL:
%samplenames = ["NoWns0110", "NoWns0120", "NoWns0210", "NoWns0220", "NoWns0610", "NoWns0620", "NoWns0310", "NoWns0410", "NoWns0710", "NoWns0810"];
samplenames = [];

% Path of the SNPSummary/ies or IndvMutLists of the evolved strains:
% SNPPath = "H:\Vns_onBs166NCe\";    
% SNPPath = "H:\Wns_onW23wt\";
SNPPath = "/home/isabel/shared_Master/Matlab/";

saveCNPSummary = "on"; % Turn "on" to save the CNPSummary !

if strcmp(SNPSource, "SNPSummary") 
    % You can give more than {1} SNPSummary and CallSummary as input
    SNPName{1} = "20220315_Mix13_BCFSummary.mat";
    CallName{1}="20220315_Mix13_CallSummary_ml.mat";
    %SNPName{2} = "20220217_SNPSummary.mat";


elseif strcmp(SNPSource, "IndvMutLists")
    % Default setting: The IndvMutLists are saved as the samplenames 
    % plus "_IndvMutList.txt"
    SNPName = samplenames + "_IndvMutList.txt";
    
else
    error("Please check your SNPSource! It needs to be 'SNPSummary' or 'IndvMutLists'.");
end

%
    
% Where do you want to save the output -- CNPSummary ?
savepath = SNPPath;

% Define cluster finding parameters
cms = 5;    % cms - 1: number of allowed missing snps %!


  %                                                                  %
 % %                                                                % %
% % %   Now, just lean back and let me do the rest for you ...     % % %
 % %                                                                % %
  %                                                                  %
  
% Load variant lists into allSNPs
allSNPs = [];
allCall=[];
if strcmp(SNPSource, "SNPSummary")
    
    for i = 1 : length(SNPName)  
        Data = load(SNPPath + SNPName{i});
        Datafp=load(SNPPath+CallName{i});
        allSNPs = [allSNPs Data.SNPSummary];
        allCall=[allCall Datafp];
    end
    if isempty(samplenames)
        samplenames = [allSNPs.Sample];
    end
    
elseif strcmp(SNPSource, "IndvMutLists")
    
    for i = 1 : length(SNPName)
        fid = fopen(SNPPath + SNPName(i));
            imp = textscan(fid, '%f %s %s');
            allSNPs(i).Sample = samplenames(i);
            allSNPs(i).IndvMutList = [imp{1}, string(imp{2}), string(imp{3})];
            clear imp;
        fclose(fid);
    end
    disp("You are using IndvMutList.txt - files to analyse your data.");
    disp("These are obsolete (old filtering)!! Check out the new SNPSummaries!:)");
    
end
  
% Preallocating your variables
denovo = cell(numel(samplenames),1);      % SNPs that do not fit the masterlist
C = cell(numel(samplenames),1);           % detected clusters
SPI = cell(numel(samplenames),1);         % SNPs that fit the masterlist but not in cluster (You need at least two mlSNPs to have a cluster)
Cdist = cell(length(C),1);              % minimum length of the detected cluster (from first snp to the last)
Mdist = cell(length(C),1);              % maximum length (including the distance to the next mlsnp or to the start of the next accessory part)
Adist = cell(length(C),1);              % average length ((maxlen-minlen)/2+minlen)
ident = cell(length(C),1);
transfer = zeros(1,length(C));
ORI_CROSSING = zeros(length(C),1);

% Load recipient/donor specific master list and write position in ml.pos and
% the alternate base in ml.atcg (ml is a struct)
fid = fopen(masterlist);
imp = textscan(fid,'%f %s %s');
fclose(fid);
ml.pos = imp{1};
ml.atcg = imp{3};
clear imp

% Load recipient/donor specific accessory genome (for Bsub168 with respect
% to W23 from Zeigler et al.) in acc where the start positions of the 
% accessory genome is written into acc.start and the end position into
% acc.edge (acc is a struct)
fid = fopen(accgenome);
% for Zeigler use the following three lines
% imp = textscan(fid,'%s %f %f %f %s', 'delimiter', '\t');
% acc.start = imp{2};
% acc.edge = imp{3};
% otherwise, use:
imp = textscan(fid, '%f %f %f', 'delimiter', '\t');
acc.start = imp{1};
acc.edge = imp{2};
fclose(fid);
clear imp

% Load the multi mapper list 
if ~isempty(mmlist)
fid = fopen(mmlist);
imp = textscan(fid, '%f %f %f');
mm.start = imp{1};
mm.edge = imp{2};
clear imp;
end

% Merge with acc.list for later use:
acc.start = vertcat(acc.start, mm.start);
acc.edge = vertcat(acc.edge, mm.edge);

% Create acc_mask
acc_mask = [];
for i = 1 : length(acc.start)
    acc_mask = [acc_mask acc.start(i):acc.edge(i)];
end 
acc_mask = unique(sort(acc_mask));

% Read in artefacts.vcf (Ancestor reads on dictionary)
if ~isempty(artefacts)
fid = fopen(artefacts);
imp = textscan(fid, '%s %f %s %s %s %f %s %s %s %s', 'HeaderLines', 33);
artefact.pos = imp{2};
artefact.alt = imp{5};
fclose(fid);
clear imp;
end 


%
% This loop goes through all samples in samplenames and ends at the end of the script
%

for m = 1:numel(samplenames)
    
% import SNP list of the current sample
clear snp
findSample = strcmp(samplenames(m), [allSNPs.Sample]);
findCall = strcmp(samplenames(m), [allCall.CallSummary.SampleName]);

if length(nonzeros(findSample)) == 0
    error("Your SNPSummary does not contain sample '%s'!", samplenames(m));
elseif length(nonzeros(findSample)) > 1
    fprintf("Be aware that your sample '%s' can be found more than once in the loaded SNPSummary/ies!\n",  samplenames(m));
    fprintf("Only the first entry will be considered in the following analysis!\n");
    idx = find(findSample == 1);
    findSample = min(idx);
end

if length(nonzeros(findCall)) == 0
    fprintf("There is no CallSummary fitting your sample!");
elseif length(nonzeros(findCall)) > 1
    fprintf("Be aware that your sample '%s' can be found more than once in the loaded CallSummary/ies!\n",  samplenames(m));
    fprintf("Only the first entry will be considered in the following analysis!\n");
    idx = find(findCall == 1);
    findCall=min(idx);
end

snp.atcg = [allSNPs(findSample).FilterSummary.filtered(:).alt]';
snp.pos = [allSNPs(findSample).FilterSummary.filtered(:).pos]';
snp.vf=[allSNPs(findSample).FilterSummary.filtered(:).varfreq]';

FalsePositives=allCall(findCall).CallSummary.FalsePositives;
fp.pos=[FalsePositives(:).pos];
fp.vf=[FalsePositives(:).varfreq];

% remove the artefacts 
for i = 1 : length(artefact.pos)
    idx = find(snp.pos == artefact.pos(i));
    if ~isempty(idx) && strcmp(artefact.alt(i), snp.atcg(idx))
        snp.pos(idx) = [];
        snp.atcg(idx) = [];
        snp.vf(idx) = [];
    end   
end 
clear idx 

if isempty(snp.pos)
    continue
end

% 
%
% the next four lines equal new match function (MATCH_MF)
%

[match_pos, match_posidx] = ismember(ml.pos, snp.pos);        % With positions are on both lists ? match_pos is a mask (logicals) for the masterlist, match_posidx gives the index on the snplist of the replicate
match_nt = strcmp(ml.atcg(match_pos), snp.atcg(nonzeros(match_posidx)));    % Are the detected alternate alleles the same as the expected ? match_nt gives a mask for the 

paren = @(x, varargin) x(varargin{:});      % definition of an anonymous function
match = paren(ml.pos(match_pos), match_nt); % Match contains the positions on the reference genome where mlSNP was detected

match_mask = ismember(ml.pos, match);       % creates a masterlist mask with detected mlSNPs

numberofmlsnps(m)=length(nonzeros(match_mask));
%
% Create list of denovo mutations 
%

denovo{m,1} = snp.pos(~ismember(snp.pos, match))';
denovo{m}(2,:) = 0;

%
% 
%
    
if isempty(match)
    continue
end
   
%
% Finding Cluster
%  

% Finding the start of the clusters
% For this, the ml mask ($match_mask) is shifted $cms-times to the right and
% added to the non shifted mask, $sta. For every start of a cluster (a detected
% masterlist snp after $cms not detected snps), $stat contains a 0 followed
% by a 1. By now dividing sta non shifted through sta shifted one to the left, sta2,
% every starting position is INF. All other positions are an INT or NaN

clear sta sta2 start
sta = match_mask(1:end)'; 
for i = 1:cms-1
    sta = [match_mask(end-i+1:end)' match_mask(1:end-i)'] + sta; 
end
sta2 = sta(1:end)./[sta(end:end) sta(1:end-1)];
start = ml.pos(isinf(sta2));

% Finding the ends of the clusters (here: edge, because end is not a valid
% variable name); The end of the cluster is found the same way as start, just 
% shifting the mask to the left and adding (ed) and then dividing ed through 
% the one to the right shifted ed, ed2. edge gives the end positions of clusters

clear ed ed2 edge
ed = match_mask(1:end)';
for i = 1:cms-1
    ed = [match_mask(1+i:end)' match_mask(1:i)'] + ed; 
end 
ed2 = ed(1:end) ./ [ed(2:end) ed(1:1)];
edge = ml.pos(isinf(ed2)); %gives only the ml positions where ed2 equal inf

% Tidy up
clear sta sta2 ed ed2

%
% Test, if a cluster is going over the ORI , if yes , split first
%

if edge(1) < start(1)
    start = vertcat(0, start);
    edge = vertcat(edge, recipsize);
    ORI_CROSSING(m) = 1;
    disp(['Your replicate ', samplenames{m}, ' has an ORI crossing cluster, dude!']);
end

% All Cluster with length 1 are shifted to SPI, longer clusters remain
% clusters
SPI_mask = ismember(start, edge);
SPI{m,1} = start(SPI_mask);
start = start(~SPI_mask);
edge = edge(~SPI_mask);
clear SPI_mask

if isempty(start) && isempty(edge)
    continue
end

% Create a clustermask with all positions within a cluster now, you will
% need it for the exclusion of the accessory parts and to find if denovos
% are within clusters or outside


clustermask = [];
for i = 1 : length(start)
    clustermask = [clustermask start(i):edge(i)];
end 

%% meins !!!!!!!!!!!!!!!!!!!!!!!!!!
infoidx=ismember(snp.pos, clustermask); %remember the information about all SNPs in the found clusters
fpinfoidx=ismember(fp.pos, clustermask); % find all false positives within the found cluster boundaries
CNPInfo=[snp.pos(infoidx), snp.atcg(infoidx), snp.vf(infoidx)];
fpClu.pos=[fp.pos(fpinfoidx)];
fpClu.vf=[fp.vf(fpinfoidx)];


%% hier !!!!!!!!!!!!!!!!!!!!!!!!!!!!!

% Compare with accessory genome (and multi mapper regions) and cut out
% overlapping positions
acc_filter = ~ismember(clustermask, acc_mask);
clustermask_filt = clustermask(acc_filter);
clear clustermask acc_filt

% Are denovos in a cluster or outside ?
denovo{m}(2,:) = ismember(denovo{m}(1,:), clustermask_filt);

% Now go back from the list of all positions in a cluster to start/end
% position of the detected (acc.gen. and mm-regions - cleaned) cluster
k = 1;
start_filt(k) = clustermask_filt(1);

for i = 1 : length(clustermask_filt) - 1
   if clustermask_filt(i+1) ~= clustermask_filt(i)+1
       edge_filt(k) = clustermask_filt(i);
       start_filt(k+1) = clustermask_filt(i+1);
       k = k + 1;
   end 
end
edge_filt(k) = clustermask_filt(end);

start = start_filt;
edge = edge_filt;
clear start_filt edge_filt

% Starting to fill the cell C with information about the detected clusters 
C{m}(1,:) = start';
C{m}(2,:) = edge';

% Counting mlSNPs: This method works with length of ml.pos for
% entry greater than start/end (loop ~ 100)
%

for i = 1 : length(start)
    % Counting number of mlsnps in a cluster
    snpno(i) = length(ml.pos(ml.pos >= start(i))) - length(ml.pos(ml.pos >= edge(i))) + 1;
    C{m}(3,i) = snpno(i);
    % Counting the detected number of snps in cluster (matching snps in a cluster) --> missing snps in a
    % cluster
    snpno_det(i) = length(match(match >= start(i))) - length(match(match >= edge(i))) + 1;
    C{m}(4,i) = C{m}(3,i) - snpno_det(i); % number of missing snps
    clear snpno snpno_det
    
    % Calculating distances (minimum(c), maximum(m), average(a))
    cdist = edge(i) - start(i) + 1;
    Cdist{m}(i,1) = cdist;

    % Measuring cluster lengths: To calculate the maximum distance, the next mlSNP that is not in the
    % cluster needs to be found or the next accessory part(which one of both is closer)
    mdist_back = min(ml.pos(ml.pos > edge(i)));     % find the next mlsnp behind the cluster
    if isempty(mdist_back); mdist_back = recipsize; end % if there is no, the maximum is the end of the genome
    
    mdist_front = max(ml.pos(ml.pos < start(i)));   % find the next mlsnp in front of the cluster
    if isempty(mdist_front); mdist_front = 0; end   % if there is no, the limit is the start of the genome
    
    idx_back = find(edge(i) < acc.start(:,1) & mdist_back > acc.start(:,1)); % see if there is an acc part between the two snps in the back
        if ~isempty(idx_back) 
            mdist_back = acc.start(min(idx_back));  % if there is an acc part, set the range of mdist to the start of the accessory part
        end    
    idx_front = find(start(i) > acc.edge(:,1) & mdist_front < acc.edge(:,1)); % see if there is an acc part between the two snps in the front
        if ~isempty(idx_front) 
            mdist_front = acc.edge(max(idx_front)); % if there is an acc part, set the range of mdist to the end of the accessory part
        end  
    mdist = (mdist_back - 1) - (mdist_front + 1) + 1;
    Mdist{m}(i,1) = mdist;
    Mdist{m}(i,2) = mdist_front + 1;
    Mdist{m}(i,3) = mdist_back - 1;
        
    % Average distance: adist = cdist + (mdist - cdist)/2;
    Adist{m}(i,2) = ceil(mdist_front + (start(i) - mdist_front)/2);
    Adist{m}(i,3) = ceil(mdist_back - (mdist_back - edge(i))/2);
    Adist{m}(i,1) = Adist{m}(i,3) - Adist{m}(i,2) + 1;

    clear mdist cdist mdist_back mdist_front
end 
   
% Now merge, the ORI crossing cluster 
if ORI_CROSSING(m)~=0
    C{m}(1,1) = C{m}(1,end); % 
    C{m}(3,1) = C{m}(3,1) + C{m}(3,end);
    C{m}(4,1) = C{m}(4,1) + C{m}(4,end);
    C{m}(:,end) = [];
    
    Adist{m}(1,1) = Adist{m}(1,1) + Adist{m}(end,1);
    Adist{m}(1,2) = Adist{m}(end,2);
    Adist{m}(end, :) = [];
    
    Mdist{m}(1,1) = Mdist{m}(1,1) + Mdist{m}(end,1);
    Mdist{m}(1,2) = Mdist{m}(end,2);
    Mdist{m}(end, :) = [];
    
    Cdist{m}(1,1) = Cdist{m}(1,1) + Cdist{m}(end,1);
    Cdist{m}(end, :) = [];
end 
    
% Calculate the identity:
% Identity = 1 - (# mlSNPs) / Adist
ident{m} = 1 - C{m}(3,:)' ./ Adist{m}(:,1);
 
% Calculate the percentage of genome replaced 
% for Cdist (minimum distance)
transfer_min = sum(Cdist{m}(:,1)) / recipsize * 100 ;
% for Adist (average distance)
transfer(m) = sum(Adist{m}(:,1)) / recipsize * 100 ;

% Tidy up
clear i idx_back idx_front fid match_posidx match_pos match_nt
end

if ~isempty(nonzeros(transfer))
    disp(['On average, (', num2str(mean(transfer(transfer>0)), '%.2f'),' ',char(177),' ',num2str(std(transfer(transfer>0)), '%.2f'),') % of the genome is replaced (replicates with no clusters excluded).']);
end

%save 
samplenamesC = cellfun(@(x) {string(x)},cellstr(samplenames));
CNPInfostr=struct('pos', str2double(CNPInfo(:, 1)), 'alt', CNPInfo(:, 2), 'varfreq', str2double(CNPInfo(:, 3)));
CNPSummary = struct('C',C,'Cdist',Cdist,'Adist',Adist,'Mdist',Mdist,'denovo',denovo,'SPI',SPI, 'Ident', ident,'ORI_Crossing',num2cell(ORI_CROSSING),'Transfer', num2cell(transfer'),'Sample', samplenamesC', 'Info', CNPInfostr, 'FPInfo', fpClu);

if saveCNPSummary == "on"
    save(savepath + datestr(now, 'yyyymmdd') + "_Mix13_CNPSummary.mat", 'CNPSummary')
end

% Tidy up; comment out if you like to have a closer look at variables
clear acc_mask clustermask i 
