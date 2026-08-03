function decomp_results = decompose4(emg, fs, badchan, padLen, initialization, NITER, ...
    nbextchan, silthr, covfilter, covthr, differentialmode, ...
    peeloff_flag, peeloffwin, duplicatesthresh, CoVDR, ...
    contrastfunc, refineMU, preproc_flag)

% DECOMPOSE4 Decompose multichannel EMG into motor-unit pulse trains.
%
% The function preprocesses and extends the EMG, whitens the extended
% signal, estimates independent sources with FastICA, It also removes
% duplicate units, optionally refines their discharge times, calculates MUAP and
% firing-rate measures, and creates structures that can be opened in MUedit.
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
%   peeloffwin        - 0.025 Half-window duration in seconds used for peel-off and MUAP extraction.
%   duplicatesthresh  - 0.3 Minimum proportion of common discharges used to identify duplicate motor units.
%   CoVDR             - 0.3 Discharge-rate CoV target used during MU refinement.
%   contrastfunc      - FastICA contrast function, for example 'skew', 'kurtosis', or 'logcosh'.
%   refineMU          - Refine discharge times over the complete signal
%   preproc_flag      - Apply adaptive notch and band-pass filtering:
%                       
%
% OUTPUT
%   decomp_results    - Structure containing:
%       B             - All estimated separation vectors.
%       peaks         - MU pulse trains with their original amplitudes
%                       (motor units x samples).
%       MUPulses      - Discharge sample indices, one cell per motor unit.
%       spike_train   - Sparse binary spike matrix (samples x motor units).
%       sil_all       - SIL quality value for each retained motor unit.
%       cov_all       - Interspike-interval CoV for each retained unit.
%       MUAPs         - Average MUAP waveforms; each cell contains a mchannels x waveform-samples matrix.
%       fr            - Instantaneous firing rates for each motor unit.
%       mean_fr       - Mean firing rate for each motor unit.
%       p2ps          - Channel-wise peak-to-peak MUAP amplitudes.
%       MU_locs       - Channel with maximum peak-to-peak amplitude per MU.
%       D, E          - Eigenvalue and eigenvector matrices from PCA.
%       whitened_mat  - Whitening matrix.
%       MUFilters     - Separation filters retained after quality control.
%       signal        - MUedit-compatible signal structure.
%       parameters    - Parameters used for this decomposition.

%% Step 0: Initialize outputs

% Initialize every field before processing 

decomp_results = struct;
decomp_results.B = [];
decomp_results.peaks = [];
decomp_results.MUPulses = {};
decomp_results.spike_train = [];
decomp_results.sil_all = [];
decomp_results.cov_all = [];
decomp_results.MUAPs = {};
decomp_results.fr = {};
decomp_results.mean_fr = [];
decomp_results.p2ps = [];
decomp_results.MU_locs = [];
decomp_results.D = [];
decomp_results.E = [];
decomp_results.whitened_mat = [];
decomp_results.MUFilters = [];
decomp_results.signal = struct;
decomp_results.parameters = struct;


%% Step 1: Preprocessing

if preproc_flag
    emg = adaptiveNotchFilter(emg,fs);
    emg = bandpassingals(emg,fs,1);
end

% Preserve all channels and the original sample length for MUedit.
% Bad channels are retained here and excluded through signal.EMGmask.
originalEMG = emg;

nChannelsOriginal = size(originalEMG,1);
nSamplesOriginal = size(originalEMG,2);

nChannels = size(emg,1);

fprintf('Signal has %d channels.\n',nChannels);

if ~isempty(badchan)
    fprintf('There are %d bad channels.\n',numel(badchan));

    % Bad channels are excluded only from the numerical decomposition.
    % Their original positions are restored in the MUAP-related outputs.
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

        fprintf('Iteration %d - SIL = %.4f, CoV = %.4f\n',j,SIL(j),CoV(j));

    else
        B(:,j) = w;

        fprintf( ...
            'Iteration %d - fewer than 10 spikes detected.\n', ...
            j);
    end
end

%% Step 5: Keep reliable filters
keepFilter = SIL >= silthr;
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
    sil_all = sil_all(retainedOriginalIndices);
    CoV = CoV(retainedOriginalIndices);
else
    sil_all = nan(1,numel(distimenew));
    CoV = nan(1,numel(distimenew));
end

%% Step 8: Refine motor units 

if refineMU == 1
    % Remove outliers generating irrelevant discharge rates before manual edition (1st time)
    distimenew = remoutliers(PulseT,distimenew,CoVDR,fs);

    refinementMask = ones(1,size(emg,1));

    [Pulsetrain,distimenew] = refineMUs(emg,refinementMask,PulseT,distimenew,fs); % reapply filter on entire emg
     % Remove outliers generating irrelevant discharge rates before manual edition (2nd time)
    distimenew = remoutliers(Pulsetrain,distimenew,CoVDR,fs);

else
    Pulsetrain = PulseT;
end

%% Step 9: Remove motor units with too few spikes

% At least 11 discharges are required for stable MUAP and firing-rate calculations. Apply the same mask to timings, pulse trains, SIL, and CoV.
validMU = false(1,numel(distimenew));

for mu = 1:numel(distimenew)
    validMU(mu) = numel(distimenew{mu}) > 10;
end

% keep only valid MUs
distimenew = distimenew(validMU);
Pulsetrain = Pulsetrain(validMU,:);

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


%% Step 12: Compute average MUAP waveforms
% peeloffwin = 0.025; % duration of the window for detecting the action potentials from the EMG signal
windowl = round(peeloffwin*fs);  % 51 samples for 0.025 ms
MUAPs = cell(1,nMUs);

for mu = 1:nMUs
    spikes = Dischargetimes{mu};
    waveform = zeros(size(emg,1),1+2*windowl);
    for channel = 1:size(emg,1)
        temp = cutMUAP(spikes,windowl,emg(channel,:));
        waveform(channel,:) = mean(temp,1);
    end
    MUAPs{mu} = waveform;
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

%% Step 14: Calculate MUAP maps and motor-unit locations
% The channel with the largest MUAP peak-to-peak amplitude
p2ps = zeros(size(emg,1),nMUs);
chan_max = zeros(nMUs,1);% channel with maximum p2p

for mu = 1:nMUs
    p2ps(:,mu) = peak2peak(MUAPs{mu},2); % get peak to peak values
    [~,chan_max(mu)] = max(p2ps(:,mu));  % Get MU electrode location

%% Step 15: Restore bad-channel positions in MUAP results

% Insert NaNs at excluded channel positions so that MUAP matrices and maps 
% retain the same channel indexing as the original EMG recording.
if ~isempty(badchan)

    restoredMUAPs = cell(size(MUAPs));
    for mu = 1:nMUs
        restoredWaveform = nan(nChannelsOriginal,size(MUAPs{mu},2));
        restoredWaveform(goodchan,:) = MUAPs{mu};
        restoredMUAPs{mu} = restoredWaveform;
    end
    MUAPs = restoredMUAPs;
    restoredP2P = nan(nChannelsOriginal,nMUs);
    restoredP2P(goodchan,:) = p2ps;
    p2ps = restoredP2P;

    for mu = 1:nMUs
        chan_max(mu) = goodchan(chan_max(mu));
    end
end

%% Step 17: Create the signal structure

signal = struct;

signal.data = originalEMG; %channels x samples
signal.fsamp = fs;
signal.ngrid = 1;
signal.Pulsetrain = {Pulsetrain}; % motor units x samples

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

parameters = struct;

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

%% Step 22: Save outputs

decomp_results.B = B;
decomp_results.sil_all = sil_all;
decomp_results.cov_all = CoV;
decomp_results.peaks = Pulsetrain;
decomp_results.MUPulses = Dischargetimes;
decomp_results.spike_train = spike_train;
decomp_results.MUAPs = MUAPs;
decomp_results.fr = fr;
decomp_results.mean_fr = mean_fr;
decomp_results.p2ps = p2ps;
decomp_results.MU_locs = chan_max;
decomp_results.D = D;
decomp_results.E = E;
decomp_results.whitened_mat = w_mat;
decomp_results.MUFilters = MUFilters;

% MUedit-compatible outputs
decomp_results.signal = signal;
decomp_results.parameters = parameters;

end

