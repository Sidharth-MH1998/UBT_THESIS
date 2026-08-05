function [MUactContained] = MUactiveStages(MUactivePeriods, stagesDurations, overlapThreshold)
    % Determine if the active period of a spike is contained within time segments.
    % Parameters:
    %    MUactivePeriods: Cell array of active periods (start and end times) for each motoneuron
    %    stagesDurations: Array of time durations representing time segments
    %    overlapThreshold: Minimum percentage of overlap for considering the active period within a time segment
    %
    % Returns:
    %    contained: Boolean array indicating if the active period of a spike is contained within time segments

    numMUs = length(MUactivePeriods);
    numSegments = length(stagesDurations);
    
    % Initialize contained array
    MUactContained = false(numMUs, numSegments);

    % Calculate the cumulative start and end times of the time segments
    segmentStarts = [0; cumsum(stagesDurations(1:end-1))];
    segmentEnds = cumsum(stagesDurations);
    
    % Loop through each motoneuron
    for mu = 1:numMUs
        % Get active periods for the current motoneuron
        periods = MUactivePeriods{mu};
        
        % Loop through each time segment
        for seg = 1:numSegments
            % Check if any active period is contained within the current time segment
            for i = 1:size(periods, 1)
                periodStart = periods(i, 1);
                periodEnd = periods(i, 2);
                
                segmentStart = segmentStarts(seg);
                segmentEnd = segmentEnds(seg);
                
                % Calculate the overlap
                overlapStart = max(periodStart, segmentStart);
                overlapEnd = min(periodEnd, segmentEnd);
                overlapDuration = max(0, overlapEnd - overlapStart);
                
                periodDuration = periodEnd - periodStart;
                overlapPercentage = overlapDuration / periodDuration;
                
                if overlapPercentage >= overlapThreshold
                    MUactContained(mu, seg) = true;
                    break;
                end
            end
        end
    end
end
