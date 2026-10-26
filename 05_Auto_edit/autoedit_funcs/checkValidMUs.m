function [validMUs, spiketrains, CoV, SIL, activePeriods, recruitTimes] = checkValidMUs(fLevel, trialType, spiketrains, CoV, SIL, fs)
% Made specifically for the dataset by Renato Mio and Jan Bodenschlaegel (2025).
%     Trials decomposed using decompose3.mat function.
%     Experiment consisted in thumb, index and middle finger (one at a time)
%     isometric flexion at 10% and 20% of MVF.
%     Three types of trials were recorded:
%         - Trapezium force trace with 15s plateau and 5 %MVF/s up and down
%         slopes.
%         - Sinusoidal force trace at 0.5 Hz (slow) for 15 cycles.
%         - Sinusoidal force trace at 1.5 Hz (fast) for 15 cycles.

    % get general trial phases/timings in seconds
    % this can be derive from the target force level and the type of trial
    % trialDur: total trial duration
    % highForceTime: start time of the force plateau in trapezium  trials or force-active phase in sine trials
    if strcmp(trialType,'') && strcmp(fLevel,'10') % trial type is just an empty string for trapezium trials
        trialDur = 15+2*2+5*2; highForceTime = 5+2; activeForceDuration = 15; % force plateau duration
    elseif strcmp(trialType,'') && strcmp(fLevel,'20') % trial type is just an empty string for trapezium trials
        trialDur = 15+4*2+5*2; highForceTime = 5+4; activeForceDuration = 15; % force plateau duration
    elseif strcmp(trialType,'_sine05')
        trialDur = 30+5*2; highForceTime = 5; activeForceDuration = 30; % active sine force trace duration at 0.5 Hz
    elseif strcmp(trialType,'_sine15')
        trialDur = 10+5*2; highForceTime = 5; activeForceDuration = 10; % active sine force trace duration at 1.5 Hz
    end

    % parameters to determine MUs active periods
    if strcmp(trialType,'')
        firingThreshHz = 2; % minimum spiking frequency
        restThresh = 0.5; % time in seconds between spikes to go from active to inactive
        minActiveDuration = 1;
    else
        firingThreshHz = 0; % more flexible in the case of sinusoidal force traces
        restThresh = 0.1; 
        minActiveDuration = 0.01;
    end

    % keep track of valid MU indices
    validMUs = 1:size(spiketrains,2);

    % Remove MUs with less than 20 spikes
    % (before, we used a threshold of 100 spikes for 60s-plateau trials
    fewSpikes = sum(full(spiketrains(:,:)),1) < 20;
    validMUs(fewSpikes) = [];
    spiketrains(:,fewSpikes) = [];
    CoV(fewSpikes) = [];
    SIL(fewSpikes) = [];

    % Get active periods
    activePeriods = find_MU_active_periods_v2(spiketrains, firingThreshHz, fs, restThresh, minActiveDuration, 0);

    % If no active periods, also remove these MUs from the pipeline
    emptyAP = cellfun(@isempty, activePeriods);
    if any(emptyAP)
        validMUs(emptyAP) = [];
        spiketrains(:,emptyAP) = [];
        CoV(emptyAP) = [];
        SIL(emptyAP) = [];
        activePeriods(emptyAP) = [];
    end

    % Recruitment times in seconds
    recruitTimes = cell2mat(cellfun(@(x) min(x, [], "all"), activePeriods, 'UniformOutput', false));

    % Remove MUs recruited outside plateau and slopes +-2 secs
    outSpikes = (recruitTimes > (highForceTime + 2)); 
    validMUs(outSpikes) = [];
    spiketrains(:,outSpikes) = [];
    CoV(outSpikes) = [];
    SIL(outSpikes) = [];
    activePeriods(outSpikes) = [];
    recruitTimes(outSpikes) = [];

    % CHANGED: no recruitment threshold calculation here anymore
    % Resample force from fs_force to fs
%     t_force = (0:length(force)-1) / fs_force;
%     t_target = (0:1/fs:(length(force)-1)/fs_force);
%     force_resampled = interp1(t_force, force, t_target, 'linear', 'extrap');
% 
%     % Get recruitment thresholds from resampled force
%     recruitSamples = max(1, min(round(recruitTimes * fs), length(force_resampled)));
%     recruitThresh = force_resampled(recruitSamples);
    
    % CHANGED: removed this criterion
    % Keep MUs with active periods longer than 0.5 * force plateau or active sine force trace duration
%     activeDurations = cellfun(@(x) max(x, [], "all") - min(x, [], "all"), activePeriods);
%     activeMUs = find(activeDurations > 0.5*activeForceDuration);
% 
%     spiketrains = spiketrains(:,activeMUs);
%     CoV = CoV(:,activeMUs);
%     activePeriods = activePeriods(activeMUs);
%     recruitThresh = recruitThresh(activeMUs);
%     recruitTimes = recruitTimes(activeMUs);

    % CHANGED: No sorting by recruitment threshold here
    % Sort by recruitment threshold
%     [recruitThresh, sortIdx] = sort(recruitThresh, 'ascend');
%     recruitTimes = recruitTimes(sortIdx);
%     spiketrains = spiketrains(:,sortIdx);
%     validCoV = CoV(:,sortIdx);
%     activePeriods = activePeriods(sortIdx);
% 
%     % Output sorted indices of valid MUs
%     validMUs = sortIdx;

end