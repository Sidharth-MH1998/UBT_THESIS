function [recruitThresh, lateRecruited, earlyRecruited] = getRecruitThresh_v03(activePeriods,agonistMUs,gridNumber, force, fs_force)
    % Detect recruitment thresholds and label MUs as late/early recruited.
    %
    % Parameters:
    %   activePeriods: Struct containing sets of active periods and agonist MU labels.
    %   agonistMUs: 
    %   gridNumber: A number from 1 to 4
    %   force: The force signal array.
    %   fs_force: The sampling rate of the force signal in Hz.
    %
    % Returns:
    %   recruitmentThresholds: Array of recruitment thresholds (force level) for each MU.
    %   lateRecruited: Logical array indicating late recruitment (upper 30% of max force amplitude).
    %   earlyRecruited: Logical array indicating early recruitment (lower 30% of max force amplitude).

    numMUs = length(activePeriods); % Number of motoneurons (MUs)
    recruitThresh = NaN(numMUs, 1); % Initialize recruitment thresholds for this set
    lateRecruited = false(numMUs, 1); % Initialize late recruited logical array
    earlyRecruited = false(numMUs, 1); % Initialize early recruited logical array
    
    % Get the max force amplitude for threshold calculations
    if gridNumber == 1 || gridNumber == 2
        maxForceAmplitude = max(force); % Positive force max for sets 1 and 2
    else
        maxForceAmplitude = min(force); % Negative force max for sets 3 and 4
    end
    
    upperThreshold = 0.667 * abs(maxForceAmplitude); % Upper 33% of force amplitude
    lowerThreshold = 0.333 * abs(maxForceAmplitude); % Lower 33% of force amplitude
    
    for muIdx = 1:numMUs
        if agonistMUs(muIdx) == 1 % Only check for agonist MUs
            % Get the active periods for this motoneuron
            muActivePeriods = activePeriods{muIdx};
            
            if ~isempty(muActivePeriods)
                % Get the start time of the first active period (in seconds)
                firstActiveTime = muActivePeriods(1, 1);
                
                % Convert the active period start time to the corresponding force index
                forceIdx = round(firstActiveTime * fs_force) + 1;
                
                % Ensure the index is within the bounds of the force array
                if forceIdx > length(force)
                    forceIdx = length(force);
                end
                
                % Get the corresponding force level at the start of the first active period
                threshold = force(forceIdx);
                
                % Check if the threshold matches the correct sign
                if (gridNumber == 1 || gridNumber == 2) && threshold < 0
                    threshold = 0; % Replace with 0 if negative for sets 1 and 2
                elseif (gridNumber == 3 || gridNumber == 4) && threshold > 0
                    threshold = 0; % Replace with 0 if positive for sets 3 and 4
                end
                
                % Store the corrected recruitment threshold
                recruitThresh(muIdx) = threshold;
                
                % Label as late recruited if in upper 30% of max force amplitude
                if abs(threshold) >= upperThreshold
                    lateRecruited(muIdx) = true;
                end
                
                % Label as early recruited if in lower 30% of max force amplitude
                if abs(threshold) <= lowerThreshold && threshold ~= 0
                    earlyRecruited(muIdx) = true;
                end
            else
                % If no active period was found, leave NaN (no recruitment threshold)
                recruitThresh(muIdx) = NaN;
            end
        else
            % Non-agonist MUs should be NaN
            recruitThresh(muIdx) = NaN;
        end
    end
end