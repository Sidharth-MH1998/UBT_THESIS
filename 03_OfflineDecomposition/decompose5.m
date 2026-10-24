function [signal,parameters] = decompose5(emg, fs, badchan, padLen, initialization, NITER, ...
    nbextchan, silthr, covfilter, covthr, differentialmode, ...
    peeloff_flag, peeloffwin, duplicatesthresh, CoVDR, contrastfunc, refineMU, preproc_flag, recordedForce)

% DECOMPOSE4 Decompose multichannel EMG into motor-unit pulse trains.
%
% The function preprocesses ,extends , whitens the extended signal, estimates
% independent sources with FastICA, It also removes duplicate units, optionally
% refines their discharge times, and calculates firing-rate.
%
% INPUTS
%   emg               - EMG matrix arranged as channels x samples.
%   fs                - Sampling frequency
%   badchan           - List of bad channels.
%   padLen            - Number of zero samples added to each signal edge. 0 to disable padding.
%   initialization    - 0 = sample with maximum summed EMG activity and 1 = random separation vector.
%   NITER             - Number of FastICA iterations.
%   nbextchan         - number of extened channels.
%   silthr            - 0.9 Minimum silhouette (SIL) value for retaining a MU.
%   covfilter         - Apply the interspike-interval CoV filter  0 = no; 1 = yes.
%   covthr            - 0.5 Maximum accepted CoV of the interspike intervals.
%   differentialmode  - filter out the smallest MU, can improve decomposition at the highest intensities 0 = no; 1 = yes.
%   peeloff_flag      - Remove reliable sources from the residual signal:
%   peeloffwin        - 0.025 Half-window duration in seconds used for peel-off.
%   duplicatesthresh  - 0.3 Minimum proportion of common discharges used to identify duplicate motor units.
%   CoVDR             - 0.3 Discharge-rate CoV target used during MU refinement.
%   contrastfunc      - FastICA contrast function, for example 'skew', 'kurtosis', or 'logcosh'.
%   refineMU          - Refine discharge times over the complete signal
%   preproc_flag      - Apply adaptive notch and band-pass filtering:
%   recordedForce     - Optional force data stored with the output signal.
%                       
%
% OUTPUTS
%   signal            - MUedit-compatible structure containing the original
%                       signal and all decomposition results:
%       peaks         - MU pulse trains with their original amplitudes
%                       (motor units x samples).
%       MUPulses      - Discharge sample indices, one cell per motor unit.
%       spike_train   - Sparse binary spike matrix (samples x motor units).
%       sil_all       - SIL quality value for each retained motor unit.
%       cov_all       - Interspike-interval CoV for each retained unit.
%       fr            - Instantaneous firing rates for each motor unit.
%       mean_fr       - Mean firing rate for each motor unit.
%       D, E          - Eigenvalue and eigenvector matrices from PCA.
%       whitened_mat  - Whitening matrix.
%       MUFilters     - Original filters retained after SIL/CoV control.
%   parameters        - Parameters used for this decomposition.

%% Step 0: Initialize outputs

% Pass the loaded signal structure as the first input to process each grid.
% A numeric EMG matrix still follows the original single-grid steps below.
if isstruct(emg)
    recording = emg;
    if isfield(recording,'ngrids')
        nGrids = recording.ngrids;
    else
        nGrids = recording.ngrid;
    end
    validateattributes(nGrids,{'numeric'},{'scalar','integer','positive'});
    channelsPerGrid = size(recording.data,1)/nGrids;
    if channelsPerGrid ~= fix(channelsPerGrid)
        error('The EMG channel count must divide evenly into the grid count.');
    end
    if ~isempty(badchan)
        validateattributes(badchan,{'numeric'},{'vector','integer','positive','<=',size(recording.data,1)},mfilename,'badchan');
    end
    fs = recording.fsamp;
    % Display recording details before starting any grid decomposition.
    fprintf('\nEMG recording loaded\n');
    fprintf('Total EMG channels: %d\n',size(recording.data,1));
    fprintf('Number of grids: %d\n',nGrids);
    fprintf('Channels per grid: %d\n',channelsPerGrid);
    fprintf('Sampling frequency: %.1f Hz\n',fs);
    fprintf('Recording duration: %.2f s (%d samples)\n', ...
        size(recording.data,2)/fs,size(recording.data,2));
    if isempty(badchan)
        fprintf('Bad-channel indices (original recording): None\n');
    else
        fprintf('Bad-channel indices (original recording): %s\n',mat2str(badchan(:)'));
    end
    fprintf('Total excluded channels: %d\n\n',numel(unique(badchan)));
    recordedForce = [];
    if isfield(recording,'recordedForce')
        recordedForce = recording.recordedForce;
    end

    % Keep the original recording metadata and store independent grid results.
    signal = recording;
    signal.ngrid = nGrids;
    signal.ngrids = nGrids;
    signal.emgtype = ones(1,nGrids);
    signal.Pulsetrain = cell(1,nGrids);
    signal.EMGmask = cell(1,nGrids);
    signal.Dischargetimes = cell(nGrids,0);
    signal.gridResults = cell(1,nGrids);
    signal.MUFilters = cell(1,nGrids);
    signal.nChan = size(recording.data,1);
    % MUedit's reference selector reads sample-aligned auxiliary rows.
    % Keep the original force samples separately in recordedForce.
    signal.auxiliary = [recording.path(:)'; recording.target(:)'];
    signal.auxiliaryname = {'Recorded force (selected channel)','Target'};
    if ~isempty(recordedForce)
        if size(recordedForce,1) == 1
            forceAtEMGRate = repmat(recordedForce',1,size(recording.data,2));
        else
            forceAtEMGRate = interp1(linspace(0,1,size(recordedForce,1)), ...
                recordedForce,linspace(0,1,size(recording.data,2)),'linear')';
        end
        for forceChannel = 1:size(forceAtEMGRate,1)
            signal.auxiliary(end+1,:) = forceAtEMGRate(forceChannel,:);
            signal.auxiliaryname{end+1} = sprintf('Force channel %d',forceChannel);
        end
    end
    parameters = struct;
    parameters.grid = cell(1,nGrids);
    parameters.gridChannels = cell(1,nGrids);

    % Save the same per-grid summary that is printed after decomposition.
    signal.gridSummary = repmat(struct('grid',0,'firstChannel',0, ...
        'lastChannel',0,'goodChannels',0,'badChannels',0, ...
        'motorUnits',0,'processingSeconds',0),1,nGrids);

    for grid = 1:nGrids
        % Recording channels are consecutive blocks: 1:64, 65:128, ...
        channels = (grid-1)*channelsPerGrid + (1:channelsPerGrid);
        gridBadchan = find(ismember(channels,badchan));
        if numel(gridBadchan) == channelsPerGrid
            error('Grid %d has no good channels.',grid);
        end
        fprintf('\nDecomposing grid %d of %d (channels %d to %d).\n', ...
            grid,nGrids,channels(1),channels(end));
        gridTimer = tic;
        [gridSignal,gridParameters] = decompose5(recording.data(channels,:), ...
            fs,gridBadchan,padLen,initialization,NITER,nbextchan,silthr, ...
            covfilter,covthr,differentialmode,peeloff_flag,peeloffwin, ...
            duplicatesthresh,CoVDR,contrastfunc,refineMU,preproc_flag,recordedForce);
        gridSeconds = toc(gridTimer);
        signal.gridResults{grid} = gridSignal;
        signal.MUFilters{grid} = gridSignal.MUFilters;
        signal.EMGmask{grid} = double(ismember((1:channelsPerGrid)',gridBadchan));
        parameters.grid{grid} = gridParameters;
        if grid == 1
            % Keep MUedit's standard parameters at the top level as well.
            names = fieldnames(gridParameters);
            for field = 1:numel(names)
                parameters.(names{field}) = gridParameters.(names{field});
            end
        end
        parameters.gridChannels{grid} = channels;
        if isfield(gridSignal,'Pulsetrain')
            signal.Pulsetrain{grid} = gridSignal.Pulsetrain{1};
            nGridMUs = numel(gridSignal.Dischargetimes);
            signal.Dischargetimes(grid,1:nGridMUs) = gridSignal.Dischargetimes;
        else
            % An empty grid must not stop decomposition of the other grids.
            signal.Pulsetrain{grid} = zeros(0,size(recording.data,2));
        end
        signal.gridSummary(grid) = struct('grid',grid, ...
            'firstChannel',channels(1),'lastChannel',channels(end), ...
            'goodChannels',channelsPerGrid-numel(gridBadchan), ...
            'badChannels',numel(gridBadchan), ...
            'motorUnits',size(signal.Pulsetrain{grid},1), ...
            'processingSeconds',gridSeconds);
        fprintf('Grid %d finished: %d good channels, %d bad channels, %d MUs, %.1f seconds.\n', ...
            grid,signal.gridSummary(grid).goodChannels,numel(gridBadchan), ...
            signal.gridSummary(grid).motorUnits,gridSeconds);
    end

    fprintf('\nPer-grid decomposition summary\n');
    fprintf('Grid   Channels     Good   Bad   MUs   Seconds\n');
    for grid = 1:nGrids
        summary = signal.gridSummary(grid);
        fprintf('%4d   %3d-%-3d      %3d   %3d   %3d   %7.1f\n', ...
            summary.grid,summary.firstChannel,summary.lastChannel, ...
            summary.goodChannels,summary.badChannels, ...
            summary.motorUnits,summary.processingSeconds);
    end
    fprintf('Total: %d MUs; %.1f seconds spent decomposing grids.\n', ...
        sum([signal.gridSummary.motorUnits]),sum([signal.gridSummary.processingSeconds]));
    parameters.badchan = badchan; % original recording channel numbers
    parameters.ngrids = nGrids;
    parameters.nwindows = 1;
    parameters.thresholdtarget = 0.8;
    parameters.edges = 0;
    return
end

% Initialize every field before processing 

signal = struct;
parameters = struct;

if nargin < 19
    recordedForce = [];
end

signal.peaks = [];
signal.MUPulses = {};
signal.spike_train = [];
signal.sil_all = [];
signal.cov_all = [];
signal.fr = {};
signal.mean_fr = [];
signal.D = [];
signal.E = [];
signal.whitened_mat = [];
signal.MUFilters = [];
signal.recordedForce = recordedForce;

% Record settings before any early return, including grids with no units.
parameters = struct('initialization',initialization,'NITER',NITER, ...
    'nbextchan',nbextchan,'silthr',silthr,'covfilter',covfilter, ...
    'covthr',covthr,'differentialmode',differentialmode, ...
    'peeloff',peeloff_flag,'peeloffwin',peeloffwin, ...
    'duplicatesthresh',duplicatesthresh,'CoVDR',CoVDR, ...
    'contrastfunc',contrastfunc,'refineMU',refineMU,'preproc',preproc_flag, ...
    'padLen',padLen,'badchan',badchan,'checkEMG',0, ...
    'nwindows',1,'thresholdtarget',0.8,'edges',0);


%% Step 1: Preprocessing

% Preserve the truly raw recording for MUedit and online filter rebuilding.
originalEMG = emg;
nChannelsOriginal = size(originalEMG,1);
nSamplesOriginal = size(originalEMG,2);

if preproc_flag
    emg = adaptiveNotchFilter(emg,fs);
    emg = bandpassingals(emg,fs,1);
end

nChannels = size(emg,1);

fprintf('Signal has %d channels.\n',nChannels);

if ~isempty(badchan)
    fprintf('There are %d bad channels.\n',numel(badchan));

    % Bad channels are excluded only from the numerical decomposition.
    goodchan = setdiff(1:nChannels,badchan);
    emg = emg(goodchan,:);
else
    goodchan = 1:nChannels;
end

if padLen > 0
    % Padding reduces edge artefacts during filtering and source recovery.
    emg = [zeros(size(emg,1),padLen),emg,zeros(size(emg,1),padLen)];

    fprintf('Padding enabled; signal now has %d samples.\n',size(emg,2));
end

if differentialmode
    % Temporal differentiation can suppress smaller/common components, improve separation during high-force contractions.
    emg = diff(emg,1,2);
end

%% Step 2: Signal extension

% Extend the signal with delayed channel copies.
exFactor = round(nbextchan/size(emg,1));
exFactor = max(exFactor,1);

eSIG = extend(emg,exFactor);
eSIG = demean(eSIG);

%% Step 3: Whitening

% Remove the mean and decorrelate the extended observations. Whitening also normalizes their variance before the FastICA iterations.
[E,D] = pcaesig(eSIG);
[wSIG,w_mat,~] = whiteesig(eSIG,E,D);

%% Step 4: FastICA source extraction

% Initialize matrix B (n x m) n: separation vectors, m: iterations 
% Initialize matrix MUFilters to only save the reliable filters
% Intialize SIL and PNR
B = zeros(size(wSIG,1),NITER); % all separation vectors
MUFilters = zeros(size(wSIG,1),NITER);  % only reliable vectors, later unreliable removed

w = zeros(size(wSIG,1),1);
SIL = zeros(1,NITER);
CoV = zeros(1,NITER);
idx1 = zeros(1,NITER);

X = wSIG;
actind = [];

for j = 1:NITER

    % Initialize from either a high-activity sample or a random vector
    if initialization == 0

        if j == 1
            actind = sum(X,1).^2;
        elseif ~isempty(actind)
            actind(idx1(j-1)) = 0;
        end

        [~,idx1(j)] = max(actind);
        w = X(:,idx1(j));

    else
        w = randn(size(X,1),1);
    end

    w = w - B*B'*w; % orthogonalisation to Remove projections onto previously estimated component.
    w = w/norm(w); % normalisation to scale the candidate vector to unit length.
   
    maxiter = 500; % max number of iteration for fixed point algorithm
    w = fixedpointalg(w,X,B,maxiter,contrastfunc); 
    % Maximize source sparsity/non-Gaussianity using the requested contrast

    [~,spikes] = getspikes(w,X,fs); % output is the sample of spikes detected 

    if numel(spikes) > 10

        ISI = diff(spikes/fs);
        CoV(j) = std(ISI)/mean(ISI);
        Wini = sum(X(:,spikes),2);% update W by summing the spikes

        % minimize the CoV of the resulting interspike intervals. (end whenCoV minimised)
        [MUFilters(:,j),spikes,CoV(j)] = minimizeCOVISI(Wini,X,CoV(j),fs);
        B(:,j) = w;

        % calc SIL values (larger values indicate a more reliable motor-unit pulse train.)
        [~,spikes,SIL(j)] = calcSIL(X,MUFilters(:,j),fs);

        % Optionally subtract reliable MU activity from the residual signal
        if peeloff_flag == 1 && SIL(j) > silthr
            X = peeloff(X,spikes,fs,peeloffwin);
        end

        if SIL(j) >= silthr && (covfilter ~= 1 || CoV(j) <= covthr)
            fprintf('Iteration %d - SIL = %.4f, CoV = %.4f - Potential MU found\n', ...
                j,SIL(j),CoV(j));
        else
            fprintf('Iteration %d - SIL = %.4f, CoV = %.4f\n',j,SIL(j),CoV(j));
        end

    else
        B(:,j) = w;

        fprintf( ...
            'Iteration %d - fewer than 10 spikes detected.\n', ...
            j);
    end
end

%% Step 5: Keep reliable filters
% An iteration with too few spikes leaves a zero filter, which cannot be used.
keepFilter = SIL >= silthr & any(MUFilters ~= 0,1);
% Apply the SIL criterion to the filter and its associated quality arrays
MUFilters = MUFilters(:,keepFilter);
sil_all = SIL(keepFilter);
CoV = CoV(keepFilter);

if covfilter == 1
    % Optionally reject irregular discharge trains with excessive ISI CoV. keep the ones under CoV thresh
    keepCoV = CoV <= covthr;
    MUFilters = MUFilters(:,keepCoV);
    sil_all = sil_all(keepCoV);
    CoV = CoV(keepCoV);
end

%% Step 6: Convert filters into motor-unit pulse trains
[PulseT,distime] = batchprocessfilters_1win(MUFilters,wSIG,exFactor,differentialmode,size(emg,2),fs);
% pulse train and time of discharge using the filter\

if isempty(PulseT) || size(PulseT,1) == 0
    warning('No motor units were detected.');
    return
end

if size(PulseT,2) ~= size(emg,2)
    error('Pulse-train length does not match the processed EMG length.');
end

%% Step 7: Remove duplicate motor units

% Units with sufficiently many coincident discharges are treated as the same source.
[PulseT,distimenew] = remduplicates(PulseT,distime,distime,round(fs/40),0.00025,duplicatesthresh,fs);

% Match retained units to their original quality values.
retainedOriginalIndices = zeros(1,numel(distimenew));

for newMU = 1:numel(distimenew)
    for originalMU = 1:numel(distime)
        if isequal(distimenew{newMU},distime{originalMU})
            retainedOriginalIndices(newMU) = originalMU;
            break
        end
    end
end

validMatch = retainedOriginalIndices > 0;

if all(validMatch)
    MUFilters = MUFilters(:,retainedOriginalIndices);
    sil_all = sil_all(retainedOriginalIndices);
    CoV = CoV(retainedOriginalIndices);
else
    error('Could not match duplicate-filtered motor units to their filters.');
end

%% Step 8: Refine motor units 

if refineMU == 1
    % Remove outliers generating irrelevant discharge rates before manual edition (1st time)
    distimenew = remoutliers(PulseT,distimenew,CoVDR,fs);

    % emg already contains only good channels. refineMUs uses the standard
    % mask convention 0 = keep and 1 = remove.
    refinementMask = zeros(size(emg,1),1);

    [Pulsetrain,distimenew] = refineMUs(emg,refinementMask,PulseT,distimenew,fs); % reapply filter on entire emg
     % Remove outliers generating irrelevant discharge rates before manual edition (2nd time)
    distimenew = remoutliers(Pulsetrain,distimenew,CoVDR,fs);

else
    Pulsetrain = PulseT;
end

%% Step 9: Remove motor units with too few spikes

% At least 11 discharges are required for stable firing-rate calculations. Apply the same mask to timings, pulse trains, SIL, and CoV.
validMU = false(1,numel(distimenew));

for mu = 1:numel(distimenew)
    validMU(mu) = numel(distimenew{mu}) > 10;
end

% keep only valid MUs
distimenew = distimenew(validMU);
Pulsetrain = Pulsetrain(validMU,:);
MUFilters = MUFilters(:,validMU);

if numel(sil_all) == numel(validMU)
    sil_all = sil_all(validMU);
end

if numel(CoV) == numel(validMU)
    CoV = CoV(validMU);
end

if isempty(distimenew)
    warning('No motor units remained after quality control.');
    return
end

nMUs = numel(distimenew);

%% Step 10: Create discharge-time and binary spike structures
Dischargetimes = cell(1,nMUs);

for mu = 1:nMUs
    Dischargetimes{mu} = unique(round(distimenew{mu}(:)'),'sorted');
end

% Store the same timings as a samples x motor-units sparse binary matrix.

spike_train = zeros(size(emg,2),nMUs);

for mu = 1:nMUs
    validIndices = Dischargetimes{mu};

    validIndices = validIndices(validIndices >= 1 & validIndices <= size(spike_train,1));

    Dischargetimes{mu} = validIndices;
    spike_train(validIndices,mu) = 1;
end

spike_train = sparse(spike_train);

%% Step 11: Remove padding

if padLen > 0 % if there was padding, we remove it here
    fprintf('Removing padding.\n');

    emg = emg(:,padLen+1:end-padLen); % remove padding from original signal
    spike_train =spike_train(padLen+1:end-padLen,:); % remove padding from spike train
    Pulsetrain = Pulsetrain(:,padLen+1:end-padLen); % remove padding from pulse train (with amplitudes)
    % We generate the pulses (indices) again from the updated spike trains
    for mu = 1:nMUs
        Dischargetimes{mu} =find(spike_train(:,mu))';
    end

    fprintf('Signal returned to %d samples.\n',size(emg,2));
end

% Differentiation removes the final sample. Restore an empty final sample
% so MUedit can index all arrays against the original recording timeline.
if differentialmode && size(Pulsetrain,2) == nSamplesOriginal-1
    Pulsetrain(:,end+1) = 0;
    spike_train(end+1,:) = 0;
end

%% Step 13: Calculate firing rates
% Instantaneous firing rate is the reciprocal interspike interval in Hz.
fr = cell(1,nMUs);
mean_fr = zeros(nMUs,1);
for mu = 1:nMUs
    peakIndices = Dischargetimes{mu};
    if numel(peakIndices) > 1
        fr{mu} = [0,fs./diff(peakIndices)]; %IFR= 1/ISI
        mean_fr(mu) = mean(fr{mu}); %avg of IFR
    else
        fr{mu} = [];
        mean_fr(mu) = NaN;
    end
end

%% Step 17: Create the signal structure

signal.data = originalEMG; %channels x samples
signal.fsamp = fs;
signal.ngrid = 1;
signal.emgtype = 1; % 1 = surface EMG, 2 = intramuscular EMG
signal.Pulsetrain = {Pulsetrain}; % motor units x samples
signal.MUFilters = MUFilters; % retained filters aligned with the final MUs

% Cells indexed as {grid,motorUnit}
signal.Dischargetimes = cell(1,nMUs);

for mu = 1:nMUs
    dischargeIndices = round(Dischargetimes{mu}(:)');
    dischargeIndices = dischargeIndices(isfinite(dischargeIndices) & dischargeIndices >= 1 &dischargeIndices <= nSamplesOriginal);
    signal.Dischargetimes{1,mu} = unique(dischargeIndices,'sorted');
end

%% Create the MUedit channel mask
% Zero means include; one means exclude.
signal.EMGmask = {zeros(nChannelsOriginal,1)};
if ~isempty(badchan)
    signal.EMGmask{1}(badchan) = 1;
end

%% Create an EMG-amplitude reference
% MUedit expects target/path information. When no external force or target
% trajectory is supplied, use a normalized one-second moving EMG envelope.
referenceWindow = max(1,round(fs));

emgEnvelope = movmean(abs(originalEMG),referenceWindow,2);
signal.target = mean(emgEnvelope,1);
targetMaximum = max(abs(signal.target));

if isfinite(targetMaximum) && targetMaximum > 0
    signal.target = signal.target/targetMaximum;
else
    signal.target = ones(1,nSamplesOriginal);
end

% No separate requested trajectory is available.
signal.path = signal.target;

% Store the generated reference as one auxiliary signal.
signal.auxiliary = signal.target;
signal.auxiliaryname = {'EMG amplitude'};


%% Step 20: Record decomposition parameters for MUedit

parameters.initialization = initialization;
parameters.NITER = NITER;
parameters.nbextchan = nbextchan;
parameters.silthr = silthr;
parameters.covfilter = covfilter;
parameters.covthr = covthr;
parameters.differentialmode = differentialmode;
parameters.peeloff = peeloff_flag;
parameters.peeloffwin = peeloffwin;
parameters.duplicatesthresh = duplicatesthresh;
parameters.CoVDR = CoVDR;
parameters.contrastfunc = contrastfunc;
parameters.refineMU = refineMU;
parameters.preproc = preproc_flag;
parameters.padLen = padLen;
parameters.badchan = badchan;
% Standard MUedit fields
parameters.nwindows = 1;
parameters.thresholdtarget = 0.8;
parameters.edges = 0;

%% Step 21: Validate the MUedit structure

% Fail early if a field has inconsistent dimensions or if discharge times
% cannot be used as valid MATLAB sample indices.
if signal.ngrid ~= numel(signal.Pulsetrain)
    error('signal.ngrid does not match signal.Pulsetrain.');
end

if signal.ngrid ~= numel(signal.EMGmask)
    error('signal.ngrid does not match signal.EMGmask.');
end

if signal.ngrid ~= numel(signal.emgtype)
    error('signal.ngrid does not match signal.emgtype.');
end

if size(signal.MUFilters,2) ~= size(signal.Pulsetrain{1},1)
    error('signal.MUFilters does not match the final motor-unit count.');
end

expectedFilterRows = sum(signal.EMGmask{1} == 0)*exFactor;
if size(signal.MUFilters,1) ~= expectedFilterRows
    error('signal.MUFilters does not match the extended channel count.');
end

if size(signal.data,2) ~= ...
        size(signal.Pulsetrain{1},2)
    error( ...
        'signal.data and signal.Pulsetrain have different lengths.');
end

if numel(signal.EMGmask{1}) ~= ...
        size(signal.data,1)
    error( ...
        'signal.EMGmask does not match the EMG channel count.');
end

if numel(signal.target) ~= ...
        size(signal.data,2)
    error( ...
        'signal.target does not match the EMG sample count.');
end

if numel(signal.path) ~= ...
        size(signal.data,2)
    error( ...
        'signal.path does not match the EMG sample count.');
end

if size(signal.auxiliary,2) ~= ...
        size(signal.data,2)
    error( ...
        'signal.auxiliary does not match the EMG sample count.');
end

if numel(signal.auxiliaryname) ~= ...
        size(signal.auxiliary,1)
    error( ...
        ['signal.auxiliaryname does not match the number ' ...
         'of auxiliary signals.']);
end

for mu = 1:nMUs

    dischargeIndices = ...
        signal.Dischargetimes{1,mu};

    if any(dischargeIndices ~= ...
            round(dischargeIndices))
        error( ...
            'MU %d contains noninteger discharge indices.', ...
            mu);
    end

    if any(dischargeIndices < 1 | ...
            dischargeIndices > nSamplesOriginal)
        error( ...
            'MU %d contains an out-of-range discharge index.', ...
            mu);
    end

    if ~issorted(dischargeIndices)
        error( ...
            'MU %d discharge indices are not sorted.', ...
            mu);
    end

    if numel(unique(dischargeIndices)) ~= ...
            numel(dischargeIndices)
        error( ...
            'MU %d contains duplicate discharge indices.', ...
            mu);
    end
end

%% Step 22: Store every decomposition result in signal

signal.sil_all = sil_all;
signal.cov_all = CoV;
signal.peaks = Pulsetrain;
signal.MUPulses = Dischargetimes;
signal.spike_train = spike_train;
signal.fr = fr;
signal.mean_fr = mean_fr;
signal.D = D;
signal.E = E;
signal.whitened_mat = w_mat;
signal.MUFilters = MUFilters;

end
