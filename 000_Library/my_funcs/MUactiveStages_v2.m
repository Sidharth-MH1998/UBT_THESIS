function [MUactContained] = MUactiveStages_v2(MUactivePeriods, stagesDurations, overlapThreshold)
    % Determine if the active period of a spike is contained within time segments.
    % Parameters:
    %    MUactivePeriods: Cell array of active periods (start and end times) for each motoneuron
    %    stagesDurations: Array of time durations representing time segments
    %    overlapThreshold: Minimum percentage of overlap for considering the active period within a time segment
    %
    % Returns:
    %    MUactContained: Boolean array indicating if the active period of a spike is contained within time segments

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
            % Loop through each active period
            for i = 1:size(periods, 1)
                periodStart = periods(i, 1);
                periodEnd = periods(i, 2);
                
                segmentStart = segmentStarts(seg);
                segmentEnd = segmentEnds(seg);
                
                % Calculate the overlap between the active period and the time segment
                overlapStart = max(periodStart, segmentStart);
                overlapEnd = min(periodEnd, segmentEnd);
                overlapDuration = max(0, overlapEnd - overlapStart);
                
                periodDuration = periodEnd - periodStart;
                overlapPercentage = overlapDuration / periodDuration;
                
                segmentDuration = segmentEnd - segmentStart;
                segmentOverlapPercentage = overlapDuration / segmentDuration;

                % Check if the overlap meets the threshold or if the active period spans the majority of the segment
                if overlapPercentage >= overlapThreshold || segmentOverlapPercentage >= overlapThreshold
                    MUactContained(mu, seg) = true;
                    break;
                end
            end
        end
    end
end
