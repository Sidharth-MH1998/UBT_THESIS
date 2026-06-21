function [analysed_results, extra_data] = analyseHyser1dof_singleTrial_v2(decomp_results, force, emg_pre, target_digit, plotOption)
%{
    Performs deep analysis on force data and MU related activity per trial
    INPUTS:
    decomp_results: 4x1 struct, output of the MU decomposition pipeline
    force: 2500 x 5 double, time series of digits force at 100 Hz during 25 secs
    emg_pre: 51200 x 256 double, preprocessed emg at 2048 Hz
    target_digit: number from 1 to 5 depending on the digit the participant was instructed to use
    % plotOption: In case plots should be generated

    OUTPUTS:
    
    analysed_results: 4x1 struct, with updated MU statistics values, plus the following extra variables:
        Variables per grid:
        - activePeriods: nMUs x 2, starts and end times of each MU active periods
        - MUactContained: nMUs x 8, boolean containing 1 in the time segments where each MU was active
        - totalActiveTimes: nMUs x 1 double, total time in seconds the MU was active  
        - agonistMUs, antagonistMUs, cocontractingMUs: nMUs x 1, boolean containing 1 when a MU was agonist, antagonist, or co-contracting
        - active_mean_fr: nMUs x 8 double containing mean discharge rate in the time segments where each MU was active, NaN where inactive
        - segmSpikeTrain: nMUs x 8 cell containing spike trains (sparse double) in the time segments where each MU was active, NaN where inactive
        - segmSmoothedDRs: nMUs x 8 cell containing smoothed spike trains (double) in the time segments where each MU was active, NaN where inactive
        - CoV: nMUs x 8 double containing coefficient of variation of smoothed spike trains where each MU was active, NaN where inactive
        - smoothedDRs: nMUs x 51200 double containing smoothed spike trains of the whole time series
    extra_data: struct with additional behavioural/force and EMG metrics
        - SNR: 1x 256 channels signal-to-noise ratio
        - t_in: 1x9 double, timings marking the starts and ends of each time segment
        - durations: 8x1 double, duraitons of each time segment
        - pos_amp1: estimated amplitude of first positive force peak
        - pos_amp2: estimated amplitude of second positive force peak
        - neg_amp1: estimated amplitude of negative force peak
        - c1: constant force at start of force trace
        - c_end: constant force at end of force trace
        - t_fit: time vector of fitted force
        - fitted_force: fitted_force
        - rmse_fit: RMSE computed against the fitted force trace
        - rmse_ideal: RMSE computed against the ideal force trace
        - digit_ind: measure of digit individuation
        - timeNormEMG: time normalised EMG power at 204.8 Hz
        - downsampledTime: time vector at 204.8 Hz
    

    @author: Renato Mio
    Created: 31.05.2024
%}

% Colour plotting variables
b_hx = [0 0.4470 0.7410]; % blue
or_hx = [0.8500 0.3250 0.0980]; % orange
y_hx = [0.9290 0.6940 0.1250]; % yellow/gold
p_hx = [0.4940 0.1840 0.5560]; % purple
g_hx = [0.4660 0.6740 0.1880]; % green
lb_hx = [0.3010 0.7450 0.9330]; % light blue

fs = 2048;

%% Fix firing timings (if there are any MUs)

% First, due to the padding, we need to make sure that spike trains, peaks
% and MUPulses are only 25 seconds / 51200 samples long
for i=1:4
    samples = size(decomp_results(i).results.spike_train,1);
    padding = (samples - 51200)/2; % number of samples added at beginning and end (zero padding)
    if padding<=0 % No adjustment needed if 0, no MUs detected if padding is negative
        continue
    else
        decomp_results(i).results.spike_train = decomp_results(i).results.spike_train(padding+1:end-padding,:);
        decomp_results(i).results.peaks = decomp_results(i).results.peaks(:,padding+1:end-padding);
        % We generate the pulses again from the spike trains
        for mu=1:length(decomp_results(i).results.MUPulses)
            decomp_results(i).results.MUPulses{1,mu} = find(decomp_results(i).results.spike_train(:,mu))';
        end
    end
end

%% Second, we verify and remove duplicate MUs between grids

ngrids = length(decomp_results);
checkDuplicatesBgrids = 1;

% Run the analysis when MUs are detected in a trial
fmu = [~isempty(decomp_results(1).results.spike_train) ~isempty(decomp_results(2).results.spike_train)...
    ~isempty(decomp_results(3).results.spike_train) ~isempty(decomp_results(4).results.spike_train)];

% We need a 1 x ngrid cell array to hold all MU pulse/spike trains
allPulseTrain{1,1} = decomp_results(1).results.spike_train'; % in a MUs x samples double format
allPulseTrain{1,2} = decomp_results(2).results.spike_train';
allPulseTrain{1,3} = decomp_results(3).results.spike_train';
allPulseTrain{1,4} = decomp_results(4).results.spike_train';
% Do the same for discharge times / MU pulses
nMUsmax = max([length(decomp_results(1).results.MUPulses) length(decomp_results(2).results.MUPulses) length(decomp_results(3).results.MUPulses) length(decomp_results(4).results.MUPulses)]);
allDisTimes = cell(4,nMUsmax);
for i=1:ngrids
    for mu=1:nMUsmax
        if mu <= length(decomp_results(i).results.MUPulses) % only do until we go through all MUs in a grid
            allDisTimes{i,mu} = decomp_results(i).results.MUPulses{1,mu};
        end
    end
end

if sum(fmu) > 0 && checkDuplicatesBgrids == 1
    nmu = 0;
    for i = 1:size(allPulseTrain,2) % for every grid
        if ~isempty(allPulseTrain{i})
            nmu = nmu + size(allPulseTrain{i},1);
        end
    end
    % PROBLEM, last i is empty grid, size wrong
    PulseT = zeros(nmu, max(cellfun(@length,allPulseTrain)) ); % nMUs x nSamples (we get nSamples from a non-empty pulse train)
    Distim = cell(1,nmu);
    muscle = zeros(1,nmu);
    mu = 1;
    for i = 1:size(allPulseTrain,2) % for every grid
        if ~isempty(allPulseTrain{i}) % if MU spikes were detected
            for j = 1:size(allPulseTrain{i},1) % for every MU
                PulseT(mu,:) = allPulseTrain{i}(j,:);
                Distim{mu} = allDisTimes{i,j};
                muscle(mu) = i;
                mu = mu+ 1;
            end
        end
    end
    
    [PulseT, Distim, muscle] = remduplicatesbgrids(PulseT, Distim, muscle, round(fs/40), 0.00025, 0.3, fs);

    % Get indexes of survivor MUs
    survivors = zeros(ngrids,nMUsmax);
    for mu = 1:length(Distim)
        isSurvivor = cellfun(@(x) isequal(x,Distim{1,mu}), allDisTimes);
        [row,col] = find(isSurvivor);
        survivors(row,col) = 1;
    end

    % We update the decomp_results variable
    for g=1:4
        duplicateMUs = find(survivors(g,1:length(decomp_results(g).results.sil_all))==0);  % crop to a length to match the actual number of MUs 
        decomp_results(g).results = discardMUs_singleTrial(duplicateMUs,decomp_results(g).results);
    end

    clear allPulseTrain allDisTimes PulseT Distim muscle survivors isSurvivor row col duplicateMUs nMUsmax nmu mu fmu
end

%% Single force sample analysis

fs_force = 100; % force sampling frequency
fs = 2048; % emg sampling frequency
t = 1/fs_force:1/fs_force:25; % time vector in force sampling frequency

% Get positive and negative amplitudes
% Low-pass force to remove noise
force = lowpass(force,5,fs_force);
force_data = force(:,target_digit);
if plotOption
    lpforce = lowpass(force_data,5,fs_force);
    figure; plot(t,lpforce)
    plot(t,force(:,2))
    xlabel('Time (s)');
    ylabel('Force');
end

% [t1, t2, t3, t4, t5, t6, t7, rmse, pos_amp, neg_amp, c1, c_end] = fit_triangular_signal_v3(force_data', 0.01);
[t1, t2, t3, t4, t5, t6, t7, rmse_fit, pos_amp1, pos_amp2, neg_amp, c1, c_end] = fit_triangular_signal_v4(force_data', 0.01);

% Generate the fitted signal for comparison
[t_fit, fitted_force] = generate_triangular_signal_v5(t1, t2, t3, t4, t5, t6, t7, pos_amp1, pos_amp2, neg_amp, c1, c_end, 1/fs_force);

% Time delimiters for each segment
t_in = [0,t1,t1+t2,t1+t2+t3,t1+t2+t3+t4,t1+t2+t3+t4+t5,t1+t2+t3+t4+t5+t6,t1+t2+t3+t4+t5+t6+t7,25];
% By segment durations
stagesDurations = [t1 t2 t3 t4 t5 t6 t7 25-(t1+t2+t3+t4+t5+t6+t7)]';

% Plot the results
if plotOption
    figure;
    plot(t, force_data, 'b');
    hold on;
    plot(t_fit, fitted_force, 'r--');
    title(sprintf('Noisy Signal and Fitted Signal (RMSE: %.4f)', rmse_fit));
    xlabel('Time (s)');
    ylabel('Force');
    legend('Noisy Signal', 'Fitted Signal');
    grid on;
end

%% Compute force tracking precision metrics

force_ideal = force_trace();
rmse_ideal = sqrt(mean((force_data' - force_ideal).^2)); % RMSE computed agains ideal force trace

% Measure of finger individuation (only during tracking)
t_start = round(t1*fs_force);
t_end = round((t1+t2+t3+t4+t5+t6+t7)*fs_force);
target_rms = rms(force(t_start:t_end,target_digit));
% Get rms for other fingers
nontargets_rms = 0;
for digit=1:5
    if digit~= target_digit
        nontargets_rms = nontargets_rms + rms(force(t_start:t_end,digit));
    end
end

digit_ind = (target_rms-nontargets_rms)/rms(force_ideal);% individuation metric

% Save behavioural data
extra_data.t_in = t_in;
extra_data.durations = stagesDurations;
extra_data.pos_amp1 = pos_amp1;
extra_data.pos_amp2 = pos_amp2;
extra_data.neg_amp1 = neg_amp;
extra_data.c1 = c1;
extra_data.c_end = c_end;
extra_data.t_fit = t_fit;
extra_data.fitted_force = fitted_force;
extra_data.rmse_fit = rmse_fit;
extra_data.rmse_ideal = rmse_ideal;
extra_data.digit_ind = digit_ind;

%% Use discharge timings to compute SNR
idx_emg_in = round(t_in * fs); % indexes of time segments in emg time series

% Compute SNR as the ratio between the active area and the first 3 seconds (6144 samples)
SNR = 10*log10(mean(emg_pre(idx_emg_in(2):idx_emg_in(8),:).^2)./mean(emg_pre(1:6144,:).^2));
extra_data.SNR = SNR;

%% Get time-normalised EMG power envelope to verify behavioural consistency
t_emg = 0:1/fs:25-1/fs; % Time vector

% Downsample factor and cutoff frequency
downsample_factor = 10;
cutoff_freq = 5; % Cutoff frequency in Hz

% Compute the low-passed power and downsample it
[emg_power, downsampled_time] = lowpassed_downsample_emg(emg_pre, fs, downsample_factor, cutoff_freq);

% Plot if needed
if plotOption
    figure; subplot(2,1,1)
    plotMeanAndDev(mean(emg_power(:,1:128),2)', std(emg_power(:,1:128),1,2)', b_hx, b_hx, 0.3)
    subplot(2,1,2)
    plotMeanAndDev(mean(emg_power(:,129:256),2)', std(emg_power(:,129:256),1,2)', or_hx, or_hx, 0.3)
    title('EMG power')
end

% Do again for time_normalised emg
t_out = [0 5 7.5 10 12.5 15 17.5 20 25]; % timings needed after the normalisation
timeNorm_emg = timeNormalise(emg_power, t_in,t_out,fs/downsample_factor);

% Plot excluding indexes with SNR under 5 dB
if plotOption
    figure; subplot(2,1,1)
    plotMeanAndDev( mean(timeNorm_emg( :, setdiff(1:128,find(SNR<5)) ),2)', std(timeNorm_emg( :, setdiff(1:128,find(SNR<5))) ,1,2)', b_hx, b_hx, 0.3)
    subplot(2,1,2)
    plotMeanAndDev(mean(timeNorm_emg( :, setdiff(129:256,find(SNR<5)) ),2)', std(timeNorm_emg( :, setdiff(129:256,find(SNR<5))) ,1,2)', or_hx, or_hx, 0.3)
    title('Time-normalised EMG power')
end


extra_data.timeNormEMG = timeNorm_emg;
extra_data.downsampledTime = downsampled_time;

%% Now we analyse the start and end periods of time where every MU is active

% Set threshold and sampling rate
ppsThresh = 5; % Discharge rate threshold in pulses per second (Hz)
restThresh = 1; % secs
minActDur = 0.5;

% Variables needed
overlapThresh = 0.5;

% Analyse per grid
for g=1:4
    if isempty(decomp_results(g).results.MUPulses) % If no MUs were detected, set variables to NaN
        decomp_results(g).results.activePeriods = NaN;
        decomp_results(g).results.MUactContained = NaN;
        decomp_results(g).results.totalActiveTimes = NaN;
        decomp_results(g).results.agonistMUs = NaN;
        decomp_results(g).results.antagonistMUs = NaN;
        decomp_results(g).results.cocontractingMUs = NaN;
        decomp_results(g).results.active_mean_fr = NaN;
        decomp_results(g).results.segmSpikeTrain = NaN;
        decomp_results(g).results.segmSmoothedDRs = NaN;
        decomp_results(g).results.CoV = NaN;
        decomp_results(g).results.smoothedDRs = NaN;
        continue
    end
    % Find active periods
    activePeriods = find_MU_active_periods_v2(decomp_results(g).results.spike_train, ppsThresh, fs, restThresh, minActDur, plotOption);
    % Match active periods with the different force trace stages
    [MUactContained] = MUactiveStages_v2(activePeriods, stagesDurations, overlapThresh); % size is MUs x stages
    % MUs with no activity relevant in any force-active segment (segments 2 to 7)
    inactiveMUs = find(~sum(MUactContained(:,2:7),2)>0);
    % Remove inactive MUs
    decomp_results(g).results = discardMUs_singleTrial(inactiveMUs,decomp_results(g).results);
    activePeriods(inactiveMUs,:) = [];
    MUactContained(inactiveMUs,:) = [];
    
    % We will use the toal MU active times later:
    totalActiveTimes = cellfun(@(x) sum(x(:,2)-x(:,1)), activePeriods);

    % Agonists MUs would be the ones in sync with the force direction
    % Antagonists MUs would be against force direction
    % Additionally, we also flag co-contracting MUs
    if g==1||g==2 % The case of grids in posterior forearm / extensors
        % MUs are agonists if they are active in segments 2 or 3 and 6 or 7
        % or 8 (this last one because of late de-recruitment), but inactive during segments 4 and 5
        agonistMUs = (MUactContained(:,2)|MUactContained(:,3)) & (MUactContained(:,6)|MUactContained(:,7)|MUactContained(:,8)) & ~(MUactContained(:,4)|MUactContained(:,5));
        % MUs are antagonists if they are active in segments 4 or 5 only
        antagonistMUs = (MUactContained(:,4)|MUactContained(:,5)) & ~(MUactContained(:,1)|MUactContained(:,2)|MUactContained(:,3)|MUactContained(:,6)|MUactContained(:,7)|MUactContained(:,8));
        % If the total active time is higher than 80% of the force-active time segment duration, then we can consider it a co-contracting MU
        % BUT excluding posterior forearm, agonists MUs, which may also span long periods given the de-recruitment delay 
        cocontractingMUs = (totalActiveTimes>(t2+t3+t4+t5+t6+t7)*.8) & ~antagonistMUs;

    else % The case of grids in anterior forearm / flexors
        % MUs are agonists if they are active in segments 4 or 5 only
        agonistMUs = (MUactContained(:,4)|MUactContained(:,5)) & ~(MUactContained(:,1)|MUactContained(:,2)|MUactContained(:,3)|MUactContained(:,6)|MUactContained(:,7)|MUactContained(:,8));
        % MUs are antagonists if they are active in segments 2 or 3 and 6 or 7 or 8 but inactive during segments 4 and 5
        antagonistMUs = (MUactContained(:,2)|MUactContained(:,3)) & (MUactContained(:,6)|MUactContained(:,7)|MUactContained(:,8)) & ~(MUactContained(:,4)|MUactContained(:,5));
        % If the total active time is higher than 80% of the force-active time segment duration, then we can consider it a co-contracting MU
        cocontractingMUs = totalActiveTimes>(t2+t3+t4+t5+t6+t7)*.8;
    end
  
    % For each active stage, get mean firing rates
    active_mean_fr = zeros( size(MUactContained,1), 8 );
    segmSpikeTrain = cell( size(MUactContained,1), 8 );
    segmSmoothedDRs = cell( size(MUactContained,1), 8 );
    CoV = zeros( size(MUactContained,1), 8 );
    
    for mu=1:size(MUactContained,1)
        for segm=1:length(MUactContained(mu,:)) % 8 time segments
            if MUactContained(mu,segm) % if there's activity, get mean firing rate
                [active_mean_fr(mu,segm), segmSpikeTrain{mu,segm}] = dischargeRatesInTimeSegment(decomp_results(g).results.spike_train(:,mu), fs, t_in(segm), t_in(segm+1));
                segmSmoothedDRs{mu,segm} = smoothFirings(segmSpikeTrain{mu,segm},fs);
                CoV(mu,segm) = std(segmSmoothedDRs{mu,segm})/mean(segmSmoothedDRs{mu,segm});
            else % otherwise fill with NaN
                active_mean_fr(mu,segm) = NaN;
                segmSpikeTrain{mu,segm} = NaN;
                segmSmoothedDRs{mu,segm} = NaN;
                CoV(mu,segm) = NaN;
            end
        end
    end

    % We also save the smoothed DRs for the whole time series for every MU
    smoothedDRs = smoothFirings(decomp_results(g).results.spike_train,fs);

    % Save results
    decomp_results(g).results.activePeriods = activePeriods;
    decomp_results(g).results.MUactContained = MUactContained;
    decomp_results(g).results.totalActiveTimes = totalActiveTimes;
    decomp_results(g).results.agonistMUs = agonistMUs;
    decomp_results(g).results.antagonistMUs = antagonistMUs; 
    decomp_results(g).results.cocontractingMUs = cocontractingMUs;
    decomp_results(g).results.active_mean_fr = active_mean_fr;
    decomp_results(g).results.segmSpikeTrain = segmSpikeTrain;
    decomp_results(g).results.segmSmoothedDRs = segmSmoothedDRs;
    decomp_results(g).results.CoV = CoV;
    decomp_results(g).results.smoothedDRs = smoothedDRs;
end

analysed_results = decomp_results;

end