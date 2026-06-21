function [smoothedRatesMatrix, standardizedTime, recruitmentThresh, svr_params] = smoothDRs_SVR_standardised_v3(spike_train, activePeriods, forceData, fs, fs_force, resampleFs)
    % Smooth discharge rates computed via Support Vector Regression with consistent sampling times for easier post processing.
    % This version (v3) was parallelised using parfor           
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
    trialDuration = nSamples / fs; % Trial duration in seconds
    standardizedTime = linspace(0, trialDuration, round(trialDuration * resampleFs)); % Standardized time vector
    nTimePoints = numel(standardizedTime);
    % Pre-allocate variables
    smoothedRatesMatrix = zeros(nMUs, nTimePoints); % Initialize output
    recruitmentThresh = nan(1, nMUs); % Initialize recruitment thresholds
    svr_params = nan(nMUs, 2);  % To save best parameters per MU [KernelScale, BoxConstraint]

    % Define grid search ranges for KernelScale and BoxConstraint
    kernelScaleRange = 0.5:0.5:5; % Fine grid for KernelScale
    boxConstraintRange = 50:10:500; % Fine grid for BoxConstraint

    % Process each MU
    parfor mu = 1:nMUs
        % Skip if no active periods or spikes
        if isempty(activePeriods{mu})
            continue;
        end

        % Get spike times for this MU
        spikeIndices = find(spike_train(:, mu));
        spikeTimes = spikeIndices / fs; % Convert indices to time (seconds)

        % Skip if fewer than 2 spikes
        if numel(spikeTimes) < 2
            continue;
        end

        % Grid search for optimal SVR parameters
        bestSSE = inf;
        bestKernelScale = NaN;
        bestBoxConstraint = NaN;

        % Hann window as reference
        hannWidth = 1; % 1-second window
        hannSmoothed = smoothFirings_v2(spike_train(:, mu), fs, hannWidth);

        for k = kernelScaleRange
            for b = boxConstraintRange
                try
                    % Train SVR model on Hann smoothed rates
                    mdl = fitrsvm(spikeTimes, hannSmoothed(spikeIndices), ...
                        'KernelFunction', 'rbf', ...
                        'KernelScale', k, ...
                        'BoxConstraint', b);

                    % Predict rates
                    predRates = predict(mdl, spikeTimes);

                    % Calculate SSE
                    sse = sum((predRates - hannSmoothed(spikeIndices)).^2);
                    if sse < bestSSE
                        bestSSE = sse;
                        bestKernelScale = k;
                        bestBoxConstraint = b;
                    end
                catch
                    % Handle cases where fitting fails
                    continue;
                end
            end
        end

        tempRow = zeros(1, nTimePoints); % 

        % Process active periods
        for ap = 1:size(activePeriods{mu}, 1)
            % Extract active period start and end
            startTime = activePeriods{mu}(ap, 1) - 0.05; % Extend start
            endTime = activePeriods{mu}(ap, 2) + 0.05;   % Extend end
            activeSpikeTimes = spikeTimes(spikeTimes >= startTime & spikeTimes <= endTime);

            % Skip if fewer than 2 spikes in active period
            if numel(activeSpikeTimes) < 2
                continue;
            end

            % Compute instantaneous firing rates (ISI-based)
            isi = diff(activeSpikeTimes); % Interspike intervals (seconds)
            instRates = 1 ./ isi; % Hz
            instTimes = activeSpikeTimes(2:end); % Time points for instantaneous rates

            % Train SVR on optimal parameters
            epsilon = max(iqr(instRates) / 11, 1e-6); % Epsilon from IQR
            weights = ones(numel(instRates), 1);
            weights(1:min(5, numel(instRates))) = 5; % First 5 rates
            weights(max(1, numel(instRates) - 4):end) = 5; % Last 5 rates
            mdl = fitrsvm(instTimes, instRates, ...
                'KernelFunction', 'rbf', 'KernelScale', bestKernelScale, ...
                'BoxConstraint', bestBoxConstraint, 'Epsilon', epsilon, ...
                'Weights', weights);

            % Predict smooth rates for standardized time vector
            timeIndices = standardizedTime >= startTime & standardizedTime <= endTime;
            predictedRates = predict(mdl, standardizedTime(timeIndices)');
            % Clip negative values
            predictedRates(predictedRates < 0) = 0;
            tempRow(timeIndices) = predictedRates;
            smoothedRatesMatrix(mu, :) = tempRow;
        end

        % Compute recruitment threshold
        recruitTime = min(activePeriods{mu}(:, 1)); % First activation time
        recruitIdx = round(recruitTime * fs_force);
        if recruitIdx > 0 && recruitIdx <= numel(forceData)
            recruitmentThresh(mu) = forceData(recruitIdx);
        end
        
        % Save best SVR params
        svr_params(mu, :) = [bestKernelScale, bestBoxConstraint];

    end

end
