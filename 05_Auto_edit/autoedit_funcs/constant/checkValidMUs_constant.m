function [validMUs, spiketrains, activePeriods, recruitThresh, validCoV, survivorMUs] = checkValidMUs(spiketrains, force, CoV, fs, fs_force, firingThreshHz, restThresh, minActiveDuration)

% This function was originally meant to only keep MUs highly correlated
% with force activity and to clean MUs with too few spikes. This resulted
% in the removal of several MUs with tonic behaviour.
% UPDATE 17.12.2025
% We will keep early-active tonic MUs as they could display rate-coding behaviour.
% These pre-active MUs will have their recruitment threshold set to 0.
% However, MUs that only become active after trial end will still be removed.

% Pipeline is:
% --- 0. Initialise index tracking
% --- 1. Define trial timings
% --- 2. Filter 1: Remove MUs with low spike count (<100)
% --- 3. Detect MUs active periods
% --- 4. Determine recruitment times
% --- 5. Filter 2: Remove late units (recruited after the force trace)
% --- 6. Calculate recruitment thresholds
% --- 7. Filter 3: Remove MUs with activity durations under 5 secs
% --- 8. Final sorting by recruitment threshold

    % 0. Initialise index tracking
    survivorMUs = 1:size(spiketrains, 2);

    % 1. Define trial timings
    % Get whole trial and ramp durations in seconds
    trialDur = length(force)/fs_force;
    if trialDur == 74
        rampDur = 2;
    else
        rampDur = 4;
    end

    % 2. Filter 1: Remove MUs with low spike count (<100)
    fewSpikes = sum(full(spiketrains(:,:)),1) < 100;
    spiketrains(:,fewSpikes) = [];
    CoV(:,fewSpikes) = [];
    survivorMUs(:,fewSpikes) = [];

    % 3. Get active periods
    activePeriods = find_MU_active_periods_v2(spiketrains, firingThreshHz, fs, restThresh, minActiveDuration, 0);

    % If no active periods, also remove these MUs from the pipeline
    emptyAP = cellfun(@isempty, activePeriods);
    if any(emptyAP)
        spiketrains(:,emptyAP) = [];
        CoV(emptyAP) = [];
        activePeriods(emptyAP) = [];
        survivorMUs(emptyAP) = [];
    end

    % 4. Recruitment times in seconds
    recruitTimes = cell2mat(cellfun(@(x) min(x, [], "all"), activePeriods, 'UniformOutput', false));

    % 5. Filter 2: Remove late units (recruited after the force trace)
%     outSpikes = (recruitTimes < 3) | (recruitTimes > (5 + rampDur + 2));
    outSpikes = (recruitTimes > (5 + rampDur + 2));
    spiketrains(:,outSpikes) = [];
    CoV(:,outSpikes) = [];
    activePeriods(outSpikes) = [];
    recruitTimes(outSpikes) = [];
    survivorMUs(outSpikes) = [];

    % 6a. Resample force from fs_force to fs
    t_force = (0:length(force)-1) / fs_force;
    t_target = (0:1/fs:(length(force)-1)/fs_force);
    force_resampled = interp1(t_force, force, t_target, 'linear', 'extrap');

    % 6b. Get recruitment thresholds from resampled force
    recruitSamples = max(1, min(round(recruitTimes * fs), length(force_resampled)));
    recruitThresh = force_resampled(recruitSamples);
    % FIX: Handle pre-active MUs: MUs active before the ramp (<3s) likely have undefined or baseline force thresholds.
    % We force their RThresh to 0 so they sort correctly to the bottom (Bin 0).
    recruitThresh(recruitTimes < 3) = 0;

    % 7. Filter 3: Remove MUs with activity durations under 5 secs
    activeDurations = cellfun(@(x) max(x, [], "all") - min(x, [], "all"), activePeriods);
%     activeMUs = find(activeDurations > 55); % old filter, now relaxed to keep more MUs 
    activeMUs = find(activeDurations > 5);

    spiketrains = spiketrains(:,activeMUs);
    validCoV = CoV(:,activeMUs);
    activePeriods = activePeriods(activeMUs);
    recruitThresh = recruitThresh(activeMUs);
    recruitTimes = recruitTimes(activeMUs);
    survivorMUs = survivorMUs(activeMUs);

    % 8. Sort by recruitment threshold (low -> high)
    [recruitThresh, sortIdx] = sort(recruitThresh, 'ascend');
    recruitTimes = recruitTimes(sortIdx);
    spiketrains = spiketrains(:,sortIdx);
    validCoV = validCoV(:,sortIdx);
    activePeriods = activePeriods(sortIdx);
    survivorMUs = survivorMUs(sortIdx);

    % Output number of valid MUs
    validMUs = length(survivorMUs);

end