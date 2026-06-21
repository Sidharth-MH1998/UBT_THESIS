function decomp_results = decompose3(emg, fs, badchan, padLen, initialization, NITER, nbextchan, silthr, covfilter, covthr, ...
    differentialmode, peeloff_flag, peeloffwin, duplicatesthresh, CoVDR, contrastfunc, refineMU, preproc_flag)

% INPUTS: 
% emg: signal in channels x samples
% fs: sampling frequency
% badchan: list of bad channels to discard for decomposition
% padLen: lenght in samples for zero padding the signal
% NITER = 50;
% ref_exist = 1; % if ref_signal exist ref_exist = 1; if not ref_exist = 0 and manual selection of windows
% checkEMG = 0; % 0 = Consider all the channels ; 1 = Visual checking
% nwindows = 1; % number of segmented windows over each contraction
% differentialmode = 0; % 0 = no; 1 = yes (filter out the smallest MU, can improve decomposition at the highest intensities
% initialization = 1; % 0 = max EMG; 1 = random weights
% peeloff_flag = 1; % 0 = no; 1 = yes (update the residual EMG by removing the motor units with the highest SIL value)
% covfilter = 0; % 0 = no; 1 = yes (filter out the motor units with a coefficient of variation of their ISI > than covthr)
% refineMU = 0; % 0 = no; 1 = yes (refine the MU spike train over the entire signal 1-remove the discharge times that generate outliers in the discharge rate and 2- reevaluate the MU pulse train)
% duplicatesbgrids = 0; % 0 = do not consider duplicates between grids ; 1 = Remove duplicates between grids
% nbextchan = 1000; % nb of extended channels (1000 in Negro 2016, can be higher to improve the decomposition)
% edges = 0.2; % edges of the signal to remove after preprocessing the signal (in sec)
% contrastfunc = 'skew'; % contrast functions: 'skew', 'kurtosis', 'logcosh'
% silthr = 0.9; % Threshold for SIL values
% covthr = 0.5; % Threshold for CoV of ISI values
% peeloffwin = 0.025; % duration of the window (ms) for detecting the action potentials from the EMG signal
% duplicatesthresh = 0.3; % threshold that define the minimal percentage of common discharge times between duplicated motor units
% CoVDR = 0.3; % threshold that define the CoV of Discharge rate that we want to reach for cleaning the MU discharge times when refineMU is on

% OUTPUTS
% Struct containing fields:
% B: separation matrix (nbexthannels x NITER)
% peaks: pulse trains of each MU with original amplitudes (nMUs x nSamples)
% MUPulses: discharge times of each MU (1 x nMUs cell)
% sil_all: SIL values of each MU (1 x nMUs)
% cov_all: CoV of ISI for each MU spike train (1 x nMUs)
% MUAPs: MUAP waveforms (1 x nMUs cell, and each is nChannels x 103 double)
% fr: firing rates (instantaneous) time series for each MU (1 x nMUs cell)
% mean_fr: mean fr for each MU (nMUs x 1 double)
% p2ps: peak to peak of each MUAP waveform (nChannels x nMUs)
% MU_locs: location of MU designes as the channel with max p2p (nMUs x 1)

% Changes: 02.10.24
% - removed unnecesary variables
% - added preproc_flag to either perform the preprocessing inside the function or not
% - changed notchsignals for adaptivenotchfilter function
% Changes 05.11.24
% - added bad channels and zero padding as inputs
% - added fixing of timings within the function

% @author: Renato Mio

%% Step 0: Initialise results
decomp_results.B = [];
decomp_results.peaks = [];
decomp_results.MUPulses = [];
decomp_results.spike_train = [];
decomp_results.sil_all = [];
decomp_results.cov_all = [];
decomp_results.MUAPs = [];
decomp_results.fr = [];
decomp_results.mean_fr = [];
decomp_results.p2ps = [];
decomp_results.MU_locs = [];

%% Step 1: Preprocessing

    if preproc_flag
%       1a: Removing line interference (Notch filter)
        emg = adaptiveNotchFilter(emg,fs);
%       1b: Bandpass filtering
        emg = bandpassingals(emg,fs, 1);
    end

    % Prepare signal for decomposition
    nChannels = size(emg,1);
    disp(strcat("Signal has ", num2str(nChannels), " channels"))
    if not(isempty(badchan))
        disp(strcat("There are ", num2str(length(badchan)), " bad channels"))
        goodchan = setdiff(1:nChannels, badchan);
        emg = emg(goodchan,:);
    end
    if padLen > 0
        emg = [zeros(size(emg,1),padLen) emg zeros(size(emg,1),padLen)];
        disp(strcat("Padding enabled, the signal is now ", num2str(size(emg,2)), " samples long"))
    end

%       1c: Differentiation (perform only if there is many motor units,
%      filter out the smallest motor units) useful for high intensities
    if differentialmode
        emg = diff(emg,1,2);
    end

%       1d: Signal extension (extension factor calculated to reach 1000 channels)
    exFactor = round(nbextchan/size(emg,1));
%     ReSIG = zeros(exFactor * size(emg,1)); % commented lines that don't seem to do anything
%     iReSIG = zeros(exFactor * size(emg,1));
    
    eSIG = extend(emg, exFactor); % extended signal

%     ReSIG = eSIG * eSIG' / size(eSIG,2); % commented lines that don't seem to do anything
%     iReSIG = pinv(ReSIG); % Moore-Penrose pseudoinverse

%       1e: Removing the mean
    eSIG = demean(eSIG);

%% Step 2: Whitening
%Whitening with a regularization factor (average of the smallest half of 
%the eigenvalues of the covariance matrix from the extended signals)

%       2a: Get eigenvalues and eigenvectors (regularization factor =>
%       average smallest half of eigenvalues)
    [E, D] = pcaesig(eSIG); %Returns the eigenvector (E) and diagonal eigenvalue (D) matrices7  

%       2b: Zero-phase component analysis
    [wSIG,w_mat, ~] = whiteesig(eSIG, E, D);
    %clearvars E D

%% Step 3: FastICA method

% Initialize matrix B (n x m) n: separation vectors, m: iterations 
% Initialize matrix MUFilters to only save the reliable filters
% Intialize SIL and PNR

B = zeros(size(wSIG,1), NITER); % all separation vectors
MUFilters = zeros(size(wSIG,1), NITER); % only reliable vectors, later unreliable removed
w = zeros(size(wSIG,1), 1);
icasig = zeros(NITER, size(wSIG,2));
SIL = zeros(1, NITER);
CoV = zeros(1, NITER);
idx1 = zeros(1, NITER);

% Find the index where the square of the summed whitened vectors is
% maximized and initialize W with the whitened observations at this time

for j = 1:NITER
    if j == 1
        X = wSIG; % Initialize X (whitened signal), then X: residual
        if initialization == 0
            actind = sum(X,1).^2;
            [~, idx1(j)] = max(actind);
            w = X(:, idx1(j)); % Initialize w with the time at max emg activity 
        else
            w = randn(size(X,1),1);
        end
        time = linspace(0,size(X,2)/fs,size(X,2));
    else
        if initialization == 0
            actind(idx1(j-1)) = 0; % remove the previous vector
            [~, idx1(j)] = max(actind);
            w = X(:, idx1(j)); % Initialize w
        else
            w = randn(size(X,1),1);
        end
    end
    
    w = w - B * B' * w; % Orthogonalization
    w = w / norm(w); % Normalization
    
    %       3a: Fixed point algorithm (end when sparsness is maximized)
    maxiter = 500; % max number of iterations for the fixed point algorithm
    w = fixedpointalg(w, X, B , maxiter, contrastfunc);
    
    % Step 4: Minimization of the CoV of discharge times (end when CoV is% minimized)
    
    % Initialize CoV (variation of interspike intervals, %) Step 4a => 4e
    [icasig, spikes] = getspikes(w, X, fs);
    
    if length(spikes) > 10
        ISI = diff(spikes/fs); % Interspike interval
        CoV(j) = std(ISI)/mean(ISI); % Coefficient of variation
        Wini = sum(X(:,spikes),2); % update W by summing the spikes
                       
        % Minimization of the CoV of discharge times (end when CoV is minimized)
        [MUFilters(:,j), spikes, CoV(j)] = minimizeCOVISI(Wini, X, CoV(j), fs);
        B(:,j) = w;
    
        % Calculate SIL values
        [icasig, spikes, SIL(j)] = calcSIL(X, MUFilters(:,j), fs);
        
        % Peel-off of the (reliable) source    
        if peeloff_flag == 1 && SIL(j) > silthr
           X = peeloff(X, spikes, fs, peeloffwin);
        end
    
        disp(['Iteration #' num2str(j) ' - Sil = ' num2str(SIL(j)) ' CoV = ' num2str(CoV(j))])
        
    else
        B(:,j) = w;
    end
end

% Filter out MUfilters below the SIL threshold
MUFilters(:,SIL < silthr) = [];
% Save sil values for the ones above the threshold
sil_all = SIL(SIL>silthr);
CoV(SIL < silthr) = []; % remove below SIL thresh

% Check CoV of ISI < covthr
if covfilter == 1
    MUFilters(:,CoV > covthr) = [];
    sil_all = sil_all(CoV < covthr); % keep the ones under CoV thresh
    CoV(CoV > covthr) = []; % remove CoV over threshold
end

%% Remove duplicates and outliers and calculate additional metrics

% Batch processing over each window
[PulseT, distime] = batchprocessfilters_1win(MUFilters, wSIG, exFactor, differentialmode, size(emg,2), fs);

if size(PulseT,1) > 0 && size(PulseT,2) == size(emg,2)  % Only continue if MUs were detected, and if PulseT lenght is correct (prevents bugs)
    % Remove duplicates
    [PulseT, distimenew] = remduplicates(PulseT, distime, distime, round((fs/40)), 0.00025, duplicatesthresh, fs);
    
    % Check which indexes are missing after removing duplicates and outliers
    idx_miss = [];
    % Check only if some MUs were removed
    if numel(distimenew) < numel(distime) % true if MUs were removed
        for i = 1:length(distime)
            % check for every element in distime if it is present in
            % distimenew
            check = false;
            for j = 1:length(distimenew)
                if isequal(distime{i},distimenew{j})
                    check = true;
                end
            end      
            % if it's not present then index i from distime is missing in distimenew
            if ~check
                idx_miss =  [idx_miss i];
            end
        end        
    end
    % Clean SIL and CoV after removing duplicates
    sil_all(idx_miss) = [];
    CoV(idx_miss) = [];

    if refineMU == 1    
        % Remove outliers generating irrelevant discharge rates before manual edition (1st time)
        distimenew = remoutliers(PulseT, distimenew, CoVDR, fs);
    
        % Reevaluate all the unique motor units over the contractions
        [Pulsetrain, distimenew] = refineMUs(emg, ones(1,64), PulseT, distimenew, fs); % second argument is EMG mask (flagged channels)
        
        % Remove outliers generating irrelevant discharge rates before manual edition (2nd time)
        distimenew = remoutliers(Pulsetrain, distimenew, CoVDR, fs);
    else
        Pulsetrain = PulseT;
    end
    
    Dischargetimes = {};

    %%%% Clean and save the results


    for j = 1:length(distimenew)
        % In some cases a single spike is detected and that generates an
        % error in computing MUAPs. We can delete MUs with under 10 spikes
        if length(distimenew{j})>10
            Dischargetimes{j} = distimenew{j};
        end
    end
    
    if length(Dischargetimes)>0 % Remove empty cells indexes
        Dischargetimes = Dischargetimes(~cellfun('isempty',Dischargetimes));
        sil_all = sil_all(~cellfun('isempty',Dischargetimes));
        CoV = CoV(~cellfun('isempty',Dischargetimes));
    end


    if length(Dischargetimes)>0 % if true, there are MUs detected

        % First, if there was padding, we remove it here
        % Remove padding from variables that have a nSamples dimension
        % We need to make sure that spike trains, peaks and MUPulses have
        % the right length

        nMUs = length(Dischargetimes);

        % Get spike train from results
        % Convert indices to sparse matrix of ones representing spikes before plotting
        MUindices = Dischargetimes;
        spike_train = zeros( size(emg,2), nMUs);
        for mu=1:size(MUindices,2)
            spike_train(MUindices{1,mu}, mu) = 1;
        end
        spike_train = sparse(spike_train);

        % if there was padding, we remove it here
        if padLen > 0
            disp("Removing padding")
            emg = emg(:,padLen+1:end-padLen); % remove padding from original signal
            spike_train = spike_train(padLen+1:end-padLen,:); % remove padding from spike train
            Pulsetrain = Pulsetrain(:,padLen+1:end-padLen); % remove padding from pulse train (with amplitudes)
            % We generate the pulses (indices) again from the updated spike trains
            for mu=1:nMUs
                Dischargetimes{1,mu} = find(spike_train(:,mu))';
            end
            disp(strcat("Back to ", num2str(size(emg,2)), " samples long"))
        end
    
        % Compute MUAP waveforms
        % peeloffwin = 0.025; % duration of the window (ms) for detecting the action potentials from the EMG signal
        windowl = round(peeloffwin*fs); % 51 samples for 0.025 ms
        MUAPs = cell(1,nMUs);  
        for mu = 1:nMUs
            spikes = Dischargetimes{mu};
            firings = zeros(1, size(emg,2));
            firings(spikes) = 1;
            for l = 1:size(emg,1)
                temp = cutMUAP(spikes,windowl,emg(l,:));
                waveform(l,:) = mean(temp,1);
            end
            MUAPs{mu} = waveform;
        end

        % Get firing rates
        fr = cell(1, nMUs);
        mean_fr = zeros(nMUs, 1);
        for i=1:nMUs
            peak_indices = Dischargetimes{i};
            fr{1,i}= [0 (1./diff(peak_indices)*fs)];
            mean_fr(i,1) = mean(fr{1,i});
        end

        % Get MUAP locs and p2p map
        p2ps = zeros(size(emg,1),nMUs); % cummulative
        chan_max = zeros(nMUs,1); % channel with maximum p2p
       
        for mu = 1:nMUs % iterate over each MU index
            % get peak to peak values
            p2ps(:,mu) = peak2peak(MUAPs{mu},2);
            % Get MU electrode location
            chan_max(mu,1) = find(p2ps(:,mu) == max(p2ps(:,mu)));
        end
    
        % Fix MUAPs, p2ps and locs when there were bad channels
        if not(isempty(badchan))
            MUAPs2 = cell(size(MUAPs));
            for mu=1:nMUs
                MUAPs2{mu} = MUAPs{mu};
                temp = nan(nChannels,1+2*windowl);
                temp(goodchan,:) = MUAPs2{mu};
                MUAPs{mu} = temp;
            end

            p2ps2 = nan(nChannels,nMUs);
            p2ps2(goodchan,:) = p2ps;
            p2ps = p2ps2;
            
            chan_max2 = zeros(nMUs,1);
            for mu=1:nMUs
                chan_max2(mu,1) = goodchan(chan_max(mu,1));
            end
            chan_max = chan_max2;
        end

        % Save outputs
        decomp_results.B = B;
        decomp_results.sil_all = sil_all;
        decomp_results.cov_all = CoV;
        decomp_results.peaks = Pulsetrain;
        decomp_results.MUPulses = Dischargetimes; % indices (discharge timings)
        decomp_results.spike_train = spike_train; % 0s and 1s
        decomp_results.MUAPs = MUAPs; % waveforms
        decomp_results.fr = fr;
        decomp_results.mean_fr = mean_fr;
        decomp_results.p2ps = p2ps;
        decomp_results.MU_locs = chan_max;
        decomp_results.D= D;
        decomp_results.E= E;
        decomp_results.whitened_mat= w_mat;
        decomp_results.MUFilters=MUFilters;
    end

end


end