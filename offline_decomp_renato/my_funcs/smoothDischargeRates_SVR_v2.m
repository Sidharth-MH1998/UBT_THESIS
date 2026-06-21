function smoothedRates = smoothDischargeRates_SVR_v2(spike_train, activePeriods, fs, plotFlag)
    % SMOOTHDISCHARGERATES_SVR Smooth discharge rates using SVR with grid search.
    %
    % Parameters:
    %   spike_train: Sparse double matrix (nSamples x nMUs) containing spike trains.
    %   activePeriods: Cell array (1 x nMUs), each containing a matrix of active periods
    %                  [startTime, endTime] (in seconds).
    %   fs: Sampling frequency in Hz.
    %   plotFlag: Boolean flag to plot smoothed rates (1 for true, 0 for false).
    %
    % Returns:
    %   smoothedRates: Cell array (1 x nMUs), each containing a matrix [time, smoothedRate].

    [nSamples, nMUs] = size(spike_train);
    smoothedRates = cell(1, nMUs); % Initialize output

    % Define grid search ranges for KernelScale and BoxConstraint
    kernelScaleRange = 0.5:0.5:5; % Fine grid for KernelScale
    boxConstraintRange = 50:50:500; % Fine grid for BoxConstraint

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

        % Use the best parameters for active periods
        smoothTime = [];
        smoothRates = [];

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

            % Train SVR model with optimal parameters
            mdl = fitrsvm(instTimes, instRates, ...
                'KernelFunction', 'rbf', ...
                'KernelScale', bestKernelScale, ...
                'BoxConstraint', bestBoxConstraint);

            % Predict smooth rates over a dense time vector
            predictionTime = linspace(startTime, endTime, round((endTime - startTime) * fs))'; % Dense vector
            predictedRates = predict(mdl, predictionTime);

            % Clip negative values
            predictedRates(predictedRates < 0) = 0;

            % Store smoothed rates for the current active period
            smoothTime = [smoothTime; predictionTime]; %#ok<AGROW>
            smoothRates = [smoothRates; predictedRates]; %#ok<AGROW>
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