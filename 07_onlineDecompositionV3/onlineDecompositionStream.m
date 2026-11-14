function out = onlineDecompositionStream(signal,parameters,cfg,sharedUI)
%onlineDecompositionStream Online decomposition pipeline.
%
% INPUTS
%   signal      : MUedit signal structure containing calibration EMG,
%                 final pulse trains, discharge times, and EMG mask.
%   parameters  : MUedit decomposition-parameter structure.
%   cfg         : complete Novecento, streaming, and display configuration.
%
% OUTPUT
%   out         : online EMG, pulse trains, discharge times, firing rates,
%                 session timing, and Novecento configuration.
%
% Filters are rebuilt independently for every grid from calibration EMG and
% discharge times. Each grid has its own mask, classifier and overlap buffer.
% Combined outputs use grid order; out.online.gridResults stores each grid.

%% Read and validate the MUedit structures
if nargin < 3 || ~isstruct(cfg) || isempty(cfg)
    error('A complete cfg structure must be supplied.');
end

validate_signal_inputs(signal,parameters,cfg);

fs = signal.fsamp;
[gridStates, muMap] = prepare_online_grid_states(signal, parameters, cfg);
nGrids = numel(gridStates);
nMU = size(muMap, 1);
cfg.muLabels = arrayfun(@(mu) sprintf('G%d MU%d', ...
    muMap(mu,1), muMap(mu,2)), 1:nMU, 'UniformOutput', false);
fprintf('Prepared %d grids with %d motor units in total.\n', nGrids, nMU);

%% Novecento connection and online stream geometry
dev = novecento_connect(cfg);
% Ensure hardware is stopped/disconnected on any exit path.
cleanupObj = onCleanup(@() novecento_disconnect(dev));

activeInputs = cfg.activeInputs(:)';
fsVals = dev.fsInput(activeInputs);
if any(fsVals <= 0)
    error('No sampling rate detected for one or more active inputs.');
end

if numel(unique(fsVals)) ~= 1
    error('All active inputs must use the same sampling frequency.');
end

fs_online = fsVals(1);
if fs_online <= 0
    error('No sampling rate detected for active inputs.');
end

if fs_online ~= fs
    error('Calibration fs (%d Hz) must match online fs (%d Hz).', fs, fs_online);
end

totalOnlineChan = sum(dev.NumChan(activeInputs));
if max(cfg.emgChannels) > totalOnlineChan
    error('cfg.emgChannels exceeds total active-input channel count (%d).', totalOnlineChan);
end

nsamp = fs_online * cfg.windowBaseCols / 500;   %0.128 second data (256 samples)
if mod(nsamp, 1) ~= 0
    error('cfg.windowBaseCols must map to an integer sample count.');
end
nsamp = round(nsamp);
windowSec = nsamp / fs_online;

for gridIdx = 1:nGrids
    state = gridStates{gridIdx};
    if state.nMU > 0 && nsamp < state.extensionfactor - 1
        error('Processing window is too short for grid %d extension.', gridIdx);
    end
end

%% Figure/state initialization and online accumulators
[fig, plotState] = online_live_display('init', nMU, cfg, sharedUI);
if isfield(cfg,'showQuadrant') && cfg.showQuadrant
    quadrantState = ispin_quadrant_feedback('init',nMU,fs_online,windowSec,cfg);
else
    quadrantState = struct('enabled',false);
end

Distime_chunks = {};
Pulsetrain_chunks = {};
EMG_chunks = {};
Dischargetimes_online = cell(1, nMU);
fr_online = cell(1, nMU);
for mu = 1:nMU
    Dischargetimes_online{mu} = zeros(0,1);
    fr_online{mu} = zeros(0,1);
end

sessionStart = tic;
sampleCursor = 0;
windowCount = 0;

try
    flush(dev.tcpSocket);
catch
end
pause(0.2);

fprintf('\n=== Streaming from Novecento+ ===\n');
fprintf('Inputs: %s | fs: %d Hz | window: %d samples (%.3f s)\n', ...
    mat2str(activeInputs), fs_online, nsamp, windowSec);
fprintf('Close the figure window to stop the session.\n\n');

%% Real-time processing loop
while ishandle(fig)
    if ~ishandle(sharedUI.fig)
        break;
    end

    % Explicitly service the Arduino here. Novecento TCP reads are
    % blocking, so relying only on a MATLAB timer can starve force reads.
    sharedUI.pollForce([],[]);

    if getappdata(sharedUI.fig,'forceStopRequested')
        break;
    end
    if getappdata(fig, 'stopRequested')
        break;
    end

    elapsedSec = toc(sessionStart);
    if isfinite(cfg.onlineDurationSec) && elapsedSec >= cfg.onlineDurationSec
        break;
    end

    % Read one multi-input hardware window, then keep only requested EMG channels.
    blockAll = novecento_read_emg_block(dev, activeInputs, nsamp);
    emgBlock = blockAll(cfg.emgChannels, :);
    % Decode each grid separately, retaining independent overlap buffers.
    [pulseChunk, distChunk, gridStates] = ...
        decode_online_grid_window(emgBlock, gridStates, fs_online);

    windowCount = windowCount + 1;
    idxGlobal = sampleCursor + (1:nsamp);

    % Persist window outputs for post-session concatenation.
    Pulsetrain_chunks{windowCount} = pulseChunk; %#ok<AGROW>
    Distime_chunks{windowCount} = logical(distChunk); %#ok<AGROW>
    if cfg.recordEMG
        EMG_chunks{windowCount} = emgBlock; %#ok<AGROW>
    end

    for mu = 1:nMU
        % Convert per-window spike indices to global sample indices.
        new_spikes = find(distChunk(:,mu)) + sampleCursor;
        if ~isempty(new_spikes)
            Dischargetimes_online{mu} = [Dischargetimes_online{mu}; new_spikes(:)];
        end

        % Instantaneous firing rate from inter-discharge intervals.
        if numel(Dischargetimes_online{mu}) > 1
            fr_online{mu} = fs_online ./ diff(Dischargetimes_online{mu});
        else
            fr_online{mu} = zeros(0,1);
        end
    end

    sampleCursor = idxGlobal(end);
    currentTime = sampleCursor / fs_online;

    online_live_display('update', fig, plotState, Dischargetimes_online, fr_online, currentTime, cfg, fs_online);
    quadrantState = ispin_quadrant_feedback('update',quadrantState,distChunk,currentTime);

    if cfg.printEveryNWindows > 0 && mod(windowCount, cfg.printEveryNWindows) == 0
        spikesThisWin = sum(distChunk, 1);
        fprintf('Window %4d | t = %7.2f s | spikes = %s\n', ...
            windowCount, currentTime, mat2str(spikesThisWin));
    end
end

%% Concatenate buffers and build output struct
elapsed = toc(sessionStart);

Pulsetrain_online = concat_chunks(Pulsetrain_chunks, nMU);
Distime = concat_chunks(Distime_chunks, nMU);
if cfg.recordEMG
    EMG_online = concat_chunks(EMG_chunks, numel(cfg.emgChannels));
else
    EMG_online = [];
end

mean_fr_online = nan(nMU, 1);
for mu = 1:nMU
    if ~isempty(fr_online{mu})
        mean_fr_online(mu) = mean(fr_online{mu});
    end
end

out = struct();
out.cfg = cfg;
out.fs = fs_online;
out.nsamp = nsamp;
out.windowSec = windowSec;
out.nWin = windowCount;
out.elapsedSec = elapsed;

out.online = struct();
out.online.EMG = EMG_online;
out.online.Pulsetrain = Pulsetrain_online;
out.online.Distime = Distime;
out.online.Dischargetimes = Dischargetimes_online;
out.online.fr = fr_online;
out.online.mean_fr = mean_fr_online;
out.online.ngrid = nGrids;
out.online.muMap = muMap; % Columns: grid number, retained MU number in grid
out.online.muLabels = cfg.muLabels;
out.online.PulsetrainByGrid = cell(1, nGrids);
out.online.DischargetimesByGrid = cell(nGrids, max(cellfun(@(s) s.nMU, gridStates)));
out.online.gridResults = cell(1, nGrids);
for gridIdx = 1:nGrids
    state = gridStates{gridIdx};
    indices = state.muIndices;
    result = struct();
    result.grid = gridIdx;
    result.fsamp = fs_online;
    result.time = (0:sampleCursor-1) / fs_online;
    result.calibChannels = state.calibChannels;
    result.emgChannels = cfg.emgChannels(state.channelRows);
    result.EMGmask = state.mask;
    result.MUOriginalIDs = state.originalIDs;
    result.globalMUIndices = indices;
    result.MUfilt = state.MUfilt;
    result.extensionfactor = state.extensionfactor;
    result.normval = state.normval;
    result.centroid = state.centroid;
    result.EMG = [];
    if windowCount == 0
        result.Pulsetrain = zeros(state.nMU, 0);
        result.Distime = false(0, state.nMU);
        if cfg.recordEMG
            result.EMG = zeros(numel(state.channelRows), 0);
        end
    else
        result.Pulsetrain = Pulsetrain_online(indices,:);
        result.Distime = Distime(:,indices);
        if cfg.recordEMG
            result.EMG = EMG_online(state.channelRows,:);
        end
    end
    result.Dischargetimes = Dischargetimes_online(indices);
    result.fr = fr_online(indices);
    result.mean_fr = mean_fr_online(indices);
    out.online.gridResults{gridIdx} = result;
    out.online.PulsetrainByGrid{gridIdx} = result.Pulsetrain;
    out.online.DischargetimesByGrid(gridIdx,1:state.nMU) = result.Dischargetimes;
end
out.online.quadrant = ispin_quadrant_feedback('export',quadrantState);
if isempty(Pulsetrain_online)
    out.online.Time = zeros(1,0);
else
    out.online.Time = (0:size(Pulsetrain_online,2)-1) / fs_online;
end

out.novecento = rmfield(dev, 'tcpSocket');

fprintf('\n=== Session finished ===\n');
fprintf('Elapsed time: %.2f s\n', elapsed);
fprintf('Windows processed: %d\n', windowCount);
fprintf('Samples decoded: %d\n', sampleCursor);

end

%% Input validation helpers
function validate_signal_inputs(signal,parameters,cfg)
if nargin < 3
    error('signal, parameters, and cfg are required.');
end
if ~isstruct(signal) || isempty(signal)
    error('signal must be a non-empty structure.');
end
if ~isstruct(parameters) || isempty(parameters)
    error('parameters must be a non-empty structure.');
end

required = {'data','fsamp','Pulsetrain','Dischargetimes','EMGmask'};
for fieldIdx = 1:numel(required)
    if ~isfield(signal,required{fieldIdx})
        error('signal.%s is missing.',required{fieldIdx});
    end
end
if ~isnumeric(signal.data) || ~ismatrix(signal.data) || isempty(signal.data)
    error('signal.data must be a non-empty channels-by-samples matrix.');
end
if ~isscalar(signal.fsamp) || ~isfinite(signal.fsamp) || signal.fsamp <= 0
    error('signal.fsamp must be a positive scalar.');
end
requiredCfg = {'activeInputs', ...
    'calibChannels','emgChannels','onlineDurationSec', ...
    'visibleWindowSec','windowBaseCols','recordEMG', ...
    'printEveryNWindows','showLegend','frYLim', ...
    'socketTimeoutSec','hardwareQueryRetries', ...
    'hardwareQueryPauseSec','forceInputChannelCounts','GainFactor', ...
    'FSelAux','AnOutINSource','AnOutChan','AnOutGain','IN_Active', ...
    'Mode','Gain','HRES','HPF','FsampCode'};
for fieldIdx = 1:numel(requiredCfg)
    if ~isfield(cfg,requiredCfg{fieldIdx})
        error('cfg.%s is missing.',requiredCfg{fieldIdx});
    end
end
validateattributes(cfg.activeInputs, {'numeric'}, ...
    {'vector','nonempty','integer','>=',1,'<=',10});
assert(numel(unique(cfg.activeInputs)) == numel(cfg.activeInputs), ...
    'cfg.activeInputs must not contain duplicate inputs.');
validateattributes(cfg.windowBaseCols, {'numeric'}, ...
    {'scalar','integer','positive','finite'});
end

%% Utility helpers
function out = concat_chunks(chunks,~)
if isempty(chunks)
    out = [];
    return;
end

if islogical(chunks{1})
    % Distime is stored as window-by-window logical rows.
    out = vertcat(chunks{:});
else
    % Pulse train / EMG are stored as channels-by-time blocks.
    out = horzcat(chunks{:});
end
end

