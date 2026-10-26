function signal = buildMUeditSignal(recordedEMG, fsEMG, recordedForce,forceChannel, forceTarget, activeInputs, gridName, muscleName, fsForce)
% Build the MAT-file structure expected by MUedit.
    nSamples = size(recordedEMG, 2);
    nGrids = numel(activeInputs);

    signal = struct();
    signal.data = recordedEMG;
    signal.fsamp = fsEMG;
    signal.nChan = size(recordedEMG, 1);
    signal.ngrid = nGrids;
    signal.gridname = normalizeGridNames(gridName, nGrids, 'gridName');
    signal.muscle = normalizeGridNames(muscleName, nGrids, 'muscleName');
    signal.target = repmat(forceTarget, 1, nSamples);
    % Keep all three force channels at their original force sampling rate.
    % signal.path below remains the selected channel resampled to EMG length.
    signal.recordedForce = recordedForce;
    signal.fs_force = fsForce;

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

function names = normalizeGridNames(value, nGrids, fieldName)
% Save a flat row cell array with one character vector per active input.
    if ischar(value) && isrow(value)
        names = {value};
    elseif isstring(value) && isvector(value) && ~any(ismissing(value))
        names = cellstr(value);
    elseif iscell(value) && isvector(value)
        names = value;
        for idx = 1:numel(names)
            name = names{idx};
            if isstring(name) && isscalar(name) && ~ismissing(name)
                names{idx} = char(name);
            elseif ~(ischar(name) && isrow(name))
                error('buildMUeditSignal:InvalidNames', ...
                    '%s must contain text names, not nested cells.', fieldName);
            end
        end
    else
        error('buildMUeditSignal:InvalidNames', ...
            '%s must be text or a vector of text names.', fieldName);
    end

    names = reshape(names, 1, []);
    if numel(names) == 1
        names = repmat(names, 1, nGrids);
    elseif numel(names) ~= nGrids
        error('buildMUeditSignal:NameCountMismatch', ...
            '%s must have one name or %d names (one per active input).', ...
            fieldName, nGrids);
    end
end
