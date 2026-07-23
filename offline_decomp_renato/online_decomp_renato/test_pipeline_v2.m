% Test pipeline v2, using functions in I-Spin live

% path = "D:\Datasets\SingleDigitForceEMG\raw\S15\S15_ss1_dig2_f10_t3.mat";
% For trial at 10% MVC
% path = "/Users/renatomio/Library/CloudStorage/OneDrive-UniversitätBayreuth/2Laptop/S15_ss1_dig2_f10_t3.mat";

% For trial at 20% MVC
path = "D:\UBT_Thesis\decomp_code_and_data\S15_ss1_dig2_f20_t1.mat";


load(path)
fs = 2000; % emg sampling rate
fs_force = 50;
digit = 2;
ElChannelMap = getElChannelMap("HD08MM1305");

[emg, emg_rms, emg_rms_grid1, emg_rms_grid2, emg_power, force, force_rmse, digit_ind, badchan, goodchan, SNR, discard] = ...
                    proc_hdemg(recordedEMG,recordedForce, fTrace, digit, fs,fs_force, ElChannelMap);

%% Prepare to decompose
% % Decomposition parameters
% NITER = 25; % iterations to run the decomposition
% ref_exist = 1; % if ref_signal exist ref_exist = 1; if not ref_exist = 0 and manual selection of windows
% checkEMG = 0; % 0 = Consider all the channels ; 1 = Visual checking
% differentialmode = 0; % 0 = no; 1 = yes (filter out the smallest MU, can improve decomposition at the highest intensities
% initialization = 1; % 0 = max EMG; 1 = random weights
% peeloff_flag = 1; % 0 = no; 1 = yes (update the residual EMG by removing the motor units with the highest SIL value)
% covfilter = 1; % 0 = no; 1 = yes (filter out the motor units with a coefficient of variation of their ISI > than parameters.covthr)
% refineMU = 1; % 0 = no; 1 = yes (refine the MU spike train over the entire signal 1-remove the discharge times that generate outliers in the discharge rate and 2- reevaluate the MU pulse train)
% preproc_flag = 1; % 0 = no; 1 = yes (apply notch and bandpass, if the signal has not been preprocessed)
% padLen = 200; % length to add zero padding to our signal only during decomposition (sometimes needed to prevent decomposition mistakes)
% 
% % SPECIFIC VALUES
% nbelectrodes = 64; % number of electrodes per grid or array
% thresholdtarget = 0.8; % threshold to segment the target displayed to the participant, 1 being the maxima of the target (e.g., plateau)
% nbextchan = 1000; % nb of extended channels (1000 in Negro 2016, can be higher to improve the decomposition)
% contrastfunc = 'skew'; % contrast functions: 'skew', 'kurtosis', 'logcosh'
% silthr = 0.9; % Threshold for SIL values
% covthr = 0.7; % Threshold for CoV of ISI values
% peeloffwin = 0.025; % duration of the window (ms) for detecting the action potentials from the EMG signal
% duplicatesthresh = 0.3; % threshold that define the minimal percentage of common discharge times between duplicated motor units
% CoVDR = 0.3; % threshold that define the CoV of Discharge rate that we want to reach for cleaning the MU discharge times when refineMU is on
% 
% IED = 8; % inter-electrode distance

%% Only variables needed here
NITER = 25; % iterations to run the decomposition
silthr = 0.9; % Threshold for SIL values
covthr = 0.3; % Threshold for CoV of ISI values
peeloff_flag = 1; % 0 = no; 1 = yes (update the residual EMG by removing the motor units with the highest SIL value)
peeloffwin = 0.025; % duration of the window (ms) for detecting the action potentials from the EMG signal
refineMU = 1; % 0 = no; 1 = yes (refine the MU spike train over the entire signal 1-remove the discharge times that generate outliers in the discharge rate and 2- reevaluate the MU pulse train)
CoVDR = 0.3; % threshold that define the CoV of Discharge rate that we want to reach for cleaning the MU discharge times when refineMU is on

t_start = 20; % start time to crop EMG signal
t_end = 50; % end time to crop EMG signal

%% Using I-Spin functions

nbextchan = 1000; % number of extended channels
            
offsetMU = 0; % used for plotting

% Crop to only have data from t_start to t_end seconds
SIG = emg(1:64,t_start*fs+1:t_end*fs);
SIG = SIG(goodchan<=64,:); % discard bad channels

% Signal Extension
exFactor = round(nbextchan/size(SIG,1));
eSIG = extend(SIG,exFactor);
eSIG = demean(eSIG);

% Signal Whitening
[E, D] = pcaesig(eSIG);
[wSIG, ~, dewhiteningMatrix] = whiteesig(eSIG, E, D);

% % Removing the edges
% wSIG = wSIG(:,round(fs):end-round(fs));

% FastICA
% Initialize matrix B (n x m) n: separation vectors, m: iterations 
% Initialize matrix MUFilters to only save the reliable filters
% Intialize SIL and PNR
B = zeros(size(wSIG,1), NITER); % all separation vectors
MUFilters = zeros(size(wSIG,1), NITER); % only reliable vectors
SIL = zeros(1,NITER);
COV = zeros(1,NITER);
%% Fast ICA
% Find the index where the square of the summed whitened vectors is
% maximized and initialize W with the whitened observations at this time
for j = 1:NITER
    if j == 1
        X = wSIG; % Initialize X (whitened signal), then X: residual
        w = randn(size(X,1),1); % Initialize w
    else
        w = randn(size(X,1),1); % Initialize w
    end
    
    w = w - B * B' * w; % Orthogonalization
    w = w / norm(w); % Normalization
    
    %       3a: Fixed point algorithm (end when sparsness is maximized)
    maxiter = 500; % max number of iterations for the fixed point algorithm
    w = fixedpointalg(w, X, B , maxiter, 'skew');
    
    % Step 4: Minimization of the CoV of discharge times (end when CoV is
    % minimized)
    % Initialize CoV (variation of interspike intervals, %) Step 4a => 4e
    [~, spikes] = getspikes(w, X, fs);
    
    if length(spikes) > 10 % If the number of peaks is low, skip the second algorithm
        ISI = diff(spikes/fs); % Interspike interval
        COV(j) = std(ISI)/mean(ISI); % Coefficient of variation
        Wini = sum(X(:,spikes),2); % update W by summing the spikes
                       
        % Minimization of the CoV of discharge times (end when CoV is minimized)
        [MUFilters(:,j), ~, COV(j)] = minimizeCOVISI(Wini, X, COV(j), fs);
        B(:,j) = w;
    
        % Calculate SIL values
        [~, ~, SIL(j)] = calcSIL(X, MUFilters(:,j), fs);
        
        % Peel-off of the (reliable) source    
        if peeloff_flag == 1 && SIL(j) > silthr
           X = peeloff(X, spikes, fs, peeloffwin);
        end

    else
        B(:,j) = w;
    end
    disp(['Iter : ' num2str(j) ' - SIL : ' num2str(round(SIL(j),2)) ' - COV : ' num2str(round(COV(j),2))]);

end

%% Filter out MUfilters below the SIL threshold
MUFilters(:,SIL < silthr) = [];
COV(SIL < silthr) = [];
SIL(SIL < silthr) = [];
MUFilters(:,COV > covthr) = [];
MUFilters = dewhiteningMatrix * MUFilters;

%% Get the pulse train for the entire signal
EMG = emg(1:64,t_start*fs+1:t_end*fs);
EMGmask = zeros(size(EMG,1),1);
EMGmask(badchan(badchan<=64)) = 1;
[PulseT, Distime, ~] = getPulseT(EMG, EMGmask, MUFilters, fs);

% Remove duplicates
[~, Distime] = remduplicates(PulseT, Distime, Distime, round(fs/40), 0.00025, 0.3, fs);

% Get the decomposition parameters for the biofeedback
MUFilters = getMUfilters(EMG, EMGmask, Distime);
[PulseT, Distime, ~] = getPulseT(EMG, EMGmask, MUFilters, fs);
% [extensionfactor, iReSIG, norm, centroid] = getonlineparameters(EMG, EMGmask, MUFilters, fs);
%% Check number of spikes and remove MUs with low count

spikeCount = cellfun(@length, Distime);
lowCount = spikeCount < 10; % minimum number of spikes
% Remove those spikes from the filters
MUFilters(:,lowCount) = [];
[PulseT, Distime, ~] = getPulseT(EMG, EMGmask, MUFilters, fs);
[extensionfactor, iReSIG, norm, centroid] = getonlineparameters(EMG, EMGmask, MUFilters, fs);

%% Refine MU spike trains
if refineMU == 1    
    % Remove outliers generating irrelevant discharge rates before manual edition (1st time)
    Distime = remoutliers(PulseT, Distime, CoVDR, fs);

    % Reevaluate all the unique motor units over the contractions
    [PulseT, Distime] = refineMUs(EMG, EMGmask, PulseT, Distime, fs); % second argument is EMG mask (flagged channels)

    % Remove outliers generating irrelevant discharge rates before manual edition (2nd time)
    Distime = remoutliers(PulseT, Distime, CoVDR, fs);
end

% Update filters and online parameters
MUFilters = getMUfilters(EMG, EMGmask, Distime);
[PulseT, Distime, ~] = getPulseT(EMG, EMGmask, MUFilters, fs);
[extensionfactor, iReSIG, norm, centroid] = getonlineparameters(EMG, EMGmask, MUFilters, fs);

%% Plot pulse train from the offline decomposition

time = linspace(0,size(PulseT,2)/fs,size(PulseT,2));
offsetMU = 0;
figure;
for k = 1:length(Distime)
    plot(time, PulseT(k,:)+2*k+offsetMU, time(Distime{k}), PulseT(k,Distime{k})+2*k+offsetMU, 'o', 'LineWidth', 1.5, 'MarkerSize', 3, 'Color', [0.8 0.8 0.8], 'MarkerEdgeColor', [0.81 0.50 1.00]);
    hold on
    Dischargetimes{k} = Distime{k};
    DR(k) = mean(1./(diff(Distime{k})/fs));
end
title("Offline decomposition")
ylim([1.5 offsetMU+2*length(Distime)+1.5]); set(gca,'YTick',[]); set(get(gca, 'YAxis'), 'Visible', 'off');
xlim([0 10])
xlabel("Time (s)"); ylabel("MU spike trains")
    
%% Perform reverse procedure using MUfilters

EMG_online = zeros(size(emg(1:64,t_start*fs+1:(t_end)*fs)));

Refreshrate = 60; % Hz, for the biofeedback
durationonline = size(EMG_online,2); % total number of samples in the trial to analyse
nsamp = floor(fs/Refreshrate); % number of samples per window

nwin = floor(durationonline/nsamp); % number of windows to evaluate
nwinbuff = floor(fs*5/nsamp); % 5 seconds buffer equals nwinbuff windows
k = 1; % index for the window

% Pre allocate empty matrices
Time = linspace(0,nwin*nsamp/fs,nwin*nsamp);

EMGtmp1 = zeros(size(EMG_online,1),nsamp); % nsamp is samples in the time window for biofeedback
EMGtmp2 = zeros(sum(EMGmask==0),nsamp);
esample2 = zeros(sum(EMGmask==0)*extensionfactor,extensionfactor-1);
Distime = zeros(nwin*nsamp, size(MUFilters,2));
Pulsetrain = zeros(size(MUFilters,2), nsamp*nwin);
noise_centroids = ones(nsamp,size(MUFilters,2)) .* (centroid(:,1)');
spike_centroids = ones(nsamp,size(MUFilters,2)) .* (centroid(:,2)');
MUfilt = MUFilters' * iReSIG;
MUoffset = 1:1:size(MUFilters,2);
forcefb = zeros(1,nwin);
feedback = zeros(1,nwin);

data = emg(1:64,t_start*fs+1:(t_end+5)*fs); % simulates the data coming online

while k <= nwin % - floor(nwinbuff/2)
    EMG_online(:,(k-1)*nsamp+1:k*nsamp) = data(:,(k-1)*nsamp+1:k*nsamp); % simulates reading a batch of data points according to the refresh rate and saving it in preallocated memory
    EMGtmp1 = EMG_online(:, (k-1)*nsamp+1:k*nsamp); % temporary variable for incoming EMG
    EMGtmp2 = EMGtmp1(EMGmask==0, :); % Only good EMG channels
    [Pulsetrain(:,(k-1)*nsamp+1:k*nsamp), Distime((k-1)*nsamp+1:k*nsamp, :), esample2] = getspikesonline(EMGtmp2, extensionfactor, esample2, MUfilt, norm, noise_centroids, spike_centroids, nsamp, fs); % Get spikes  
    k = k+1;
end

%% Verify decomposition

% First, change "Distime" to the previous "Dischargetimes" variable format
% Preallocate cell array
Dischargetimes_online = cell(1, size(Distime, 2));

% Find and store nonzero indices per column
for mu = 1:size(Distime, 2)
    Dischargetimes_online{mu} = find(Distime(:, mu)); % Row indices for each column
end

%% Plot results of online decomposition

figure;
offsetMU = 0;
for mu = 1:length(Dischargetimes_online)
    plot(Time, Pulsetrain(mu,:)+2*mu+offsetMU, Time(Dischargetimes_online{mu}), Pulsetrain(mu,Dischargetimes_online{mu})+2*mu+offsetMU, 'o', 'LineWidth', 1.5, 'MarkerSize', 5, 'Color', [0.4660 0.6740 0.1880], 'MarkerEdgeColor', [0.81 0.50 1.00]);
    hold on
    % Dischargetimes{k} = Distime{k};
    DR_online(mu) = mean(1./(diff(Dischargetimes_online{mu})/fs));
end
title("Motor neurons decoded with MU filters")
ylim([1.5 offsetMU+2*length(Dischargetimes_online)+1.5]); set(gca,'YTick',[]); set(get(gca, 'YAxis'), 'Visible', 'off');
xlim([0 10])
xlabel("Time (s)")

%% Add real-time decomposition performance metrics
tolerance = 20; % Number of samples allowed as tolerance

% Preallocate metrics
sensitivity = zeros(1, length(Dischargetimes_online));
precision = zeros(1, length(Dischargetimes_online));
false_negative_rate = zeros(1, length(Dischargetimes_online));
rate_of_agreement = zeros(1, length(Dischargetimes_online));

for mu = 1:length(Dischargetimes_online)
    % Get the manually edited spike train (offline) and real-time spike train
    offline_spikes = Dischargetimes{mu};
    online_spikes = Dischargetimes_online{mu};

    % Initialize counters
    TP = 0; % True positives
    FN = 0; % False negatives
    FP = 0; % False positives

    % % Sort spikes to ensure comparisons are ordered
    % offline_spikes = sort(offline_spikes);
    % online_spikes = sort(online_spikes);

    % Match spikes with tolerance
    matched_online = false(size(online_spikes)); % Tracks matched spikes in online train
    matched_offline = false(size(offline_spikes)); % Tracks matched spikes in offline train

    for i = 1:length(offline_spikes)
        % Find the closest online spike within tolerance
        candidates = find(abs(online_spikes - offline_spikes(i)) <= tolerance);
        if ~isempty(candidates)
            % Match to the first unmatched candidate
            for c = candidates
                if ~matched_online(c)
                    matched_online(c) = true;
                    matched_offline(i) = true;
                    TP = TP + 1; % True positive
                    break;
                end
            end
        end
    end

    % Calculate false negatives and false positives
    FN = sum(~matched_offline); % Unmatched offline spikes
    FP = sum(~matched_online); % Unmatched online spikes

    % Calculate metrics
    sensitivity(mu) = TP / (TP + FN);
    precision(mu) = TP / (TP + FP);
    false_negative_rate(mu) = FN / (TP + FN);
    rate_of_agreement(mu) = TP / (TP + FN + FP);
end

% Display results
disp('Sensitivity:'), disp(sensitivity)
disp('Precision:'), disp(precision)
disp('False Negative Rate:'), disp(false_negative_rate)
disp('Rate of Agreement:'), disp(rate_of_agreement)

disp(['Sensitivity: ', num2str(mean(sensitivity), '%.2f'), ' ± ', num2str(std(sensitivity), '%.2f')])
disp(['Precision: ', num2str(mean(precision), '%.2f'), ' ± ', num2str(std(precision), '%.2f')])
disp(['False Negative Rate: ', num2str(mean(false_negative_rate), '%.2f'), ' ± ', num2str(std(false_negative_rate), '%.2f')])
disp(['Rate of Agreement: ', num2str(mean(rate_of_agreement), '%.2f'), ' ± ', num2str(std(rate_of_agreement), '%.2f')])