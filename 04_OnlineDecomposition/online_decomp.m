function out = online_decomp(Calib_data, calibEMG_full, fs, badchan, userCfg)
% RUN_REALTIME_NOVECENTO_FROM_CALIB
% -------------------------------------------------------------------------
% True real-time online EMG decomposition using Novecento+ streaming and
% motor-unit filters obtained from offline calibration.
%
% This runner is intended for continuous live use:
%   1. build online parameters from calibration EMG + MU filters
%   2. connect to Novecento+
%   3. stream one block at a time from one or more inputs
%   4. detect MU discharges online with getspikesonline
%   5. update raster/firing-rate plots live
%   6. stop cleanly when the figure is closed or duration is reached
%
% INPUTS
%   Calib_data    : struct returned by decompose3
%   calibEMG_full : calibration EMG (channels x samples)
%   fs            : calibration sampling rate
%   badchan       : bad channels within the selected calibration channels
%   userCfg       : optional config overrides
%
% OUTPUT
%   out : struct containing configuration, calibration parameters,
%         accumulated online outputs, and session timing info

%% 1) Configuration merge and input validation

cfg = default_cfg();
if nargin < 5 || isempty(userCfg)
    userCfg = struct;
end
cfg = merge_structs(cfg, userCfg);

if nargin < 4 || isempty(badchan)
    badchan = [];
end

validate_inputs(Calib_data, calibEMG_full, fs, badchan, cfg);

% Select calibration channels if full array was provided.
if size(calibEMG_full,1) == numel(cfg.calibChannels)
    calibEMG = calibEMG_full;
else
    calibEMG = calibEMG_full(cfg.calibChannels, :);
end

% Build bad-channel mask in calibration channel space (0=good, 1=bad).
nCalibChan = size(calibEMG, 1);
EMGmask = zeros(nCalibChan, 1);
if ~isempty(badchan)
    EMGmask(badchan) = 1;
end

MUFilters = Calib_data.MUFilters;
nMU = size(MUFilters, 2);
nGood = sum(EMGmask == 0);

fprintf('\n=== Preparing Noveceto+ real-time decomposition ===\n');
fprintf('Calibration channels: %d\n', nCalibChan);
fprintf('Good channels: %d\n', nGood);
fprintf('Bad channels: %d\n', sum(EMGmask));
fprintf('Motor units: %d\n', nMU);

[extensionfactor, iReSIG, normval, centroid] = ...
    getonlineparameters(calibEMG, EMGmask, MUFilters, fs);

% Precompute online MU projection filters.
MUfilt = MUFilters' * iReSIG;

%% 2) Novecento connection and online stream geometry
dev = novecento_connect(cfg);
% Ensure hardware is stopped/disconnected on any exit path.
cleanupObj = onCleanup(@() novecento_disconnect(dev)); %#ok<NASGU>

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
    warning('Offline fs = %d and online fs = %d. Decoding quality may degrade.', fs, fs_online);
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

% Expand class centroids across a full window for online classifier use.
noise_centroids = ones(nsamp, nMU) .* centroid(:,1)';
spike_centroids = ones(nsamp, nMU) .* centroid(:,2)';
% Stateful overlap buffer required by getspikesonline across windows.
esample2 = zeros(nGood * extensionfactor, extensionfactor - 1);

%% 3) Figure/state initialization and online accumulators
[fig, plotState] = init_live_figure(nMU, cfg);

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

%% 4) Real-time processing loop
while ishandle(fig)
    if getappdata(fig, 'stopRequested')
        break;
    end

    elapsedSec = toc(sessionStart);
    if isfinite(cfg.onlineDurationSec) && elapsedSec >= cfg.onlineDurationSec
        break;
    end

    % Read one multi-input hardware window, then keep only requested EMG channels.
    blockAll = novecento_read_multi_input_window(dev, activeInputs, cfg.windowBaseCols, cfg.GainFactor);
    emgBlock = blockAll(cfg.emgChannels, :);
    % Remove channels marked bad during calibration.
    emgGood = emgBlock(EMGmask == 0, :);

    [pulseChunk, distChunk, esample2] = getspikesonline( ...
        emgGood, extensionfactor, esample2, MUfilt, normval, ...
        noise_centroids, spike_centroids, nsamp, fs_online);

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
            Dischargetimes_online{mu} = [Dischargetimes_online{mu}; new_spikes(:)]; %#ok<AGROW>
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

    update_live_plot(fig, plotState, Dischargetimes_online, fr_online, currentTime, cfg, fs_online);

    if cfg.printEveryNWindows > 0 && mod(windowCount, cfg.printEveryNWindows) == 0
        spikesThisWin = sum(distChunk, 1);
        fprintf('Window %4d | t = %7.2f s | spikes = %s\n', ...
            windowCount, currentTime, mat2str(spikesThisWin));
    end
end

%% 5) Concatenate buffers and build output struct
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

out.calibration = struct();
out.calibration.MUFilters = MUFilters;
out.calibration.EMGmask = EMGmask;
out.calibration.extensionfactor = extensionfactor;
out.calibration.iReSIG = iReSIG;
out.calibration.norm = normval;
out.calibration.centroid = centroid;

out.online = struct();
out.online.EMG = EMG_online;
out.online.Pulsetrain = Pulsetrain_online;
out.online.Distime = Distime;
out.online.Dischargetimes = Dischargetimes_online;
out.online.fr = fr_online;
out.online.mean_fr = mean_fr_online;
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
function validate_inputs(Calib_data, calibEMG_full, fs, badchan, cfg)
if nargin < 5
    error('Missing inputs.');
end

if isempty(Calib_data) || ~isstruct(Calib_data)
    error('Calib_data must be a non-empty struct.');
end

if ~isfield(Calib_data, 'MUFilters') || isempty(Calib_data.MUFilters)
    error('Calib_data.MUFilters is missing or empty.');
end

if isempty(calibEMG_full) || ndims(calibEMG_full) ~= 2
    error('calibEMG_full must be channels x samples.');
end

if isempty(fs) || ~isscalar(fs) || fs <= 0
    error('fs must be a positive scalar.');
end

if isempty(cfg.calibChannels)
    error('cfg.calibChannels must be specified.');
end

if isempty(cfg.emgChannels)
    error('cfg.emgChannels must be specified.');
end

if ~isfield(cfg, 'activeInputs') || isempty(cfg.activeInputs)
    error('cfg.activeInputs must be specified.');
end

if numel(cfg.calibChannels) ~= numel(cfg.emgChannels)
    error('cfg.calibChannels and cfg.emgChannels must have the same length.');
end

if size(calibEMG_full,1) < max(cfg.calibChannels) && size(calibEMG_full,1) ~= numel(cfg.calibChannels)
    error('calibEMG_full does not contain cfg.calibChannels.');
end

if ~isempty(badchan) && max(badchan) > numel(cfg.calibChannels)
    error('badchan refers outside the selected calibration channels.');
end
end

%% Plot initialization and live update helpers
function [fig, plotState] = init_live_figure(nMU, cfg)
colors = lines(nMU);

fig = figure( ...
    'Color', 'w', ...
    'Position', [60 60 1400 820], ...
    'Name', 'Novecento Real-Time Decomposition', ...
    'CloseRequestFcn', @stop_figure);
setappdata(fig, 'stopRequested', false);

axRaster = subplot(2,1,1, 'Parent', fig);
hold(axRaster, 'on');
grid(axRaster, 'on');
title(axRaster, 'Live Spike Trains', 'FontSize', 11);
xlabel(axRaster, 'Time (s)');
ylabel(axRaster, 'Motor Unit');
ylim(axRaster, [0 nMU + 1]);
yticks(axRaster, 1:nMU);
yticklabels(axRaster, arrayfun(@(x) sprintf('MU%d  (0 spikes)', x), 1:nMU, 'UniformOutput', false));

axFr = subplot(2,1,2, 'Parent', fig);
hold(axFr, 'on');
grid(axFr, 'on');
title(axFr, 'Instantaneous Firing Rate (Hz)', 'FontSize', 11);
xlabel(axFr, 'Time (s)');
ylabel(axFr, 'Firing Rate (Hz)');
ylim(axFr, [0 cfg.frYLim]);

hRaster = gobjects(nMU, 1);
hFr = gobjects(nMU, 1);
for mu = 1:nMU
    hRaster(mu) = plot(axRaster, nan, nan, '|', ...
        'Color', colors(mu,:), 'MarkerSize', 10, 'LineWidth', 1.4);
    hFr(mu) = plot(axFr, nan, nan, '.', ...
        'Color', colors(mu,:), 'MarkerSize', 5, ...
        'DisplayName', sprintf('MU%d', mu));
end

if cfg.showLegend
    legend(axFr, 'Location', 'eastoutside', 'FontSize', 7);
end

tlineRaster = xline(axRaster, 0, 'r--', 'LineWidth', 1.2);
tlineFr = xline(axFr, 0, 'r--', 'LineWidth', 1.2);

uicontrol(fig, 'Style', 'pushbutton', ...
    'String', 'Stop', ...
    'Units', 'pixels', ...
    'Position', [20 20 80 28], ...
    'Callback', @(src, evt) request_stop(fig)); %#ok<NASGU>

plotState = struct();
plotState.axRaster = axRaster;
plotState.axFr = axFr;
plotState.hRaster = hRaster;
plotState.hFr = hFr;
plotState.tlineRaster = tlineRaster;
plotState.tlineFr = tlineFr;
end

function update_live_plot(fig, plotState, Dischargetimes_online, fr_online, currentTime, cfg, fs_online)
if ~ishandle(fig)
    return;
end

nMU = numel(Dischargetimes_online);
for mu = 1:nMU
    spikes = Dischargetimes_online{mu};
    if ~isempty(spikes)
        spikeTimes = spikes / fs_online;
        set(plotState.hRaster(mu), 'XData', spikeTimes, 'YData', mu * ones(size(spikeTimes)));
    end

    if numel(spikes) > 1
        frTimes = spikes(2:end) / fs_online;
        set(plotState.hFr(mu), 'XData', frTimes, 'YData', fr_online{mu});
    end
end

set(plotState.tlineRaster, 'Value', currentTime);
set(plotState.tlineFr, 'Value', currentTime);

xMin = max(0, currentTime - cfg.visibleWindowSec);
xMax = max(cfg.visibleWindowSec, currentTime);
xlim(plotState.axRaster, [xMin xMax]);
xlim(plotState.axFr, [xMin xMax]);

yticklabels(plotState.axRaster, arrayfun(@(mu) ...
    sprintf('MU%d  (%d spikes)', mu, numel(Dischargetimes_online{mu})), ...
    1:nMU, 'UniformOutput', false));

title(plotState.axRaster, sprintf('Live Spike Trains  |  t = %.2f s', currentTime), 'FontSize', 11);

drawnow limitrate;
end

%% Utility helpers
function out = concat_chunks(chunks, nRows)
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

function request_stop(fig)
if ishghandle(fig)
    setappdata(fig, 'stopRequested', true);
end
end

function stop_figure(fig, ~)
setappdata(fig, 'stopRequested', true);
delete(fig);
end

%% Default configuration and override merge
function cfg = default_cfg()
cfg = struct();

cfg.WiFi = 0;
cfg.TCPPort = 23456;
cfg.IP_eth = '169.254.1.10';
cfg.IP_wifi = '192.168.1.1';

cfg.activeInputs = [1 2];
cfg.calibChannels = 1:128;
% Two 64-electrode Novecento probes are streamed as 70 rows each:
% keep rows 1:64 from input 1 and rows 71:134 from input 2.
cfg.emgChannels = [1:64 71:134];

cfg.onlineDurationSec = inf;
cfg.visibleWindowSec = 20;
cfg.windowBaseCols = 64;
cfg.recordEMG = true;
cfg.printEveryNWindows = 10;
cfg.showLegend = true;
cfg.frYLim = 60;
cfg.queryMetadata = false;
cfg.socketTimeoutSec = 100;
cfg.hardwareQueryRetries = 3;
cfg.hardwareQueryPauseSec = 0.2;
cfg.forceInputChannelCounts = [];

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

%% Novecento hardware connection/configuration
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

% For active inputs beyond #1, inherit unset acquisition parameters from input #1.
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

if cfg.WiFi == 1
    ip = cfg.IP_wifi;
else
    ip = cfg.IP_eth;
end

tcpSocket = tcpclient(ip, cfg.TCPPort);
tcpSocket.ByteOrder = "little-endian";
tcpSocket.Timeout = cfg.socketTimeoutSec;

disp('Connected to the socket');

try
    flush(tcpSocket);
catch
end

if cfg.queryMetadata
    try
        cmd = uint8([2 0]);
        cmd(2) = uint8(novecento_crc8(double(cmd(1)), 1));
        write(tcpSocket, cmd, 'uint8');
        fw = read(tcpSocket, 20, 'uint8')';
        disp('Firmware info:');
        disp(char(fw(2:end)));
    catch ME
        warning('Firmware query skipped: %s', ME.message);
        try
            flush(tcpSocket);
        catch
        end
    end

    try
        cmd = uint8([3 0]);
        cmd(2) = uint8(novecento_crc8(double(cmd(1)), 1));
        write(tcpSocket, cmd, 'uint8');
        bat = read(tcpSocket, 20, 'uint8')';
        fprintf('Battery level: %d%%\n', bat(2));
    catch ME
        warning('Battery query skipped: %s', ME.message);
        try
            flush(tcpSocket);
        catch
        end
    end
end

% Query hardware input/probe configuration with retries.
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

if numel(Settings) ~= 20
    error('Hardware settings read failed.');
end

if Settings(20) == 255
    error('Hardware config request returned CRC error.');
end

fprintf('Raw hardware settings bytes: %s\n', mat2str(double(Settings)));
disp('Probe types per input:');
disp(Settings(2:11));
pause(0.2);

write(tcpSocket, ConfString, 'uint8');

% Compute channel counts and packet layout pointers for each input.
NumChan = zeros(10,1);
Ptr_IN = zeros(11,1);
Size_IN = zeros(11,1);
Ptr_IN(1) = 1;
NumActInputs = 0;

for i = 1:10
    probeType = double(Settings(i+1));
    if probeType < 0 || probeType + 1 > numel(ChVsType)
        warning('Unexpected probe type code %d on input %d. Treating as disconnected.', probeType, i);
        NumChan(i) = 0;
    else
        NumChan(i) = ChVsType(probeType + 1);
    end

    if NumChan(i) == 0
        cfg.IN_Active(i) = 0;
    end

    if cfg.IN_Active(i) == 1
        Size_IN(i) = (cfg.HRES(i)+1) * FsampVal(cfg.FsampCode(i)+1) / 500 * NumChan(i);
        NumActInputs = NumActInputs + 1;
    else
        Size_IN(i) = 0;
    end

    Ptr_IN(i+1) = Ptr_IN(i) + Size_IN(i);
end

if ~isempty(cfg.forceInputChannelCounts)
    % Optional manual override when device probe type reporting is unreliable.
    for idx = 1:min(numel(cfg.forceInputChannelCounts), 10)
        forcedCount = cfg.forceInputChannelCounts(idx);
        if forcedCount > 0
            NumChan(idx) = forcedCount;
            if any(cfg.activeInputs == idx)
                cfg.IN_Active(idx) = 1;
                Size_IN(idx) = (cfg.HRES(idx)+1) * FsampVal(cfg.FsampCode(idx)+1) / 500 * NumChan(idx);
            end
        end
    end

    Ptr_IN(1) = 1;
    NumActInputs = 0;
    for i = 1:10
        if cfg.IN_Active(i) == 1
            Size_IN(i) = (cfg.HRES(i)+1) * FsampVal(cfg.FsampCode(i)+1) / 500 * NumChan(i);
            NumActInputs = NumActInputs + 1;
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
dev.NumActInputs = NumActInputs;
dev.fsInput = fsInput;
end

%% Packet read and input extraction
function EMG = novecento_read_multi_input_window(dev, inputIdxList, nBaseCols, gainFactor)
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
    % Standard-resolution mode uses int16 samples directly.
    temp1 = reshape(Data(dev.Ptr_IN(inputIdx):dev.Ptr_IN(inputIdx+1)-1, :), 1, []);
    EMG = gainFactor * double(reshape(temp1, numCh, fsInput * nBaseCols / 500));
else
    % High-resolution mode packs samples as int32.
    temp1 = reshape(Data(dev.Ptr_IN(inputIdx):dev.Ptr_IN(inputIdx+1)-1, :), 1, []);
    temp2 = typecast(temp1, 'int32');
    EMG = gainFactor * double(reshape(temp2, numCh, fsInput * nBaseCols / 500));
end
end

%% Graceful hardware shutdown
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

%% CRC helper used by Novecento command packets
function crc = novecento_crc8(vector, len)
crc = 0;
idx = 1;

while len > 0
    extract = vector(idx);
    for i = 8:-1:1
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
