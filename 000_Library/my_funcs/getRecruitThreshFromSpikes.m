function recruitmentThresholds = getRecruitThreshFromSpikes(decomp_results, force, fs_force, fs_emg)
    % Detect the recruitment threshold for each motoneuron (MU) in the spike trains.
    %
    % Parameters:
    %   decomp_results: Struct containing sets of spike trains and agonist MU labels.
    %   force: The force signal array.
    %   fs_force: The sampling rate of the force signal in Hz.
    %   fs_emg: The sampling rate of the spike trains in Hz.
    %
    % Returns:
    %   recruitmentThresholds: Array of recruitment thresholds (force level) for each MU.
    
    numSets = length(decomp_results); % Number of sets of decomp results
    recruitmentThresholds = cell(numSets, 1); % Initialize a cell array to hold recruitment thresholds
    
    for setIdx = 1:numSets
        % Get the spike train data and agonistMUs from this set
        spikeTrains = decomp_results(setIdx).results.spike_train;
        agonistMUs = decomp_results(setIdx).results.agonistMUs; % Logical array for agonist MUs
        
        numMUs = size(spikeTrains, 2); % Number of motoneurons (MUs)
        recruitmentThresholds{setIdx} = NaN(numMUs, 1); % Initialize recruitment thresholds for this set
        
        for muIdx = 1:numMUs
            if agonistMUs(muIdx) % Only check for agonist MUs
                % Get the spike train for this motoneuron
                spikeTrain = spikeTrains(:, muIdx);
                
                % Find the first occurrence of a spike (i.e., the first non-zero element)
                firstSpikeIdx = find(spikeTrain, 1, 'first');
                
                if ~isempty(firstSpikeIdx)
                    % Convert the spike train index to time
                    timeOfFirstSpike = (firstSpikeIdx - 1) / fs_emg;
                    
                    % Convert the spike train time to the corresponding force index
                    forceIdx = round(timeOfFirstSpike * fs_force) + 1;
                    
                    % Ensure the index is within the bounds of the force array
                    if forceIdx > length(force)
                        forceIdx = length(force);
                    end
                    
                    % Get the corresponding force level at that time
                    recruitmentThresholds{setIdx}(muIdx) = force(forceIdx);
                else
                    % If no spike was found, leave NaN (no recruitment threshold)
                    recruitmentThresholds{setIdx}(muIdx) = NaN;
                end
            else
                % Non-agonist MUs should be NaN
                recruitmentThresholds{setIdx}(muIdx) = NaN;
            end
        end
    end
end