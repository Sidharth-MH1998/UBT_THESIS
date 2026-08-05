function [timeVectors, instRates, smoothedRates] = smoothFirings_poly(spike_train, activePeriods, fs, polyOrder, epochDuration, windowSize, plotFlag)
    % Computes time vectors, moving window firing rates, and smoothed firing rates per MU.
    %
    % Parameters:
    %   spike_train: Sparse double matrix (Samples × nMUs) with spikes (1s indicate spikes).
    %   activePeriods: Cell array (1 × nMUs), each containing a matrix of active periods
    %                  [startTime, endTime] (in seconds).
    %   fs: Sampling rate of the spike train in Hz.
    %   polyOrder: Order of the polynomial for smoothing.
    %   epochDuration: Duration of the moving window epoch in seconds (e.g., 0.125s).
    %   windowSize: Number of epochs in the moving window (e.g., 8).
    %   plotFlag: If true, plots a tiled layout of firing rate time series per MU.
    %
    % Returns:
    %   timeVectors: Cell array (1 × nMUs), each containing spike time vectors (in seconds).
    %   instRates: Cell array (1 × nMUs), each containing moving window firing rates (Hz).
    %   smoothedRates: Cell array (1 × nMUs), each containing smoothed firing rates (Hz).

    [nSamples, nMUs] = size(spike_train);
    timeVectors = cell(1, nMUs);
    instRates = cell(1, nMUs);
    smoothedRates = cell(1, nMUs);

    % Moving window parameters
    windowLength = round(epochDuration * fs);
    numSamplesInWindow = windowSize * windowLength;
    
    % Create Gaussian window for smoothing
    sigma = numSamplesInWindow / 6; % Standard deviation (1/6 of window for ~99.7% coverage)
    gaussWindow = gausswin(numSamplesInWindow, 2.5);
    gaussWindow = gaussWindow / sum(gaussWindow); % Normalize to preserve amplitude

    % Process each MU
    for mu = 1:nMUs
        % Get spike indices and convert to time
        spikeIndices = find(spike_train(:, mu));
        spikeTimes = spikeIndices / fs; % Convert to seconds

        % Skip if no spikes
        if numel(spikeIndices) < 2
            timeVectors{mu} = [];
            instRates{mu} = [];
            smoothedRates{mu} = [];
            continue;
        end
        
        spike_train = full(spike_train); % 
        % Compute moving window firing rates using convolution
        rates = conv(double(spike_train(:, mu)), gaussWindow, 'same');
        rates = rates * fs; % Convert to Hz (compensate for sampling rate)

        % Create time vector for the moving window rates
        windowTime = (0:nSamples - 1) / fs; % Time vector corresponding to each sample

        % Save moving window firing rates
        timeVectors{mu} = windowTime; % Time vector in seconds
        instRates{mu} = [windowTime', rates]; % Store time and rate

        % Initialize cell arrays to store smoothed firing rates for each active period
        smoothTime = {};
        smoothFiringRates = {};

        % Get active periods for this MU
        muActivePeriods = activePeriods{mu};

        if ~isempty(muActivePeriods)
            % Smooth firing rates for each active period
            for p = 1:size(muActivePeriods, 1)
                % Extract active period bounds in time
                startTime = muActivePeriods(p, 1) - 0.05; % Extend start by 0.05s
                endTime = muActivePeriods(p, 2) + 0.05;   % Extend end by 0.05s

                % Find indices of firing rates within the active period
                activeIdx = (windowTime >= startTime) & (windowTime <= endTime);

                if any(activeIdx)
                    % Fit a polynomial to the rates within the active period
                    fitX = windowTime(activeIdx);
                    fitY = rates(activeIdx);

                    if numel(fitX) > polyOrder
                        pCoeffs = polyfit(fitX, fitY, polyOrder);

                        % Evaluate the polynomial
                        smoothX = fitX;
                        smoothY = polyval(pCoeffs, smoothX);

                        % Store results in cell arrays
                        smoothTime{end+1} = smoothX;
                        smoothFiringRates{end+1} = smoothY;
                    end
                end
            end
        end

        % Concatenate the results for all active periods
        smoothedRates{mu} = {smoothTime, smoothFiringRates};  % Cell arrays storing time and smoothed rates
    end

    % Plotting
    if plotFlag
        figure;
        tiledlayout('flow', 'TileSpacing', 'Compact');
        for mu = 1:nMUs
            nexttile;
            hold on;
            if ~isempty(instRates{mu})
                plot(instRates{mu}(:, 1), instRates{mu}(:, 2), 'b', 'DisplayName', 'Moving Window Rate');
            end
            if ~isempty(smoothedRates{mu})
                for idx = 1:length(smoothedRates{mu}{1})  % Iterate through active periods
                    plot(smoothedRates{mu}{1}{idx}, smoothedRates{mu}{2}{idx}, 'r', 'DisplayName', 'Smoothed Rate');
                end
            end
            hold off;
            xlabel('Time (s)');
            ylabel('Firing Rate (Hz)');
            title(sprintf('MU %d', mu));
            legend;
            grid on;
        end
        sgtitle('Firing Rate Time Series per MU');
    end
end