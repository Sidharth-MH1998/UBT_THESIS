
function out = online_decomp_signal_force(signal,parameters,cfg,sharedUI)
%ONLINE_DECOMP_SIGNAL_FORCE Online decomposition for the force pipeline.
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
% Final filters are read from signal.RefinedMUFilters when available.
% Otherwise, the original signal.MUFilters matrix is used directly.

%% 1) Read and validate the MUedit structures
if nargin < 3 || ~isstruct(cfg) || isempty(cfg)
    error('A complete cfg structure must be supplied.');
end

validate_signal_inputs(signal,parameters,cfg);

calibEMG_full = double(signal.data);
fs = signal.fsamp;
fullMask = signal.EMGmask{1}(:) ~= 0; % false = good, true = bad

% Select the same electrode rows that will be streamed online.
if size(calibEMG_full,1) == numel(cfg.calibChannels)
    calibEMG = calibEMG_full;
    EMGmask = fullMask;
else
    calibEMG = calibEMG_full(cfg.calibChannels,:);
    EMGmask = fullMask(cfg.calibChannels);
end

nCalibChan = size(calibEMG,1);
nGood = sum(~EMGmask);
if nGood < 1
    error('The EMG mask excludes every calibration channel.');
end

finalPulseTrain = signal.Pulsetrain{1};
nFinalMU = size(finalPulseTrain,1);

% MU filters are always rebuilt from calibration EMG and discharge times.
% getMUfilters uses a fixed target of 1000 extended channels.
onlineNbextchan = 1000;
extensionfactor = max(round(onlineNbextchan/nGood),1);
expectedFilterRows = nGood*extensionfactor;

Distime = signal.Dischargetimes;
if iscell(Distime) && numel(Distime) == 1 && iscell(Distime{1})
    Distime = Distime{1};
elseif iscell(Distime) && size(Distime,1) >= 1
    Distime = Distime(1,:);
end
if ~iscell(Distime) || numel(Distime) ~= nFinalMU
    error(['Cannot rebuild MU filters: signal.Dischargetimes must ' ...
        'contain one cell per motor unit.']);
end

MUFilters = double(getMUfilters(calibEMG,EMGmask,Distime));
if ~isequal(size(MUFilters),[expectedFilterRows nFinalMU])
    error(['Rebuilt MU filters have size %s, but %s is required.'], ...
        mat2str(size(MUFilters)),mat2str([expectedFilterRows nFinalMU]));
end
if ~all(isfinite(MUFilters),'all') || any(vecnorm(MUFilters) == 0)
    error('One or more rebuilt MU filters are invalid.');
end
nMU = nFinalMU;
filterMessage = 'Rebuilt MU filter matrix using getMUfilters';

fprintf('\n=== Preparing Novecento+ real-time decomposition ===\n');
fprintf('Calibration channels: %d\n',nCalibChan);
fprintf('Good channels: %d\n',nGood);
fprintf('Bad channels: %d\n',sum(EMGmask));
fprintf('Online motor-unit filters: %d\n',nMU);
fprintf('%s: %d x %d\n',filterMessage, ...
    size(MUFilters,1),size(MUFilters,2));

[extensionfactor,iReSIG,normval,centroid] = prepare_online_parameters( ...
    calibEMG,EMGmask,MUFilters,fs,onlineNbextchan);
MUfilt = MUFilters' * iReSIG;

%% 2) Novecento connection and online stream geometry
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
[fig, plotState] = init_live_figure(nMU, cfg, sharedUI);

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
if ~iscell(signal.Pulsetrain) || isempty(signal.Pulsetrain) || ...
        isempty(signal.Pulsetrain{1})
    error('signal.Pulsetrain{1} is missing or empty.');
end
if ~iscell(signal.Dischargetimes)
    error('signal.Dischargetimes must be a cell array.');
end
if ~iscell(signal.EMGmask) || isempty(signal.EMGmask)
    error('signal.EMGmask must be a non-empty cell array.');
end
if numel(signal.EMGmask{1}) ~= size(signal.data,1)
    error('signal.EMGmask{1} does not match the EMG channel count.');
end
if size(signal.Pulsetrain{1},2) ~= size(signal.data,2)
    error('The calibration EMG and pulse trains have different lengths.');
end
if numel(signal.Dischargetimes) ~= size(signal.Pulsetrain{1},1)
    error('Discharge-time and pulse-train motor-unit counts differ.');
end
if isempty(cfg.activeInputs) || isempty(cfg.calibChannels) || ...
        isempty(cfg.emgChannels)
    error('Active inputs, calibration channels, and online EMG channels are required.');
end
if numel(cfg.calibChannels) ~= numel(cfg.emgChannels)
    error('cfg.calibChannels and cfg.emgChannels must have the same length.');
end
if size(signal.data,1) < max(cfg.calibChannels) && ...
        size(signal.data,1) ~= numel(cfg.calibChannels)
    error('signal.data does not contain cfg.calibChannels.');
end

requiredCfg = {'WiFi','TCPPort','IP_eth','IP_wifi','activeInputs', ...
    'calibChannels','emgChannels','onlineDurationSec', ...
    'visibleWindowSec','windowBaseCols','recordEMG', ...
    'printEveryNWindows','showLegend','frYLim','queryMetadata', ...
    'socketTimeoutSec','hardwareQueryRetries', ...
    'hardwareQueryPauseSec','forceInputChannelCounts','GainFactor', ...
    'FSelAux','AnOutINSource','AnOutChan','AnOutGain','IN_Active', ...
    'Mode','Gain','HRES','HPF','FsampCode'};
for fieldIdx = 1:numel(requiredCfg)
    if ~isfield(cfg,requiredCfg{fieldIdx})
        error('cfg.%s is missing.',requiredCfg{fieldIdx});
    end
end
end

%% Prepare covariance, normalization, and classification parameters
function [exFactor,iReSIG,normval,centroid] = prepare_online_parameters( ...
        EMG,EMGmask,MUFilters,fsamp,nbextchan)

EMG = EMG(~EMGmask,:);
exFactor = round(nbextchan/size(EMG,1));
eSIG = demean(extend(EMG,exFactor));
ReSIG = eSIG*eSIG'/size(eSIG,2);
iReSIG = pinv(ReSIG);

nMU = size(MUFilters,2);
normval = zeros(1,nMU);
centroid = zeros(nMU,2);

for mu = 1:nMU
    pulseTrain = (MUFilters(:,mu)'*iReSIG)*eSIG;
    pulseTrain = pulseTrain(1:size(EMG,2));
    pulseTrain = pulseTrain.*abs(pulseTrain);

    [~,peaks] = findpeaks(pulseTrain, ...
        'MinPeakDistance',round(fsamp*0.02));
    if numel(peaks) < 3
        error('MU %d produced fewer than three calibration peaks.',mu);
    end

    [labels,centers] = kmeans(pulseTrain(peaks)',2);
    [~,spikeClass] = max(centers);
    spikePeaks = peaks(labels == spikeClass);
    noisePeaks = peaks(labels ~= spikeClass);

    outlierLimit = mean(pulseTrain(spikePeaks)) + ...
        3*std(pulseTrain(spikePeaks));
    spikePeaks(pulseTrain(spikePeaks) > outlierLimit) = [];
    if isempty(spikePeaks) || isempty(noisePeaks)
        error('MU %d could not form separate spike and noise classes.',mu);
    end

    strongestSpikeCount = min(10,numel(spikePeaks));
    normval(mu) = mean(maxk(pulseTrain(spikePeaks), ...
        strongestSpikeCount));
    if ~isfinite(normval(mu)) || normval(mu) <= 0
        error('MU %d produced an invalid pulse-train normalization.',mu);
    end

    % Preserve the established classifier scaling: the projection itself
    % uses the spike normalization above, while cluster centroids use the
    % ten strongest preliminary peaks from both classes.
    strongestPeakCount = min(10,numel(peaks));
    classifierScale = mean(maxk(pulseTrain(peaks),strongestPeakCount));
    normalizedPulseTrain = pulseTrain/classifierScale;
    centroid(mu,1) = mean(normalizedPulseTrain(noisePeaks));
    centroid(mu,2) = mean(normalizedPulseTrain(spikePeaks));
end

end

%% Plot initialization and live update helpers
function [fig, plotState] = init_live_figure(nMU, cfg, sharedUI)
colors = lines(nMU);

fig = figure( ...
    'Color', 'w', ...
    'Position', [180 100 1050 650], ...
    'Name', 'Real-Time Discharge Rate', ...
    'CloseRequestFcn', @stop_figure);
setappdata(fig, 'stopRequested', false);

axRaster = sharedUI.axRaster;
cla(axRaster);
hold(axRaster, 'on');
grid(axRaster, 'on');
title(axRaster, 'Live Spike Trains', 'FontSize', 11);
xlabel(axRaster, 'Time (s)');
ylabel(axRaster, 'Motor Unit');
ylim(axRaster, [0 nMU + 1]);
yticks(axRaster, 1:nMU);
yticklabels(axRaster, arrayfun(@(x) sprintf('MU%d  (0 spikes)', x), 1:nMU, 'UniformOutput', false));

axFr = axes('Parent',fig,'Units','normalized', ...
    'Position',[0.08 0.12 0.82 0.80]);
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
    'Callback', @(~,~) request_stop(fig));

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

function request_stop(fig)
if ishghandle(fig)
    setappdata(fig, 'stopRequested', true);
end
end

function stop_figure(fig, ~)
setappdata(fig, 'stopRequested', true);
delete(fig);
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
        warning(ME.identifier,'Firmware query skipped: %s',ME.message);
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
        warning(ME.identifier,'Battery query skipped: %s',ME.message);
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
    % Each HRES sample arrives as [highWord,lowWord]. MATLAB typecast on
    % this little-endian system expects [lowWord,highWord].
    linearValues = reshape( ...
        Data(dev.Ptr_IN(inputIdx):dev.Ptr_IN(inputIdx+1)-1,:),1,[]);
    wordPairs = reshape(linearValues,2,[]);
    reorderedWords = reshape(flipud(wordPairs),1,[]);
    int32Values = typecast(reorderedWords,'int32');

    % HRES has a conversion step four times smaller than 16-bit mode.
    hresGainFactor = gainFactor/4;
    EMG = hresGainFactor*double(reshape( ...
        int32Values,numCh,fsInput*nBaseCols/500));
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
