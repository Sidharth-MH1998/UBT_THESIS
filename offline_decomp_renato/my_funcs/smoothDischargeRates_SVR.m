function smoothedRates = smoothDischargeRates_SVR(spike_train, activePeriods, fs, plotFlag)
    % SMOOTHDISCHARGERATES_SVR Smooth discharge rates using SVR and active periods.
    %
    % Parameters:
    %   spike_train: Sparse double matrix (nSamples x nMUs) containing spike trains.
    %   activePeriods: Cell array (1 x nMUs), each containing a matrix of active periods
    %                  [startTime, endTime] (in seconds).
    %   fs: Sampling frequency in Hz.
    %   polyOrder: Regularization parameter for SVR smoothing.
    %   plotFlag: Boolean flag to plot smoothed rates (1 for true, 0 for false).
    %
    % Returns:
    %   smoothedRates: Cell array (1 x nMUs), each containing a matrix [time, smoothedRate].
    
    [nSamples, nMUs] = size(spike_train);
    smoothedRates = cell(1, nMUs); % Initialize output

    % Process each MU
    for mu = 1:nMUs
        % Skip if no active periods or spikes
        if isempty(activePeriods{mu})
            smoothedRates{mu} = [];
            continue;
        end

        % Get spike times for this MU
        spikeIndices = find(spike_train(:, mu));
        spikeTimes = spikeIndices / fs; % Convert indices to time (seconds)

        if isempty(spikeIndices)
            smoothedRates{mu} = [];
            continue;
        end

        % Initialize smoothed results
        smoothTime = [];
        smoothRates = [];

        % Process each active period
        for ap = 1:size(activePeriods{mu}, 1)
            % Extract start and end times of the active period
            startTime = activePeriods{mu}(ap, 1) - 0.05; % Extend start by 0.05s
            endTime = activePeriods{mu}(ap, 2) + 0.05;   % Extend end by 0.05s

            % Get spikes within the active period
            activeIdx = spikeTimes >= startTime & spikeTimes <= endTime;
            activeSpikeTimes = spikeTimes(activeIdx);

            % Skip if fewer than 2 spikes in the active period
            if numel(activeSpikeTimes) < 2
                continue;
            end

            % Compute instantaneous firing rates (ISI-based)
            isi = diff(activeSpikeTimes); % Interspike intervals (seconds)
            instRates = 1 ./ isi; % Hz
            instTimes = activeSpikeTimes(2:end); % Time points for instantaneous rates

            % Compute epsilon for SVR
            iqrRates = iqr(instRates); % Interquartile range
            epsilon = max(iqrRates / 11, 1e-6); % Ensure epsilon is positive

            % Weight the first and last five instances higher
            nWeights = numel(instRates);
            weights = ones(nWeights, 1);
            weights(1:min(5, nWeights)) = 5; % First 5 rates
            weights(max(1, nWeights - 4):nWeights) = 5; % Last 5 rates

            % Train SVR model
            mdl = fitrsvm(instTimes, instRates, ...
                'KernelFunction', 'rbf', ...
                'KernelScale', 1.6, ... % Use suggested value
                'BoxConstraint', 370, ... % Use suggested value
                'Epsilon', epsilon, ...
                'Weights', weights);

            % Predict smooth rates over a dense time vector
            predictionTime = linspace(startTime, endTime, round((endTime - startTime) * fs))'; % Dense vector
            predictedRates = predict(mdl, predictionTime);

            % Clip negative values
            predictedRates(predictedRates < 0) = 0;

            % Store smoothed rates for the current active period
            smoothTime = [smoothTime; predictionTime]; 
            smoothRates = [smoothRates; predictedRates];
        end

        % Save results for the current MU
        smoothedRates{mu} = [smoothTime, smoothRates];
    end

    % Plotting
    if plotFlag
        figure;
        hold on;
        cmap = lines(nMUs); % Use distinct colors for each MU
        for mu = 1:nMUs
            if ~isempty(smoothedRates{mu})
                plot(smoothedRates{mu}(:, 1), smoothedRates{mu}(:, 2), 'Color', cmap(mu, :), 'LineWidth', 1.5, ...
                    'DisplayName', sprintf('MU %d', mu));
            end
        end
        xlim([0, 78]);
        xlabel('Time (s)');
        ylabel('Smoothed Discharge Rate (Hz)');
        title('Smoothed Discharge Rates for All MUs');
        legend('show');
        grid on;
        hold off;
    end
end
