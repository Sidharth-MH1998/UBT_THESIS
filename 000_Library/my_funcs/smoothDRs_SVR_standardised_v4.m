function [smoothedRatesMatrix, standardizedTime, recruitmentThresh, svr_params] = smoothDRs_SVR_standardised_v4(spike_train, activePeriods, forceData, fs, fs_force, resampleFs)
    % Smooth discharge rates computed via Support Vector Regression with consistent sampling times for easier post processing.
    % This version (v4) uses Bayesian optimisation instead of full grid search for parameter tuning           
    % Parameters:
    %   spike_train: Sparse double matrix (nSamples x nMUs) containing spike trains.
    %   activePeriods: Cell array (1 x nMUs) with [startTime, endTime] for active periods (seconds).
    %   forceData: Vector of force values (nSamples x 1).
    %   fs: Original sampling frequency of spike trains (Hz).
    %   fs_force: Sampling frequency of force data (Hz).
    %   resampleFs: Desired resampling frequency (Hz).
    %
    % Returns:
    %   smoothedRatesMatrix: Matrix (nMUs x nResampledTimePoints) with smoothed rates.
    %   standardizedTime: Standardized time vector (1 x nResampledTimePoints) in seconds.
    %   recruitmentThresh: Vector (1 x nMUs) of recruitment thresholds based on force.
    %   svr_params: SVR grid search best parameters per MU [KernelScale, BoxConstraint]

    [nSamples, nMUs] = size(spike_train);
    trialDuration = nSamples / fs;
    standardizedTime = linspace(0, trialDuration, round(trialDuration * resampleFs));
    nTimePoints = numel(standardizedTime);

    smoothedRatesMatrix = zeros(nMUs, nTimePoints);
    recruitmentThresh = nan(1, nMUs);
    svr_params = nan(nMUs, 2);  % [KernelScale, BoxConstraint]

    parfor mu = 1:nMUs
        if isempty(activePeriods{mu})
            continue;
        end

        spikeIndices = find(spike_train(:, mu));
        spikeTimes = spikeIndices / fs;

        if numel(spikeTimes) < 2
            continue;
        end

        % Hann smoothing for reference
        hannWidth = 1; % seconds
        hannSmoothed = smoothFirings_v2(spike_train(:, mu), fs, hannWidth);

        % --- Prepare training data ---
        trainY = hannSmoothed(spikeIndices);
        trainX = spikeTimes(:);

        % --- Define Bayesian optimisation variables ---
        optimVars = [
            optimizableVariable('BoxConstraint', [10, 500], 'Transform', 'log');
            optimizableVariable('KernelScale', [0.5, 5], 'Transform', 'log')
        ];

        % --- Objective function ---
        objFun = @(params)kfoldLoss(fitrsvm(trainX, trainY, ...
            'KernelFunction', 'rbf', ...
            'BoxConstraint', params.BoxConstraint, ...
            'KernelScale', params.KernelScale, ...
            'KFold', 5));

        results = bayesopt(objFun, optimVars, ...
            'Verbose', 0, ...
            'AcquisitionFunctionName', 'expected-improvement-plus', ...
            'MaxObjectiveEvaluations', 30, ...
            'IsObjectiveDeterministic', true, ...
            'UseParallel', false);

        bestParams = results.XAtMinObjective;

        tempRow = zeros(1, nTimePoints);

        for ap = 1:size(activePeriods{mu}, 1)
            startTime = activePeriods{mu}(ap, 1) - 0.05;
            endTime = activePeriods{mu}(ap, 2) + 0.05;
            activeSpikeTimes = spikeTimes(spikeTimes >= startTime & spikeTimes <= endTime);

            if numel(activeSpikeTimes) < 2
                continue;
            end

            isi = diff(activeSpikeTimes);
            instRates = 1 ./ isi;
            instTimes = activeSpikeTimes(2:end);

            epsilon = max(iqr(instRates) / 11, 1e-6);
            weights = ones(numel(instRates), 1);
            weights(1:min(5, numel(instRates))) = 5;
            weights(max(1, end-4):end) = 5;

            mdl = fitrsvm(instTimes, instRates, ...
                'KernelFunction', 'rbf', ...
                'KernelScale', bestParams.KernelScale, ...
                'BoxConstraint', bestParams.BoxConstraint, ...
                'Epsilon', epsilon, ...
                'Weights', weights);

            timeIndices = standardizedTime >= startTime & standardizedTime <= endTime;
            predictedRates = predict(mdl, standardizedTime(timeIndices)');
            predictedRates(predictedRates < 0) = 0;
            tempRow(timeIndices) = predictedRates;
            smoothedRatesMatrix(mu, :) = tempRow;
        end

        recruitTime = min(activePeriods{mu}(:, 1));
        recruitIdx = round(recruitTime * fs_force);
        if recruitIdx > 0 && recruitIdx <= numel(forceData)
            recruitmentThresh(mu) = forceData(recruitIdx);
        end

        svr_params(mu, :) = [bestParams.KernelScale, bestParams.BoxConstraint];
    end
end