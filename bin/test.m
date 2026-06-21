function novecento_online(userCfg)
% Live Novecento EMG preview with filtering + overall strength graph.
%
% Press r = mark start
% Press q = mark stop and create trimmedEMG / trimmedFilteredEMG
% Close figure = stop session

%% Configuration
cfg = default_cfg();
if nargin < 1
    userCfg = struct();
end
cfg = merge_structs(cfg, userCfg);

%% Connect
dev = novecento_connect(cfg);
cleanupObj = onCleanup(@() novecento_disconnect(dev)); %#ok<NASGU>

%% Validate sampling
fsVals = dev.fsInput(cfg.activeInputs);

if any(fsVals <= 0)
    error('No valid sampling rate detected for one or more active inputs.');
end

if numel(unique(fsVals)) ~= 1
    error('All active inputs must use the same sampling frequency.');
end

fs = fsVals(1);
nsamp = fs * cfg.blockDurationSec;

if mod(nsamp, 1) ~= 0
    error('cfg.blockDurationSec must produce an integer number of samples.');
end

nsamp = round(nsamp);

totalOnlineChan = sum(dev.NumChan(cfg.activeInputs));
if max(cfg.emgChannels) > totalOnlineChan
    error('cfg.emgChannels exceeds available channels across active inputs.');
end

%% Build figure
[fig, ui] = build_figure();

%% App state
app = struct();
app.cfg = cfg;
app.fs = fs;
app.blockCounter = 0;

app.lastRawBlock = [];
app.lastFilteredBlock = [];

app.recordedEMG = [];
app.recordedFilteredEMG = [];
app.recordedDurationSec = 0;

app.recordStartSample = [];
app.recordEndSample = [];
app.trimmedEMG = [];
app.trimmedFilteredEMG = [];
app.recordStateText = 'Idle';

app.blockStrength = 0;
app.emgActivityText = 'REST';
app.emgStrengthHistory = [];
app.emgStrengthTime = [];
app.emgActivityHistory = [];

assignin('base', 'recordedEMG', app.recordedEMG);
assignin('base', 'recordedFilteredEMG', app.recordedFilteredEMG);
assignin('base', 'recordedDurationSec', app.recordedDurationSec);
assignin('base', 'trimmedEMG', app.trimmedEMG);
assignin('base', 'trimmedFilteredEMG', app.trimmedFilteredEMG);
assignin('base', 'emgStrengthHistory', app.emgStrengthHistory);
assignin('base', 'emgStrengthTime', app.emgStrengthTime);

setappdata(fig, 'novecentoVisualApp', app);
set(fig, 'WindowKeyPressFcn', @(src, event) handle_marker_keypress(src, event));

fprintf('\n=== Novecento EMG filtered visualisation ===\n');
fprintf('Filtering: bandpass %.1f-%.1f Hz, notch %.1f Hz\n', ...
    cfg.bandpassHz(1), cfg.bandpassHz(2), cfg.notchFreq);
fprintf('Press r to mark start, q to mark stop.\n');
fprintf('Close figure to stop.\n\n');

%% Acquisition loop
while ishandle(fig)

    rawAll = novecento_read_multi_input_window(dev, cfg.activeInputs, nsamp, cfg.GainFactor);
    rawBlock = double(rawAll(cfg.emgChannels, :));

    app = getappdata(fig, 'novecentoVisualApp');

    % -------------------------------------------------------------
    % Filter EMG block
    % -------------------------------------------------------------
    filteredBlock = preprocess_emg_block(rawBlock, app.fs, app.cfg);

    % Overall EMG strength from filtered signal
    app.blockStrength = sqrt(mean(filteredBlock.^2, 'all'));

    if app.blockStrength > app.cfg.activationThreshold
        app.emgActivityText = 'ACTIVE';
        activityFlag = 1;
    else
        app.emgActivityText = 'REST';
        activityFlag = 0;
    end

    % Store strength
    currentStrengthTime = app.recordedDurationSec + app.cfg.blockDurationSec;
    app.emgStrengthHistory(end + 1) = app.blockStrength;
    app.emgStrengthTime(end + 1) = currentStrengthTime;
    app.emgActivityHistory(end + 1) = activityFlag;

    % Store raw and filtered EMG
    app.blockCounter = app.blockCounter + 1;
    app.lastRawBlock = rawBlock;
    app.lastFilteredBlock = filteredBlock;

    app.recordedEMG = [app.recordedEMG rawBlock]; %#ok<AGROW>
    app.recordedFilteredEMG = [app.recordedFilteredEMG filteredBlock]; %#ok<AGROW>
    app.recordedDurationSec = size(app.recordedEMG, 2) / app.fs;

    assignin('base', 'recordedEMG', app.recordedEMG);
    assignin('base', 'recordedFilteredEMG', app.recordedFilteredEMG);
    assignin('base', 'recordedDurationSec', app.recordedDurationSec);
    assignin('base', 'emgStrengthHistory', app.emgStrengthHistory);
    assignin('base', 'emgStrengthTime', app.emgStrengthTime);
    assignin('base', 'emgActivityHistory', app.emgActivityHistory);

    setappdata(fig, 'novecentoVisualApp', app);

    update_plots(fig, ui);
    drawnow;
end
end

%% Filtering
function filteredBlock = preprocess_emg_block(rawBlock, fs, cfg)

filteredBlock = double(rawBlock);

% Remove DC offset per channel
if cfg.removeDC
    filteredBlock = filteredBlock - mean(filteredBlock, 2);
end

% Band-pass filter for EMG
if cfg.useBandpass
    nyq = fs / 2;
    lowHz = cfg.bandpassHz(1);
    highHz = min(cfg.bandpassHz(2), nyq - 1);

    if lowHz <= 0 || highHz >= nyq || lowHz >= highHz
        warning('Invalid bandpass range. Skipping bandpass filter.');
    else
        [b, a] = butter(cfg.filterOrder, [lowHz highHz] / nyq, 'bandpass');
        filteredBlock = safe_filtfilt(b, a, filteredBlock);
    end
end

% Notch filter for power-line noise, usually 50 Hz in Europe
if cfg.useNotch
    nyq = fs / 2;
    notchHz = cfg.notchFreq;

    if notchHz > 0 && notchHz < nyq
        notchBW = cfg.notchBandwidthHz;
        lowStop = max(1, notchHz - notchBW/2);
        highStop = min(nyq - 1, notchHz + notchBW/2);

        [b, a] = butter(2, [lowStop highStop] / nyq, 'stop');
        filteredBlock = safe_filtfilt(b, a, filteredBlock);
    end
end

end

function y = safe_filtfilt(b, a, x)

% x is channels x samples
if size(x, 2) > 3 * max(length(a), length(b))
    y = filtfilt(b, a, x')';
else
    y = filter(b, a, x')';
end

end

%% Figure
function [fig, ui] = build_figure()

fig = figure( ...
    'Color', 'w', ...
    'Position', [80 60 1500 820], ...
    'Name', 'Novecento EMG Filtered Online Strength Pipeline');

ui.axRaw = axes('Parent', fig, 'Position', [0.06 0.38 0.90 0.50]);
title(ui.axRaw, 'Filtered EMG Preview');
xlabel(ui.axRaw, 'Time (s)');
ylabel(ui.axRaw, 'Channel');
grid(ui.axRaw, 'on');

ui.axStrength = axes('Parent', fig, 'Position', [0.06 0.10 0.90 0.20]);
title(ui.axStrength, 'Overall EMG Strength');
xlabel(ui.axStrength, 'Time (s)');
ylabel(ui.axStrength, 'RMS strength');
grid(ui.axStrength, 'on');

ui.statusText = uicontrol(fig, 'Style', 'text', ...
    'String', 'Preview running', ...
    'Units', 'pixels', ...
    'Position', [20 780 1450 28], ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w');

end

%% Update plots
function update_plots(fig, ui)

if ~ishandle(fig)
    return;
end

app = getappdata(fig, 'novecentoVisualApp');
recordedFilteredEMG = app.recordedFilteredEMG;

%% Filtered EMG preview
if ~isempty(recordedFilteredEMG)

    previewChannels = get_preview_channels(app.cfg.previewChannels, size(recordedFilteredEMG, 1));
    channelLabels = app.cfg.emgChannels(previewChannels);

    nVisibleSamples = get_visible_sample_count(app.cfg.visibleWindowSec, app.fs, size(recordedFilteredEMG, 2));
    visibleEMG = recordedFilteredEMG(previewChannels, end - nVisibleSamples + 1:end);
    firstSample = size(recordedFilteredEMG, 2) - nVisibleSamples + 1;

    plot_stacked_block(ui.axRaw, visibleEMG, channelLabels, app.fs, firstSample, app.cfg.visibleWindowSec);

    title(ui.axRaw, sprintf('Filtered EMG Preview | %s | RMS %.2f', ...
        app.emgActivityText, app.blockStrength));
end

%% Strength graph
cla(ui.axStrength);

if ~isempty(app.emgStrengthHistory)

    plot(ui.axStrength, app.emgStrengthTime, app.emgStrengthHistory, 'LineWidth', 1.5);
    hold(ui.axStrength, 'on');

    yline(ui.axStrength, app.cfg.activationThreshold, '--', 'Threshold');

    hold(ui.axStrength, 'off');

    grid(ui.axStrength, 'on');
    xlabel(ui.axStrength, 'Time (s)');
    ylabel(ui.axStrength, 'RMS strength');

    title(ui.axStrength, sprintf('Overall EMG Strength | %s', app.emgActivityText));

    if isinf(app.cfg.visibleWindowSec)
        xlim(ui.axStrength, [0 max(app.emgStrengthTime(end), app.cfg.blockDurationSec)]);
    else
        xEnd = max(app.emgStrengthTime(end), app.cfg.visibleWindowSec);
        xlim(ui.axStrength, [xEnd - app.cfg.visibleWindowSec xEnd]);
    end

    yMax = max([app.emgStrengthHistory app.cfg.activationThreshold 1]);
    ylim(ui.axStrength, [0 yMax * 1.2]);
end

%% Status text
set(ui.statusText, 'String', sprintf( ...
    'Blocks: %d | Duration: %.2f s | Marker: %s | EMG: %s | RMS: %.2f | Threshold: %.2f | Filter: %.0f-%.0f Hz + %.0f Hz notch', ...
    app.blockCounter, ...
    app.recordedDurationSec, ...
    app.recordStateText, ...
    app.emgActivityText, ...
    app.blockStrength, ...
    app.cfg.activationThreshold, ...
    app.cfg.bandpassHz(1), ...
    app.cfg.bandpassHz(2), ...
    app.cfg.notchFreq));

end

%% Keyboard markers
function handle_marker_keypress(fig, event)

if ~ishandle(fig)
    return;
end

app = getappdata(fig, 'novecentoVisualApp');
currentSample = size(app.recordedEMG, 2);

switch lower(event.Key)

    case 'r'
        app.recordStartSample = currentSample + 1;
        app.recordEndSample = [];
        app.trimmedEMG = [];
        app.trimmedFilteredEMG = [];
        app.recordStateText = sprintf('Recording STARTED at sample %d', app.recordStartSample);

        assignin('base', 'recordStartSample', app.recordStartSample);
        assignin('base', 'recordEndSample', app.recordEndSample);
        assignin('base', 'trimmedEMG', app.trimmedEMG);
        assignin('base', 'trimmedFilteredEMG', app.trimmedFilteredEMG);

        fprintf('recordStartSample saved at sample %d.\n', app.recordStartSample);

    case 'q'
        app.recordEndSample = currentSample;

        if isempty(app.recordStartSample)
            app.recordStateText = 'Stop marker ignored: press r before q';
            fprintf('recordEndSample ignored because recordStartSample is empty.\n');
        else
            startSample = max(1, min(app.recordStartSample, size(app.recordedEMG, 2)));
            endSample = max(startSample, min(app.recordEndSample, size(app.recordedEMG, 2)));

            app.recordStartSample = startSample;
            app.recordEndSample = endSample;

            app.trimmedEMG = app.recordedEMG(:, startSample:endSample);
            app.trimmedFilteredEMG = app.recordedFilteredEMG(:, startSample:endSample);

            app.recordStateText = sprintf('Recording STOPPED at sample %d | trimmed data created', app.recordEndSample);

            assignin('base', 'recordStartSample', app.recordStartSample);
            assignin('base', 'recordEndSample', app.recordEndSample);
            assignin('base', 'trimmedEMG', app.trimmedEMG);
            assignin('base', 'trimmedFilteredEMG', app.trimmedFilteredEMG);

            fprintf('recordEndSample saved at sample %d.\n', app.recordEndSample);
            fprintf('trimmedEMG created with size %d x %d.\n', ...
                size(app.trimmedEMG, 1), size(app.trimmedEMG, 2));
            fprintf('trimmedFilteredEMG created with size %d x %d.\n', ...
                size(app.trimmedFilteredEMG, 1), size(app.trimmedFilteredEMG, 2));
        end

    otherwise
        return;
end

setappdata(fig, 'novecentoVisualApp', app);

end

%% Plot stacked EMG
function plot_stacked_block(ax, block, channelLabels, fs, firstSample, visibleWindowSec)

cla(ax);

if isempty(block)
    return;
end

hold(ax, 'on');

plotBlock = double(block);
offset = max(max(std(plotBlock, 0, 2) * 6), 1);
xSec = ((firstSample - 1):(firstSample + size(plotBlock, 2) - 2)) / fs;

for ch = 1:size(plotBlock, 1)
    plot(ax, xSec, plotBlock(ch, :) + offset * (ch - 1), 'LineWidth', 1);
end

hold(ax, 'off');
grid(ax, 'on');

if isinf(visibleWindowSec)
    xlim(ax, [xSec(1) max(xSec(end), 1 / fs)]);
else
    xEnd = max(xSec(end), visibleWindowSec);
    xlim(ax, [xEnd - visibleWindowSec xEnd]);
end

ylim(ax, [-offset offset * size(plotBlock, 1)]);
yticks(ax, offset * (0:(size(plotBlock, 1) - 1)));
yticklabels(ax, cellstr(num2str(channelLabels(:))));

xlabel(ax, 'Time (s)');
ylabel(ax, 'Channel');

end

%% Helpers
function previewChannels = get_preview_channels(previewCfg, nAvailableChannels)

if isscalar(previewCfg)
    previewChannels = 1:min(previewCfg, nAvailableChannels);
else
    previewChannels = previewCfg(:)';
    previewChannels = previewChannels(previewChannels >= 1 & previewChannels <= nAvailableChannels);
end

end

function nVisibleSamples = get_visible_sample_count(visibleWindowSec, fs, nRecordedSamples)

if isinf(visibleWindowSec)
    nVisibleSamples = nRecordedSamples;
else
    nVisibleSamples = min(nRecordedSamples, max(1, round(visibleWindowSec * fs)));
end

end

%% Default config
function cfg = default_cfg()

cfg = struct();

% Acquisition
cfg.activeInputs = 1;
cfg.emgChannels = 1:64;
cfg.blockDurationSec = 1;

% Preview
cfg.previewChannels = 64;
cfg.visibleWindowSec = 10;

% EMG activity detection
cfg.activationThreshold = 50;

% Filtering
cfg.removeDC = true;
cfg.useBandpass = true;
cfg.bandpassHz = [20 450];       % typical EMG band
cfg.filterOrder = 4;

cfg.useNotch = true;
cfg.notchFreq = 50;              % Europe = 50 Hz
cfg.notchBandwidthHz = 4;        % removes 48-52 Hz

% Hardware read settings
cfg.socketTimeoutSec = 100;
cfg.hardwareQueryRetries = 3;
cfg.hardwareQueryPauseSec = 0.2;
cfg.forceInputChannelCounts = [];

% Device configuration
cfg.GainFactor = 0.2861;
cfg.FSelAux = 2;
cfg.AnOutINSource = 0;
cfg.AnOutChan = 1;
cfg.AnOutGain = bin2dec('00000000');

cfg.IN_Active = zeros(10,1);
cfg.Mode = zeros(10,1);
cfg.Gain = zeros(10,1);
cfg.HRES = zeros(10,1);
cfg.HPF = zeros(10,1);
cfg.FsampCode = zeros(10,1);

cfg.IN_Active(1) = 1;
cfg.Mode(1) = 0;
cfg.Gain(1) = 1;
cfg.HRES(1) = 1;
cfg.HPF(1) = 1;
cfg.FsampCode(1) = 1;

cfg.IN_Active(2) = 1;
cfg.Mode(2) = 0;
cfg.Gain(2) = 1;
cfg.HRES(2) = 1;
cfg.HPF(2) = 1;
cfg.FsampCode(2) = 1;

end

function S = merge_structs(S, U)

if isempty(U)
    return;
end

f = fieldnames(U);
for i = 1:numel(f)
    S.(f{i}) = U.(f{i});
end

end

%% Novecento connection
function dev = novecento_connect(cfg)

AuxFsamp = [0 16 32 48];
FsampVal = [500 2000 4000 8000];
SizeAux = [16 64 128 256];
ChVsType = [0 14 22 38 46 70 102 0 0 0 0 0 0 0 0 0];

cfg.IN_Active(:) = 0;
cfg.Mode(:) = 0 + cfg.Mode(:);
cfg.Gain(:) = 0 + cfg.Gain(:);
cfg.HRES(:) = 0 + cfg.HRES(:);
cfg.HPF(:) = 0 + cfg.HPF(:);
cfg.FsampCode(:) = 0 + cfg.FsampCode(:);
cfg.IN_Active(cfg.activeInputs) = 1;

for ii = cfg.activeInputs(:)'
    if ii ~= 1
        cfg.Mode(ii) = cfg.Mode(ii) + (cfg.Mode(ii) == 0) * cfg.Mode(1);
        cfg.Gain(ii) = cfg.Gain(ii) + (cfg.Gain(ii) == 0) * cfg.Gain(1);
        cfg.HRES(ii) = cfg.HRES(ii) + (cfg.HRES(ii) == 0) * cfg.HRES(1);
        cfg.HPF(ii) = cfg.HPF(ii) + (cfg.HPF(ii) == 0) * cfg.HPF(1);
        cfg.FsampCode(ii) = cfg.FsampCode(ii) + (cfg.FsampCode(ii) == 0) * cfg.FsampCode(1);
    end
end

ConfString = zeros(1, 15, 'uint8');
ConfString(1) = uint8(bin2dec('10000000') + AuxFsamp(cfg.FSelAux) + cfg.IN_Active(10)*2 + cfg.IN_Active(9));
ConfString(2) = uint8(0);

for i = 1:8
    ConfString(2) = uint8(double(ConfString(2)) + cfg.IN_Active(i) * (2^(i-1)));
end

ConfString(3) = uint8(cfg.AnOutGain + cfg.AnOutINSource);
ConfString(4) = uint8(cfg.AnOutChan);

for i = 1:10
    ConfString(4+i) = uint8(cfg.Mode(i)*64 + cfg.Gain(i)*16 + cfg.HPF(i)*8 + cfg.HRES(i)*4 + cfg.FsampCode(i));
end

ConfString(15) = uint8(novecento_crc8(double(ConfString), 14));

ip = '169.254.1.10';
tcpSocket = tcpclient(ip, 23456);
tcpSocket.ByteOrder = "little-endian";
tcpSocket.Timeout = cfg.socketTimeoutSec;

fprintf('Connected to Novecento socket at %s\n', ip);

Settings = [];
lastReadError = [];

for attempt = 1:cfg.hardwareQueryRetries
    try
        flush(tcpSocket);
    catch
    end

    pause(cfg.hardwareQueryPauseSec);

    cmd = uint8([1 0]);
    cmd(2) = uint8(novecento_crc8(double(cmd(1)), 1));
    write(tcpSocket, cmd, 'uint8');

    try
        Settings = read(tcpSocket, 20, 'uint8')';
        break;
    catch ME
        lastReadError = ME;
    end
end

if isempty(Settings)
    error('Hardware settings read failed after %d attempt(s): %s', ...
        cfg.hardwareQueryRetries, lastReadError.message);
end

if Settings(20) == 255
    error('Hardware config request returned CRC error.');
end

write(tcpSocket, ConfString, 'uint8');

NumChan = zeros(10,1);
Ptr_IN = zeros(11,1);
Size_IN = zeros(11,1);
Ptr_IN(1) = 1;

for i = 1:10

    probeType = double(Settings(i+1));

    if probeType >= 0 && probeType + 1 <= numel(ChVsType)
        NumChan(i) = ChVsType(probeType + 1);
    end

    if NumChan(i) == 0
        cfg.IN_Active(i) = 0;
    end

    if cfg.IN_Active(i) == 1
        Size_IN(i) = (cfg.HRES(i)+1) * FsampVal(cfg.FsampCode(i)+1) / 500 * NumChan(i);
    else
        Size_IN(i) = 0;
    end

    Ptr_IN(i+1) = Ptr_IN(i) + Size_IN(i);
end

if ~isempty(cfg.forceInputChannelCounts)

    Ptr_IN(1) = 1;

    for i = 1:min(numel(cfg.forceInputChannelCounts), 10)
        if cfg.forceInputChannelCounts(i) > 0
            NumChan(i) = cfg.forceInputChannelCounts(i);
        end
    end

    for i = 1:10
        if cfg.IN_Active(i) == 1
            Size_IN(i) = (cfg.HRES(i)+1) * FsampVal(cfg.FsampCode(i)+1) / 500 * NumChan(i);
        else
            Size_IN(i) = 0;
        end

        Ptr_IN(i+1) = Ptr_IN(i) + Size_IN(i);
    end
end

PacketSize1Block = Ptr_IN(11) - 1 + SizeAux(cfg.FSelAux) + 128;

try
    tcpSocket.InputBufferSize = max(PacketSize1Block * 500 * 4, 1e6);
catch
end

fsInput = zeros(10,1);

for i = 1:10
    if cfg.IN_Active(i) == 1
        fsInput(i) = FsampVal(cfg.FsampCode(i)+1);
    end
end

dev = struct();
dev.ip = ip;
dev.tcpSocket = tcpSocket;
dev.cfg = cfg;
dev.Settings = Settings;
dev.ConfString = ConfString;
dev.PacketSize1Block = PacketSize1Block;
dev.NumChan = NumChan;
dev.Ptr_IN = Ptr_IN;
dev.Size_IN = Size_IN;
dev.fsInput = fsInput;

end

%% Read EMG block
function EMG = novecento_read_multi_input_window(dev, inputIdxList, nsamp, gainFactor)

fsActive = dev.fsInput(inputIdxList(1));
nBaseCols = nsamp * 500 / fsActive;

if mod(nBaseCols, 1) ~= 0
    error('nsamp must map to an integer number of Novecento base columns.');
end

nBaseCols = round(nBaseCols);
nRead = dev.PacketSize1Block * nBaseCols;

Temp = read(dev.tcpSocket, nRead, 'int16')';

if numel(Temp) ~= nRead
    error('Short read from Novecento. Expected %d int16 values, got %d.', nRead, numel(Temp));
end

Data = reshape(Temp, dev.PacketSize1Block, nBaseCols);

blocks = cell(1, numel(inputIdxList));

for i = 1:numel(inputIdxList)
    blocks{i} = novecento_extract_input_block(Data, dev, inputIdxList(i), nBaseCols, gainFactor);
end

EMG = vertcat(blocks{:});

end

function EMG = novecento_extract_input_block(Data, dev, inputIdx, nBaseCols, gainFactor)

cfg = dev.cfg;
fsInput = dev.fsInput(inputIdx);
numCh = dev.NumChan(inputIdx);

if cfg.IN_Active(inputIdx) ~= 1
    error('Requested input %d is not active.', inputIdx);
end

if cfg.HRES(inputIdx) == 0

    temp1 = reshape(Data(dev.Ptr_IN(inputIdx):dev.Ptr_IN(inputIdx+1)-1, :), 1, []);
    EMG = gainFactor * double(reshape(temp1, numCh, fsInput * nBaseCols / 500));

else

    temp1 = reshape(Data(dev.Ptr_IN(inputIdx):dev.Ptr_IN(inputIdx+1)-1, :), 1, []);
    temp2 = typecast(temp1, 'int32');
    EMG = gainFactor * double(reshape(temp2, numCh, fsInput * nBaseCols / 500));

end

end

%% Disconnect
function novecento_disconnect(dev)

try
    stopString = dev.ConfString;
    stopString(1) = uint8(bin2dec('00000000'));
    stopString(15) = uint8(novecento_crc8(double(stopString), 14));
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

%% CRC
function crc = novecento_crc8(vector, len)

crc = 0;
idx = 1;

while len > 0

    extract = vector(idx);

    for i = 8:-1:1 %#ok<NASGU>

        sumBit = xor(mod(crc, 2), mod(extract, 2));
        crc = floor(crc / 2);

        if sumBit > 0

            bitsA = dec2bin(crc, 8);
            bitsB = dec2bin(140, 8);
            bitsOut = zeros(1, 8);

            for k = 1:8
                bitsOut(k) = ~((bitsA(k) == bitsB(k)));
            end

            crc = bin2dec(strrep(num2str(bitsOut), ' ', ''));

        end

        extract = floor(extract / 2);

    end

    len = len - 1;
    idx = idx + 1;

end

end
