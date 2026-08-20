function signal = buildMUeditSignal(recordedEMG, fsEMG, recordedForce,forceChannel, forceTarget, activeInputs, gridName, muscleName)
% Build the MAT-file structure expected by MUedit.
    nSamples = size(recordedEMG, 2);
    nGrids = numel(activeInputs);

    signal = struct();
    signal.data = recordedEMG;
    signal.fsamp = fsEMG;
    signal.nChan = size(recordedEMG, 1);
    signal.ngrid = nGrids;
    signal.gridname = repmat({gridName}, 1, nGrids);
    signal.muscle = repmat({muscleName}, 1, nGrids);
    signal.target = repmat(forceTarget, 1, nSamples);
    % Keep all three force channels at their original force sampling rate.
    % signal.path below remains the selected channel resampled to EMG length.
    signal.recordedForce = recordedForce;

    forceChannel = min(max(round(forceChannel), 1), size(recordedForce, 2));
    if isempty(recordedForce) || nSamples == 0
        signal.path = zeros(1, nSamples);
    elseif size(recordedForce, 1) == 1
        signal.path = repmat(recordedForce(1, forceChannel), 1, nSamples);
    else
        sourcePosition = linspace(0, 1, size(recordedForce, 1));
        emgPosition = linspace(0, 1, nSamples);
        signal.path = interp1(sourcePosition, ...
            recordedForce(:, forceChannel).', emgPosition, 'linear');
    end
end
