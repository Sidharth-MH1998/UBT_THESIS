function [activePeriods] = find_MU_active_periods(spikeTrains, thresholdHz, samplingRate, restThreshold, plotOption)
    % Find active periods in motoneuron spike trains.
    % Parameters:
    %    spikeTrains: Sparse matrix of spike trains (samples x MUs)
    %    thresholdHz: Threshold for the discharge rate in Hz
    %    samplingRate: Sampling rate of the spike trains in Hz
    %    plotOption: Boolean to indicate if the spike trains and active periods should be plotted
    %
    % Returns:
    %    activePeriods: Cell array of active periods (start and end times) for each motoneuron

    % Convert threshold to spikes per sample
    thresholdSamples = thresholdHz / samplingRate;
    
    % Sort spike trains
    [~,order] = sort(sum(spikeTrains,1),'descend');
    spikeTrains = spikeTrains(:,order);

    numSamples = size(spikeTrains, 1);
    numMUs = size(spikeTrains, 2);
    
    % Initialize cell array to hold active periods for each motoneuron
    activePeriods = cell(numMUs, 1);

    % Loop through each motoneuron
    for mu = 1:numMUs
        % Get the spike train for the current motoneuron
        spikeTrain = spikeTrains(:, mu);
        
        % Find the indices of the spikes
        spikeIndices = find(spikeTrain);
        
        % Find the inter-spike intervals
        if ~isempty(spikeIndices)
            isi = diff(spikeIndices) / samplingRate; % Inter-spike intervals in seconds
            
            % Find periods where the ISI is less than the threshold period
            active = isi < (1 / thresholdHz);
            
            % Initialize start and end times
            starts = [];
            ends = [];
            
            % Identify start and end indices of active periods
            if ~isempty(active)
                startIdx = spikeIndices(1);
                for i = 1:length(active)
                    if active(i)
                        if isempty(starts) || spikeIndices(i) > ends(end)
                            starts = [starts; startIdx];
                            ends = [ends; spikeIndices(i+1)];
                        else
                            ends(end) = spikeIndices(i+1);
                        end
                    else
                        startIdx = spikeIndices(i+1);
                    end
                end
            end
            
            % Convert indices to times
            starts = (starts - 1) / samplingRate;
            ends = (ends - 1) / samplingRate;

            % Merge active periods separated by a small time lower than the threshold
            if ~isempty(starts)
                mergedStarts = starts(1);
                mergedEnds = ends(1);
                for i = 2:length(starts)
                    if starts(i) - mergedEnds(end) <= restThreshold
                        % Merge active periods
                        mergedEnds(end) = ends(i);
                    else
                        % Start a new merged active period
                        mergedStarts = [mergedStarts; starts(i)];
                        mergedEnds = [mergedEnds; ends(i)];
                    end
                end
                % Store merged active periods for the current motoneuron
                activePeriods{mu} = [mergedStarts, mergedEnds];
            end
            
%             % Store active periods for the current motoneuron
%             activePeriods{mu} = [starts, ends];
        end
    end
    
    % Plot if plotOption is true
    if plotOption
        figure;
        hold on;
        for mu = 1:numMUs
            spikeIndices = find(spikeTrains(:, mu));
            spikeTimes = (spikeIndices - 1) / samplingRate;
            y = mu * ones(size(spikeTimes));
            plot(spikeTimes, y, 'k.', 'MarkerSize', 10);
            
            % Plot active periods
            for k = 1:size(activePeriods{mu}, 1)
                start = activePeriods{mu}(k, 1);
                endT = activePeriods{mu}(k, 2);
                plot([start start], [mu-0.4 mu+0.4], 'r-', 'LineWidth', 2);
                plot([endT endT], [mu-0.4 mu+0.4], 'g-', 'LineWidth', 2);
            end
        end
        xlabel('Time (s)');
        ylabel('Motoneuron');
        title('Motoneuron Spike Trains and Active Periods');
        hold off;
    end
end

% % Example usage
% % Generate synthetic data for demonstration
% numSamples = 51200; % 25 seconds at 2048 Hz
% numMUs = 13;
% spikeTrains = sparse(numSamples, numMUs);
% 
% % Randomly generate some spikes
% for mu = 1:numMUs
%     spikeTimes = randperm(numSamples, 100);
%     spikeTrains(spikeTimes, mu) = 1;
% end
% 
% % Set threshold and sampling rate
% thresholdHz = 5; % Discharge rate threshold in Hz
% samplingRate = 2048; % Sampling rate in Hz
% plotOption = true; % Plot the results
% 
% % Find active periods
% activePeriods = find_active_periods(spikeTrains, thresholdHz, samplingRate, plotOption);
