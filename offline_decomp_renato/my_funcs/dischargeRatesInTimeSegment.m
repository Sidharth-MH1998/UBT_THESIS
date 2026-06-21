function [dischargeRates, segmentedSpikeTrains] = dischargeRatesInTimeSegment(spikeTrains, samplingRate, startTime, endTime)
    % Compute discharge rates and return segmented spike train for motoneuron spike trains.
    % Parameters:
    %    spikeTrains: Sparse matrix of spike trains (samples x MUs)
    %    samplingRate: Sampling rate of the spike trains in Hz
    %    startTime: Start time in seconds for the period of interest
    %    endTime: End time in seconds for the period of interest
    %
    % Returns:
    %    dischargeRates: Vector of discharge rates for each motoneuron (Hz)
    %    segmentedSpikeTrains: Segment of the spike trains between startTime and endTime

    % Convert start and end times to sample indices
    startIndex = round(startTime * samplingRate) + 1;
    endIndex = round(endTime * samplingRate);

    % Ensure indices are within valid range
    numSamples = size(spikeTrains, 1);
    if startIndex < 1 || endIndex > numSamples || startIndex >= endIndex
        error('Invalid start or end time.');
    end

    % Initialize discharge rates
    numMUs = size(spikeTrains, 2);
    dischargeRates = zeros(1, numMUs);

    % Extract the relevant segment of the spike trains
    segmentedSpikeTrains = spikeTrains(startIndex:endIndex, :);

    % Compute discharge rates for each motoneuron
    for mu = 1:numMUs
        % Get the spike train segment for the current motoneuron
        spikeSegment = segmentedSpikeTrains(:, mu);
        
        % Count the number of spikes in the segment
        numSpikes = nnz(spikeSegment);
        
        % Calculate the duration of the segment in seconds
        duration = (endIndex - startIndex + 1) / samplingRate;
        
        % Calculate the discharge rate (Hz)
        dischargeRates(mu) = numSpikes / duration;
    end

    % Output the discharge rates and segmented spike trains
    fprintf('Discharge Rates (Hz):\n');
    disp(dischargeRates);
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
% % Set parameters
% samplingRate = 2048; % Sampling rate in Hz
% startTime = 5; % Start time in seconds
% endTime = 10; % End time in seconds
% 
% % Compute discharge rates and segmented spike trains
% [dischargeRates, segmentedSpikeTrains] = compute_discharge_rates(spikeTrains, samplingRate, startTime, endTime);
