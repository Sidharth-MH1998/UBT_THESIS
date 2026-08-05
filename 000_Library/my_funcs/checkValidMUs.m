function [validMUs, spiketrains, activePeriods, recruitThresh, validCoV] = checkValidMUs(spiketrains, force, CoV, fs, fs_force, firingThreshHz, restThresh, minActiveDuration)

    % Get whole trial and ramp durations in seconds
    trialDur = length(force)/fs_force;
    if trialDur == 74
        rampDur = 2;
    else
        rampDur = 4;
    end

    % Remove MUs with less than 100 spikes
    fewSpikes = sum(full(spiketrains(:,:)),1) < 100;
    spiketrains(:,fewSpikes) = [];
    CoV(:,fewSpikes) = [];

    % Get active periods
    activePeriods = find_MU_active_periods_v2(spiketrains, firingThreshHz, fs, restThresh, minActiveDuration, 0);

    % Recruitment times in seconds
    recruitTimes = cell2mat(cellfun(@(x) min(x, [], "all"), activePeriods, 'UniformOutput', false));

    % Remove MUs recruited outside ramp
    outSpikes = (recruitTimes < 3) | (recruitTimes > (5 + rampDur + 2));
    spiketrains(:,outSpikes) = [];
    CoV(:,outSpikes) = [];
    activePeriods(outSpikes) = [];
    recruitTimes(outSpikes) = [];

    % Resample force from fs_force to fs
    t_force = (0:length(force)-1) / fs_force;
    t_target = (0:1/fs:(length(force)-1)/fs_force);
    force_resampled = interp1(t_force, force, t_target, 'linear', 'extrap');

    % Get recruitment thresholds from resampled force
    recruitSamples = max(1, min(round(recruitTimes * fs), length(force_resampled)));
    recruitThresh = force_resampled(recruitSamples);

    % Keep MUs with active periods longer than 55s
    activeDurations = cellfun(@(x) max(x, [], "all") - min(x, [], "all"), activePeriods);
    activeMUs = find(activeDurations > 55);

    spiketrains = spiketrains(:,activeMUs);
    validCoV = CoV(:,activeMUs);
    activePeriods = activePeriods(activeMUs);
    recruitThresh = recruitThresh(activeMUs);
    recruitTimes = recruitTimes(activeMUs);

    % Sort by recruitment threshold
    [recruitThresh, sortIdx] = sort(recruitThresh, 'ascend');
    recruitTimes = recruitTimes(sortIdx);
    spiketrains = spiketrains(:,sortIdx);
    validCoV = validCoV(:,sortIdx);
    activePeriods = activePeriods(sortIdx);

    % Output number of valid MUs
    validMUs = length(recruitThresh);

end