function [states, muMap] = prepare_online_grid_states(signal, parameters, cfg)
%PREPARE_ONLINE_GRID_STATES Build independent online decoders for decompose5 grids.
% cfg.calibChannels and cfg.emgChannels are paired channel lists. Every grid's
% full electrode set must be present; bad electrodes are excluded by its mask.
% muMap maps combined output columns to [grid, retained MU within grid].

assert(iscell(signal.EMGmask) && ~isempty(signal.EMGmask), ...
    'signal.EMGmask must contain one mask per grid.');
nGrids = numel(signal.EMGmask);
if isfield(signal, 'ngrid')
    assert(signal.ngrid == nGrids, 'signal.ngrid and EMGmask disagree.');
end
assert(iscell(signal.Pulsetrain) && numel(signal.Pulsetrain) == nGrids, ...
    'signal.Pulsetrain must contain one matrix per grid.');
assert(iscell(signal.Dischargetimes) && size(signal.Dischargetimes,1) == nGrids, ...
    'signal.Dischargetimes must be a grids-by-MUs cell array.');
channelCounts = cellfun(@numel, signal.EMGmask);
nChannels = size(signal.data,1);
nSamples = size(signal.data,2);
assert(sum(channelCounts) == nChannels && all(channelCounts > 0), ...
    'Grid masks must cover all calibration EMG rows.');
validateattributes(cfg.calibChannels, {'numeric'}, ...
    {'vector','integer','positive','finite','<=',nChannels});
validateattributes(cfg.emgChannels, {'numeric'}, ...
    {'vector','integer','positive','finite'});
assert(numel(cfg.calibChannels) == nChannels && ...
    isequal(sort(cfg.calibChannels(:).'), 1:nChannels), ...
    'cfg.calibChannels must list every calibration electrode exactly once.');
assert(numel(cfg.emgChannels) == nChannels && ...
    numel(unique(cfg.emgChannels)) == nChannels, ...
    'cfg.emgChannels must map every calibration electrode to a distinct stream row.');

states = cell(1,nGrids);
muMap = zeros(0,2);
muOffset = 0;
channelOffset = 0;
for gridIdx = 1:nGrids
    channels = channelOffset + (1:channelCounts(gridIdx));
    channelOffset = channelOffset + channelCounts(gridIdx);
    % decompose5 records explicit grid channel membership when available.
    if isfield(parameters, 'gridChannels')
        assert(iscell(parameters.gridChannels) && ...
            numel(parameters.gridChannels) == nGrids && ...
            isequal(parameters.gridChannels{gridIdx}(:).', channels), ...
            'Grid %d channel metadata disagrees with its EMG mask.', gridIdx);
    end
    mask = signal.EMGmask{gridIdx}(:);
    validateattributes(mask, {'numeric','logical'}, {'vector','binary'});
    mask = mask ~= 0;
    pulse = signal.Pulsetrain{gridIdx};
    assert(isnumeric(pulse) && ismatrix(pulse) && size(pulse,2) == nSamples, ...
        'Grid %d pulse trains must match the calibration sample count.', gridIdx);
    nMU = size(pulse,1);
    assert(size(signal.Dischargetimes,2) >= nMU, ...
        'Grid %d is missing discharge-time cells.', gridIdx);
    discharge = signal.Dischargetimes(gridIdx,1:nMU); % Ignore padded cells.
    for mu = 1:nMU
        validateattributes(discharge{mu}, {'numeric'}, ...
            {'vector','nonempty','integer','positive','finite','<=',nSamples});
        discharge{mu} = sort(unique(double(discharge{mu}(:).')));
    end
    [~, channelRows] = ismember(channels, cfg.calibChannels);
    state = struct();
    state.grid = gridIdx;
    state.calibChannels = channels;
    state.channelRows = channelRows;
    state.mask = mask;
    state.nMU = nMU;
    state.muIndices = muOffset + (1:nMU);
    state.originalIDs = 1:nMU;
    if isfield(signal, 'onlineMUOriginalIDs')
        state.originalIDs = signal.onlineMUOriginalIDs{gridIdx};
        assert(numel(state.originalIDs) == nMU, ...
            'Grid %d original MU IDs do not match retained MUs.', gridIdx);
    end
    state.extensionfactor = 0;
    state.MUfilt = zeros(nMU,0);
    state.normval = zeros(1,nMU);
    state.centroid = zeros(nMU,2);
    state.overlap = zeros(0,0);
    if nMU > 0
        nGood = sum(~mask);
        assert(nGood > 0 && nGood <= 1000, ...
            'Grid %d must have between 1 and 1000 good channels.', gridIdx);
        emg = double(signal.data(channels,:));
        filters = double(getMUfilters(emg, mask, discharge));
        extensionfactor = round(1000/nGood);
        assert(isequal(size(filters), [nGood*extensionfactor nMU]) && ...
            all(isfinite(filters(:))) && all(any(filters ~= 0,1)), ...
            'Grid %d produced invalid MU filters.', gridIdx);
        [state.extensionfactor, inverseCov, state.normval, state.centroid] = ...
            getonlineparameters(emg, mask, filters, signal.fsamp);
        assert(numel(state.normval) == nMU && ...
            isequal(size(state.centroid), [nMU 2]) && ...
            all(isfinite(state.normval(:))) && all(state.normval(:) > 0) && ...
            all(isfinite(state.centroid(:))) && ...
            all(state.centroid(:,2) > state.centroid(:,1)) && ...
            all(isfinite(inverseCov(:))), ...
            'Grid %d could not classify every MU using I-Spin calibration.', gridIdx);
        state.normval = reshape(state.normval,1,[]);
        state.MUfilt = filters' * inverseCov;
        state.overlap = zeros(nGood*extensionfactor, extensionfactor-1);
    end
    states{gridIdx} = state;
    muMap = [muMap; [repmat(gridIdx,nMU,1), (1:nMU)']]; %#ok<AGROW>
    muOffset = muOffset + nMU;
    fprintf('Grid %d: %d channels, %d good channels, %d MUs found.\n', ...
        gridIdx, numel(channels), sum(~mask), nMU);
end
assert(muOffset > 0, 'No motor units remain in any calibration grid.');
end
