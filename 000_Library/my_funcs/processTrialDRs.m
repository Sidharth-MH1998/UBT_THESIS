function [smoothedDRs, meanDR, activePeriods, recruitThresh, covDRs, recruitThresh2, covDRs2, b, rmse]  ...
     = processTrialDRs(spiketrain, meanDR, force, cohortRanges, fs, fs_force, firingThreshHz, restThresh, minActiveDuration)
    
    % Helper function to process a single trial discharge rates
    % Inputs:
    % spiketrain - Spiketrain data for the trial (nMUs x 1)
    % meanDR - mean DR of each MU (samples x nMUs)
    % force - Force data vector for the trial
    % fs - Sampling frequency of spiketrains
    % fs_force - Sampling frequency of force data
    % cohortRanges - Array (1 x numCohorts+1) specifying cohort threshold edges
    % firingThreshHz, restThresh, minActiveDuration: parameters to find MU spike trains active periods

    % Get whole trial and ramp durations in seconds
    trialDur = length(force)/fs_force;
    if trialDur == 74
        rampDur = 2;
    else
        rampDur = 4;
    end

    % Remove MUs with less than 100 spikes
    fewSpikes = sum(full(spiketrain(:,:)),1) < 100;
    spiketrain(:,fewSpikes) = [];
    
    % Get active periods for both grids
    activePeriods = find_MU_active_periods_v2(spiketrain, firingThreshHz, fs, restThresh, minActiveDuration, 0);

    % Recruitment thresholds
    recruitTimes = cell2mat(cellfun(@(x) min(x, [], "all"), activePeriods, 'UniformOutput',false));
    
    % Remove MUs recruited outside ramp
    outSpikes = (recruitTimes < 3) | (recruitTimes > (5+rampDur+2));
    spiketrain(:,outSpikes) = [];
    activePeriods(outSpikes) = [];
    recruitTimes(outSpikes) = [];

    recruitThresh = force(floor(recruitTimes .* fs_force));

    % We only keep the MUs with active periods over 55 seconds
    activeDurations = cellfun(@(x) max(x,[],"all") - min(x,[],"all"), activePeriods);
    activeMUs = find(activeDurations>55);
    spiketrain = spiketrain(:,activeMUs);
    meanDR = meanDR(activeMUs);
    activePeriods = activePeriods(activeMUs);
    recruitThresh = recruitThresh(activeMUs);
    recruitThresh2 = recruitThresh; % copy to be updated later

    % Smooth discharge rates
    smoothedDRs = smoothDischargeRates_SVR(spiketrain, activePeriods, fs, 0);

%     % Compute CoV of DRs per cohort
%     covDRs = computeCoVDRs(smoothedDRs, recruitThresh, cohortRanges);
    covDRs = [];
    % Compute CoV of DRs
    for muIdx = 1:length(smoothedDRs)
        % Extract the smoothed DR (second column of the matrix)
        smoothedDR = smoothedDRs{muIdx}(:, 2);
        % Compute the CV for this MU
        muMean = mean(smoothedDR);
        muStd = std(smoothedDR);
        muCV = muStd / muMean;

        % Append to cohort CVs
        covDRs = [covDRs; muCV];
    end

    covDRs2 = covDRs; % to be updated later

    % Compute regression coefficients
    [smoothedDRs_stand, standTime, recruitThresh] = smoothDRs_SVR_standardised(spiketrain, activePeriods, force, fs, fs_force, fs);

    % Resample the force signal to match the standard time vector
    % (sampled at fs)
    timeForce = (0:length(force) - 1) / fs_force; % Original time vector for force
    force_resamp = interp1(timeForce, force, standTime, 'linear', 0)'; % Pad missing values with zeros, samples as first dimension
    
    % Apply dynamic sampling to keep the focus on the edges where the force varies more
    fs_middle = 100;  % Reduced middle sampling frequency
    focus_duration = 12;  % High resolution duration in seconds
    [smoothedDRs_sampled, force_sampled] = dynamicSampling(smoothedDRs_stand', force_resamp, fs, fs_middle, focus_duration);
    
    % Fit linear model using non-negative least squares regression (MUs contribution cannot be negative)
    % and iteratively remove low-importance MUs
    weightsChanged = true;
    weightThreshold = 0.05; % Minimum importance/weight threshold for determining irrelevant MUs
    while weightsChanged
        % Fit linear model
        b = lsqnonneg(smoothedDRs_sampled, force_sampled);
        
        % Identify MUs with weights below the threshold
        lowImportanceMUs = find(b < weightThreshold);

        % Check if there are changes to be made
        if isempty(lowImportanceMUs)
            weightsChanged = false; % Stop if all weights are above the threshold
        else
            % Remove low-importance MUs
            smoothedDRs_sampled(:,lowImportanceMUs) = [];
            recruitThresh2(lowImportanceMUs) = [];
            covDRs2(lowImportanceMUs) = [];
        end
    end 
    
    % Predict the curve using the regression coefficients
    predictions = smoothedDRs_sampled * b;  % X is your design matrix, b are the regression coefficients
    
    % Get RMSE
    rmse = sqrt(mean((force_sampled - predictions).^2)); 
    
end