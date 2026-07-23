function session = novecento_emg_live_session(cfg)
%NOVECENTO_EMG_LIVE_SESSION Stream, record, and preview Novecento+ EMG.
%
% This file is intentionally self-contained. Keep user-editable settings in
% run_novecento_plot.m; keep CRC math in CRC8.m; keep the device/session
% mechanics here.
%
% Outputs are also written to the MATLAB base workspace:
%   recordedEMG
%   recordedDurationSec
%   recordStartSample
%   recordEndSample
%   trimmedEMG

if nargin < 1 || ~isstruct(cfg)
    error('novecento_emg_live_session requires a complete cfg structure.');
end
validate_config_fields(cfg);

%% Connect and prepare the session
% onCleanup guarantees that streaming is stopped even if the user closes the
% figure or MATLAB hits an error while reading.
dev = novecento_connect(cfg);
cleanupObj = onCleanup(@() novecento_disconnect(dev));

[fs, samplesPerBlock] = validate_stream_settings(dev, cfg);
[fig, ui] = build_plot_window();
app = create_app_state(cfg, fs);

% Store app state both in the figure and in the base workspace. Figure app
% data drives the live UI; base variables make the recording easy to inspect
% after the session.
assign_session_to_base(app);
setappdata(fig, 'novecentoApp', app);
set(fig, 'WindowKeyPressFcn', @(src, event) handle_marker_keypress(src, event));

fprintf('\n=== Novecento live plot ===\n');
fprintf('Connected to %s. Close the figure to stop safely.\n', dev.ip);
fprintf('Press r to mark start, q to mark stop and create trimmedEMG.\n\n');

%% Main streaming loop
% Each loop reads one block from the device, appends it to recordedEMG, then
% refreshes only the selected preview channels.
while ishandle(fig)
    rawAll = novecento_read_emg_block(dev, cfg.activeInputs, samplesPerBlock);
    if ~ishandle(fig)
        break;
    end

    rawBlock = double(rawAll(cfg.emgChannels, :));

    app = getappdata(fig, 'novecentoApp');
    app.blockCounter = app.blockCounter + 1;
    app.lastRawBlock = rawBlock;
    app.recordedEMG = [app.recordedEMG rawBlock];
    app.recordedDurationSec = size(app.recordedEMG, 2) / app.fs;

    assign_session_to_base(app);
    setappdata(fig, 'novecentoApp', app);
    update_plot_window(fig, ui);
    drawnow limitrate;
end

session = getappdata_safe(fig, app);

end

%% Stream validation
function validate_config_fields(cfg)

requiredFields = { ...
    'socketTimeoutSec', 'activeInputs', 'emgChannels', 'previewChannels', ...
    'blockDurationSec', 'visibleWindowSec', 'filterLivePlot', ...
    'useAdaptiveNotch', 'baseFreqRange', 'numHarmonics', 'notchWidth', ...
    'useBandpass', 'emgtype', 'GainFactor', 'FSelAux', ...
    'forceInputChannelCounts', 'hardwareQueryRetries', ...
    'hardwareQueryPauseSec', 'AnOutINSource', 'AnOutChan', 'AnOutGain', ...
    'IN_Active', 'Mode', 'Gain', 'HRES', 'HPF', 'FsampCode'};

missingFields = requiredFields(~isfield(cfg, requiredFields));
if ~isempty(missingFields)
    error('Missing cfg field(s): %s.', strjoin(missingFields, ', '));
end

if any(cfg.activeInputs < 1) || any(cfg.activeInputs > 10) || any(mod(cfg.activeInputs, 1) ~= 0)
    error('cfg.activeInputs must contain integer input numbers from 1 to 10.');
end

if any(cfg.emgChannels < 1) || any(mod(cfg.emgChannels, 1) ~= 0)
    error('cfg.emgChannels must contain positive integer channel numbers.');
end

if cfg.blockDurationSec <= 0
    error('cfg.blockDurationSec must be greater than zero.');
end

if cfg.FSelAux < 1 || cfg.FSelAux > 4 || mod(cfg.FSelAux, 1) ~= 0
    error('cfg.FSelAux must be 1, 2, 3, or 4.');
end

if cfg.emgtype ~= 1 && cfg.emgtype ~= 2
    error('cfg.emgtype must be 1 for surface EMG or 2 for intra-muscular EMG.');
end

vectorFields = {'IN_Active', 'Mode', 'Gain', 'HRES', 'HPF', 'FsampCode'};
for idx = 1:numel(vectorFields)
    fieldName = vectorFields{idx};
    if numel(cfg.(fieldName)) ~= 10
        error('cfg.%s must contain exactly 10 values.', fieldName);
    end
end

end

function [fs, samplesPerBlock] = validate_stream_settings(dev, cfg)

if isempty(cfg.activeInputs) || isempty(cfg.emgChannels)
    error('cfg.activeInputs and cfg.emgChannels must not be empty.');
end

fsVals = dev.fsInput(cfg.activeInputs);
if any(fsVals <= 0)
    error('No valid sampling rate detected for one or more active inputs.');
end

if numel(unique(fsVals)) ~= 1
    error('All active inputs must use the same sampling frequency.');
end

fs = fsVals(1);
samplesPerBlock = fs * cfg.blockDurationSec;
if mod(samplesPerBlock, 1) ~= 0
    error('cfg.blockDurationSec must produce an integer number of samples.');
end
samplesPerBlock = round(samplesPerBlock);

totalChannels = sum(dev.NumChan(cfg.activeInputs));
if any(cfg.emgChannels < 1) || any(mod(cfg.emgChannels, 1) ~= 0) || max(cfg.emgChannels) > totalChannels
    error('cfg.emgChannels must contain integer channel indices between 1 and %d.', totalChannels);
end

previewRows = get_preview_rows(cfg.previewChannels, numel(cfg.emgChannels));
if isempty(previewRows)
    error('cfg.previewChannels does not select any available EMG channels.');
end

end

%% User interface setup
function [fig, ui] = build_plot_window()

fig = figure( ...
    'Color', 'w', ...
    'Position', [80 60 1450 780], ...
    'Name', 'Novecento Live EMG Plot');

ui.axRaw = axes('Parent', fig, 'Position', [0.06 0.11 0.90 0.80]);
title(ui.axRaw, 'Live EMG Preview');
xlabel(ui.axRaw, 'Time (s)');
ylabel(ui.axRaw, 'Channel');
grid(ui.axRaw, 'on');

ui.statusText = uicontrol(fig, 'Style', 'text', ...
    'String', 'Waiting for data...', ...
    'Units', 'pixels', ...
    'Position', [20 738 1380 28], ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w');


end

%% Runtime state
function app = create_app_state(cfg, fs)

app = struct();
app.cfg = cfg;
app.fs = fs;
app.blockCounter = 0;
app.lastRawBlock = [];
app.recordedEMG = [];
app.recordedDurationSec = 0;
app.recordStartSample = [];
app.recordEndSample = [];
app.trimmedEMG = [];
app.recordStateText = 'Idle';

end

%% Plot refresh
function update_plot_window(fig, ui)

if ~ishandle(fig)
    return;
end

app = getappdata(fig, 'novecentoApp');
if isempty(app.recordedEMG)
    return;
end

previewRows = get_preview_rows(app.cfg.previewChannels, size(app.recordedEMG, 1));
channelLabels = app.cfg.emgChannels(previewRows);
nVisible = get_visible_sample_count(app.cfg.visibleWindowSec, app.fs, size(app.recordedEMG, 2));

visibleEMG = app.recordedEMG(previewRows, end - nVisible + 1:end);
visibleEMG = filter_display_emg(visibleEMG, app);
firstSample = size(app.recordedEMG, 2) - nVisible + 1;

novecento_plot_stacked(ui.axRaw, visibleEMG, channelLabels, app.fs, firstSample, app.cfg.visibleWindowSec);
if isfield(app.cfg, 'filterLivePlot') && app.cfg.filterLivePlot
    plotLabel = 'Filtered EMG Preview';
else
    plotLabel = 'Raw EMG Preview';
end
title(ui.axRaw, sprintf('%s | showing %d channel(s)', plotLabel, numel(previewRows)));

set(ui.statusText, 'String', sprintf( ...
    'Blocks: %d | Duration: %.2f s | Marker: %s', ...
    app.blockCounter, app.recordedDurationSec, app.recordStateText));


end

%% Display filtering
function displayEMG = filter_display_emg(displayEMG, app)

if ~isfield(app.cfg, 'filterLivePlot') || ~app.cfg.filterLivePlot || isempty(displayEMG)
    return;
end

displayEMG = double(displayEMG);

if ~isfield(app.cfg, 'useAdaptiveNotch') || app.cfg.useAdaptiveNotch
    displayEMG = adaptiveNotchFilter(displayEMG, app.fs, ...
        get_cfg_value(app.cfg, 'baseFreqRange', [45 55]), ...
        get_cfg_value(app.cfg, 'numHarmonics', 9), ...
        get_cfg_value(app.cfg, 'notchWidth', 1));
end

if ~isfield(app.cfg, 'useBandpass') || app.cfg.useBandpass
    displayEMG = bandpassingals(displayEMG, app.fs, ...
        get_cfg_value(app.cfg, 'emgtype', 1));
end

end

%% Config helper
function value = get_cfg_value(cfg, fieldName, defaultValue)

if isfield(cfg, fieldName)
    value = cfg.(fieldName);
else
    value = defaultValue;
end

end

%% Recording marker keys
function handle_marker_keypress(fig, event)

if ~ishandle(fig)
    return;
end

app = getappdata(fig, 'novecentoApp');
currentSample = size(app.recordedEMG, 2);

switch lower(event.Key)
    case 'r'
        % Start marker applies to the next sample appended after the keypress.
        app.recordStartSample = currentSample + 1;
        app.recordEndSample = [];
        app.trimmedEMG = [];
        app.recordStateText = sprintf('START at sample %d', app.recordStartSample);

    case 'q'
        % Stop marker trims a copy into trimmedEMG without changing recordedEMG.
        app.recordEndSample = currentSample;

        if isempty(app.recordStartSample)
            app.recordStateText = 'Press r before q';
        else
            startSample = max(1, min(app.recordStartSample, currentSample));
            endSample = max(startSample, min(app.recordEndSample, currentSample));
            app.recordStartSample = startSample;
            app.recordEndSample = endSample;
            app.trimmedEMG = app.recordedEMG(:, startSample:endSample);
            app.recordStateText = sprintf('STOP at sample %d | trimmedEMG ready', endSample);
        end

    otherwise
        return;
end

assign_session_to_base(app);
setappdata(fig, 'novecentoApp', app);

end

%% Preview channel helper
function previewRows = get_preview_rows(previewCfg, nAvailableRows)

if isscalar(previewCfg)
    previewRows = 1:min(previewCfg, nAvailableRows);
else
    previewRows = previewCfg(:)';
    previewRows = previewRows(previewRows >= 1 & previewRows <= nAvailableRows);
end

end

%% Visible sample helper
function nVisible = get_visible_sample_count(visibleWindowSec, fs, nRecordedSamples)

if isinf(visibleWindowSec)
    nVisible = nRecordedSamples;
else
    nVisible = min(nRecordedSamples, max(1, round(visibleWindowSec * fs)));
end

end

%% Adaptive notch filter for live display only
function filteredSignal = adaptiveNotchFilter(signal, fsamp, baseFreqRange, numHarmonics, notchWidth)

if nargin < 3
    baseFreqRange = [45, 55];
end
if nargin < 4
    numHarmonics = 9;
end
if nargin < 5
    notchWidth = 1;
end

[numChannels, signalLength] = size(signal);
filteredSignal = zeros(size(signal));

for channel = 1:numChannels
    signalFFT = fft(signal(channel, :));
    freqAxis = (0:signalLength-1) * fsamp / signalLength;

    baseFreqRange_idx = find(freqAxis >= baseFreqRange(1) & freqAxis <= baseFreqRange(2));
    if isempty(baseFreqRange_idx)
        filteredSignal(channel, :) = signal(channel, :);
        continue;
    end

    [~, maxIdx] = max(abs(signalFFT(baseFreqRange_idx)));
    baseFreq = freqAxis(baseFreqRange_idx(maxIdx));

    for harmonic = 1:numHarmonics
        notchFreq = harmonic * baseFreq;
        if notchFreq >= fsamp / 2
            break;
        end

        [b, a] = designNotchFilter(notchFreq, notchWidth, fsamp);
        signal(channel, :) = filtfilt(b, a, signal(channel, :));
    end

    filteredSignal(channel, :) = signal(channel, :);
end

end

%% Notch filter design
function [b, a] = designNotchFilter(notchFreq, notchWidth, fsamp)

wo = 2*pi*notchFreq/fsamp;
bw = 2*pi*notchWidth/fsamp;

r = 1 - bw/2;

b = [1 -2*cos(wo) 1];
a = [1 -2*r*cos(wo) r^2];

end

%% Band-pass filter for live display only
function filteredsignal = bandpassingals(signal, fsamp, emgtype)

if emgtype == 1
    highCut = min(500, 0.95 * fsamp / 2);
    [b, a] = butter(2, [20 highCut] / (fsamp / 2));
    filteredsignal = filtfilt(b, a, signal.').';
else
    highCut = min(4400, 0.95 * fsamp / 2);
    [b, a] = butter(3, [100 highCut] / (fsamp / 2));
    filteredsignal = filtfilt(b, a, signal.').';
end

end

%% Export session variables to MATLAB base workspace
function assign_session_to_base(app)

assignin('base', 'recordedEMG', app.recordedEMG);
assignin('base', 'recordedDurationSec', app.recordedDurationSec);
assignin('base', 'recordStartSample', app.recordStartSample);
assignin('base', 'recordEndSample', app.recordEndSample);
assignin('base', 'trimmedEMG', app.trimmedEMG);

end

%% Safe app-data read at shutdown
function session = getappdata_safe(fig, fallback)

if ishandle(fig)
    session = getappdata(fig, 'novecentoApp');
else
    session = fallback;
end

end

%% Hardware connection and stream configuration
function dev = novecento_connect(cfg)
% Open TCP connection, query hardware, send config, and build packet layout.

ip = '169.254.1.10';
tcpPort = 23456;

AuxFsamp = [0 16 32 48];
FsampVal = [500 2000 4000 8000];
SizeAux = [16 64 128 256];
ChVsType = [0 14 22 38 46 70 102 0 0 0 0 0 0 0 0 0];

cfg = prepare_input_config(cfg);
confString = build_config_string(cfg, AuxFsamp);

tcpSocket = tcpclient(ip, tcpPort);
tcpSocket.ByteOrder = "little-endian";
tcpSocket.Timeout = cfg.socketTimeoutSec;

settings = request_hardware_settings(tcpSocket, cfg);
write(tcpSocket, confString, 'uint8');

[numChan, ptrIn, sizeIn, cfg] = build_packet_layout(settings, cfg, ChVsType, FsampVal);

packetSize = ptrIn(11) - 1 + SizeAux(cfg.FSelAux) + 128;
try
    tcpSocket.InputBufferSize = max(packetSize * 500 * 4, 1e6);
catch
end

fsInput = zeros(10, 1);
for inputIdx = 1:10
    if cfg.IN_Active(inputIdx) == 1
        fsInput(inputIdx) = FsampVal(cfg.FsampCode(inputIdx) + 1);
    end
end

dev = struct();
dev.ip = ip;
dev.tcpSocket = tcpSocket;
dev.cfg = cfg;
dev.Settings = settings;
dev.ConfString = confString;
dev.PacketSize1Block = packetSize;
dev.NumChan = numChan;
dev.Ptr_IN = ptrIn;
dev.Size_IN = sizeIn;
dev.fsInput = fsInput;

end

%% Fill active input settings
function cfg = prepare_input_config(cfg)

cfg.IN_Active(:) = 0;
cfg.IN_Active(cfg.activeInputs) = 1;

for inputIdx = cfg.activeInputs(:)'
    if inputIdx ~= 1
        if cfg.Gain(inputIdx) == 0
            cfg.Gain(inputIdx) = cfg.Gain(1);
        end
        if cfg.HRES(inputIdx) == 0
            cfg.HRES(inputIdx) = cfg.HRES(1);
        end
        if cfg.HPF(inputIdx) == 0
            cfg.HPF(inputIdx) = cfg.HPF(1);
        end
        if cfg.FsampCode(inputIdx) == 0
            cfg.FsampCode(inputIdx) = cfg.FsampCode(1);
        end
    end
end

end

%% Device configuration packet
function confString = build_config_string(cfg, AuxFsamp)

confString = zeros(1, 15, 'uint8');
confString(1) = uint8(bin2dec('10000000') + AuxFsamp(cfg.FSelAux) + cfg.IN_Active(10) * 2 + cfg.IN_Active(9));

for inputIdx = 1:8
    confString(2) = uint8(double(confString(2)) + cfg.IN_Active(inputIdx) * 2^(inputIdx - 1));
end

confString(3) = uint8(cfg.AnOutGain + cfg.AnOutINSource);
confString(4) = uint8(cfg.AnOutChan);

for inputIdx = 1:10
    confString(4 + inputIdx) = uint8( ...
        cfg.Mode(inputIdx) * 64 + ...
        cfg.Gain(inputIdx) * 16 + ...
        cfg.HPF(inputIdx) * 8 + ...
        cfg.HRES(inputIdx) * 4 + ...
        cfg.FsampCode(inputIdx));
end

confString(15) = uint8(CRC8(double(confString), 14));

end

%% Hardware probe query
function settings = request_hardware_settings(tcpSocket, cfg)

settings = [];
lastReadError = [];

for attempt = 1:cfg.hardwareQueryRetries
    try
        flush(tcpSocket);
    catch
    end

    pause(cfg.hardwareQueryPauseSec);

    cmd = uint8([1 0]);
    cmd(2) = uint8(CRC8(double(cmd(1)), 1));
    write(tcpSocket, cmd, 'uint8');

    try
        settings = read(tcpSocket, 20, 'uint8')';
        break;
    catch ME
        lastReadError = ME;
    end
end

if isempty(settings)
    error('Hardware settings read failed after %d attempt(s): %s', ...
        cfg.hardwareQueryRetries, lastReadError.message);
end

if settings(20) == 255
    error('Hardware config request returned CRC error.');
end

end

%% Packet geometry
function [numChan, ptrIn, sizeIn, cfg] = build_packet_layout(settings, cfg, ChVsType, FsampVal)

numChan = zeros(10, 1);
ptrIn = zeros(11, 1);
sizeIn = zeros(11, 1);
ptrIn(1) = 1;

for inputIdx = 1:10
    probeType = double(settings(inputIdx + 1));
    if probeType >= 0 && probeType + 1 <= numel(ChVsType)
        numChan(inputIdx) = ChVsType(probeType + 1);
    end

    if ~isempty(cfg.forceInputChannelCounts) && inputIdx <= numel(cfg.forceInputChannelCounts)
        if cfg.forceInputChannelCounts(inputIdx) > 0
            numChan(inputIdx) = cfg.forceInputChannelCounts(inputIdx);
        end
    end

    if numChan(inputIdx) == 0
        cfg.IN_Active(inputIdx) = 0;
    end

    if cfg.IN_Active(inputIdx) == 1
        sizeIn(inputIdx) = (cfg.HRES(inputIdx) + 1) * ...
            FsampVal(cfg.FsampCode(inputIdx) + 1) / 500 * numChan(inputIdx);
    end

    ptrIn(inputIdx + 1) = ptrIn(inputIdx) + sizeIn(inputIdx);
end

end

%% Read one EMG block from TCP
function emg = novecento_read_emg_block(dev, inputIdxList, samplesPerBlock)
% The returned matrix is channels x samples. If multiple inputs are active,
% their channels are stacked vertically in the same order as inputIdxList.

fsActive = dev.fsInput(inputIdxList(1));
nBaseCols = samplesPerBlock * 500 / fsActive;

if mod(nBaseCols, 1) ~= 0
    error('samplesPerBlock must map to an integer number of Novecento packet columns.');
end
nBaseCols = round(nBaseCols);

nRead = dev.PacketSize1Block * nBaseCols;
rawValues = read(dev.tcpSocket, nRead, 'int16')';

if numel(rawValues) ~= nRead
    error('Short read from Novecento. Expected %d int16 values, got %d.', nRead, numel(rawValues));
end

packet = reshape(rawValues, dev.PacketSize1Block, nBaseCols);
blocks = cell(1, numel(inputIdxList));

for idx = 1:numel(inputIdxList)
    blocks{idx} = extract_input_block(packet, dev, inputIdxList(idx), nBaseCols);
end

emg = vertcat(blocks{:});

end

%% Decode one active input from a packet
function emg = extract_input_block(packet, dev, inputIdx, nBaseCols)

cfg = dev.cfg;
fsInput = dev.fsInput(inputIdx);
numChannels = dev.NumChan(inputIdx);

if cfg.IN_Active(inputIdx) ~= 1
    error('Requested input %d is not active.', inputIdx);
end

inputRows = dev.Ptr_IN(inputIdx):dev.Ptr_IN(inputIdx + 1) - 1;
linearValues = reshape(packet(inputRows, :), 1, []);
nSamples = fsInput * nBaseCols / 500;

if cfg.HRES(inputIdx) == 0
    emg = cfg.GainFactor * double(reshape(linearValues, numChannels, nSamples));
else
    int32Values = typecast(linearValues, 'int32');
    emg = cfg.GainFactor * double(reshape(int32Values, numChannels, nSamples));
end

end

%% Draw stacked EMG preview
function novecento_plot_stacked(ax, block, channelLabels, fs, firstSample, visibleWindowSec)
% Plot raw converted traces with stacked offsets.

cla(ax);
if isempty(block)
    return;
end

plotBlock = double(block);
offset = max(max(std(plotBlock, 0, 2) * 6), 1);

xSec = ((firstSample - 1):(firstSample + size(plotBlock, 2) - 2)) / fs;

hold(ax, 'on');
for ch = 1:size(plotBlock, 1)
    plot(ax, xSec, plotBlock(ch, :) + offset * (ch - 1), 'LineWidth', 0.8);
end
hold(ax, 'off');

grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Channel');

if isinf(visibleWindowSec)
    xlim(ax, [xSec(1) max(xSec(end), 1 / fs)]);
else
    xEnd = max(xSec(end), visibleWindowSec);
    xlim(ax, [xEnd - visibleWindowSec xEnd]);
end

yticks(ax, offset * (0:(numel(channelLabels) - 1)));
yticklabels(ax, cellstr(num2str(channelLabels(:))));
ylim(ax, [-offset offset * numel(channelLabels)]);

end

%% Stop streaming and close socket
function novecento_disconnect(dev)

try
    stopString = dev.ConfString;
    stopString(1) = uint8(bin2dec('00000000'));
    stopString(15) = uint8(CRC8(double(stopString), 14));
    write(dev.tcpSocket, stopString, 'uint8');
    pause(0.5);
catch
end

try
    clear dev.tcpSocket
catch
end

disp('Novecento connection closed.');

end
