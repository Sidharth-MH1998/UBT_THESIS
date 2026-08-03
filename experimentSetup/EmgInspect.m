% Stand-alone Novecento+ EMG acquisition script.
% The recorded channels x samples matrix is stored in emgValues.
% record the emg and find bad channels, baseline noise and inspect the frequency spectrum.

%% 1. EMG quality-check settings

cfg.activeInputs = [1 2];             % Novecento inputs used for recording.
cfg.emgChannels = [1:64 71:134];      % Channels retained from the stacked inputs.
cfg.previewChannels = 1:8:128;         % Retained-channel indices shown in the plot.
cfg.blockDurationSec = 1;             % Amount of data read on each loop, in seconds.
cfg.visibleWindowSec = 15;            % Duration shown in the moving plot, in seconds.
cfg.recordDurationSec = 60;           % USER SETTING: total recording time in seconds.
cfg.spectrumMaximumHz = 700;          % Highest frequency displayed in the PSD plots.
cfg.lineFrequencyHz = 50;             % Power-line frequency used for harmonic markers.

%% 2. Device settings

cfg.socketTimeoutSec = 100;       % Maximum TCP read/write wait time in seconds.
cfg.GainFactor = 0.2861;          % Scale factor used to convert decoded EMG to mV.
cfg.FSelAux = 2;                  % AUX rate: 1=500, 2=2000, 3=4000, 4=8000 Hz.
cfg.AnOutINSource = 0;            % Analog-output source: 0 selects Novecento input 1.
cfg.AnOutChan = 1;                % Channel number routed to the analog output.
cfg.AnOutGain = bin2dec('00000000'); % Analog-output gain code: 0 means gain of 1.
cfg.hardwareQueryRetries = 3;     % Number of hardware-query attempts before failure.
cfg.hardwareQueryPauseSec = 0.2;  % Delay before each hardware query, in seconds.

activeInputs = cfg.activeInputs;
numBlocks = ceil(cfg.recordDurationSec / cfg.blockDurationSec);

%% 3. Novecento input configuration

cfg.IN_Active = zeros(10, 1); % Enable flag for each input: 0=off, 1=on.
cfg.Mode = zeros(10, 1);      % Acquisition mode code for each input; 0=standard mode.
cfg.Gain = zeros(10, 1);      % Hardware gain code for each input.
cfg.HRES = zeros(10, 1);      % Resolution flag for each input: 0=16-bit, 1=32-bit.
cfg.HPF = zeros(10, 1);       % High-pass filter flag for each input: 0=off, 1=on.
cfg.FsampCode = zeros(10, 1); % Sampling-rate code: 0=500, 1=2000, 2=4000, 3=8000 Hz.

cfg.IN_Active(activeInputs) = 1; % Enable all inputs listed in activeInputs.
cfg.Gain(activeInputs) = 1;      % Apply hardware gain code 1 to active inputs.
cfg.HRES(activeInputs) = 0;      % Acquire active inputs using 32-bit resolution.
cfg.HPF(activeInputs) = 1;       % Enable the hardware high-pass filter.
cfg.FsampCode(activeInputs) = 1; % Sample active inputs at 2000 Hz.

%% 4. Connect to the Novecento+

dev = connectNovecento(cfg);
disconnectDevice = onCleanup(@() disconnectNovecento(dev));

%% 5. Read and store EMG data

samplesPerBlock = round(dev.fsInput(activeInputs(1)) * cfg.blockDurationSec);
samplingFrequency = dev.fsInput(activeInputs(1));
emgValues = [];

qualityFigure = figure('Name', 'Novecento EMG quality check', ...
    'NumberTitle', 'off', 'Color', 'w');
qualityAxes = axes('Parent', qualityFigure);

for blockIdx = 1:numBlocks
    allInputChannels = readEmgBlock(dev, activeInputs, samplesPerBlock);

    if max(cfg.emgChannels) > size(allInputChannels, 1)
        error(['cfg.emgChannels requests channel %d, but the active inputs ' ...
            'provide only %d stacked channels.'], ...
            max(cfg.emgChannels), size(allInputChannels, 1));
    end

    emgBlock = allInputChannels(cfg.emgChannels, :);
    emgValues = [emgValues, emgBlock]; %#ok<AGROW>

    if max(cfg.previewChannels) > size(emgValues, 1)
        error(['cfg.previewChannels requests retained-channel index %d, ' ...
            'but emgValues contains only %d channels.'], ...
            max(cfg.previewChannels), size(emgValues, 1));
    end

    if isgraphics(qualityFigure)
        previewLabels = cfg.emgChannels(cfg.previewChannels);
        plotQualityPreview(qualityAxes, ...
            emgValues(cfg.previewChannels, :), previewLabels, ...
            samplingFrequency, cfg.visibleWindowSec);
        title(qualityAxes, sprintf('EMG quality check: %.0f / %.0f seconds', ...
            size(emgValues, 2) / samplingFrequency, cfg.recordDurationSec));
        drawnow;
    end
end

%% 6. Stop streaming and disconnect

clear disconnectDevice dev;

fprintf('Recording complete: %d channels, %.1f seconds, %.0f Hz.\n', ...
    size(emgValues, 1), size(emgValues, 2) / samplingFrequency, ...
    samplingFrequency);

%% 7. Calculate and plot RMS for every recorded EMG channel

channelRMS = sqrt(mean(double(emgValues).^2, 2));
plotChannelRMS(channelRMS);

%% 8. Close the live plot, then show the power spectra

if isgraphics(qualityFigure)
    title(qualityAxes, ...
        'Recording complete - close this window to show the power spectra');
    drawnow;
    waitfor(qualityFigure);
end

previewLabels = cfg.emgChannels(cfg.previewChannels);
plotPowerSpectrum(emgValues(cfg.previewChannels, :), ...
    previewLabels, samplingFrequency, cfg.spectrumMaximumHz, ...
    cfg.lineFrequencyHz);


%% Local function: plot RMS for both 64-channel grids

function plotChannelRMS(channelRMS)

figure('Name', 'Recorded-channel RMS', ...
    'NumberTitle', 'off', 'Color', 'w');

subplot(2, 1, 1);
bar(1:64, channelRMS(1:64));
grid on;
xlabel('Input 1 EMG channel');
ylabel('RMS');
title('Input 1: RMS of channels 1-64');
xlim([0.5 64.5]);

subplot(2, 1, 2);
bar(1:64, channelRMS(65:128));
grid on;
xlabel('Input 2 EMG channel');
ylabel('RMS');
title('Input 2: RMS of channels 1-64');
xlim([0.5 64.5]);

end


%% Local function: plot all preview-channel power spectra

function plotPowerSpectrum(previewData, channelLabels, fs, maximumHz, lineHz)

% Remove DC offsets before estimating the spectra.
spectrumData = double(previewData);
spectrumData = spectrumData - mean(spectrumData, 2);

% Welch settings from freq_spectrum.m: one-second Hann windows and 50% overlap.
nSamples = size(spectrumData, 2);
welchWindowSamples = min(nSamples, max(8, round(fs)));
welchWindow = hann(welchWindowSamples, 'periodic');
welchOverlap = floor(welchWindowSamples / 2);
nFft = max(2048, 2^nextpow2(welchWindowSamples));

nChannels = size(spectrumData, 1);
powerDensity = zeros(nFft / 2 + 1, nChannels);
for channelIdx = 1:nChannels
    [powerDensity(:, channelIdx), frequencyHz] = pwelch( ...
        spectrumData(channelIdx, :), welchWindow, welchOverlap, ...
        nFft, fs, 'onesided');
end

powerDb = 10 * log10(powerDensity + eps);
plotMaximumHz = min(maximumHz, fs / 2);

% Plot every previewed channel separately in one tiled figure.
spectrumFigure = figure('Name', 'Preview-channel EMG power spectra', ...
    'NumberTitle', 'off', 'Color', 'w');
numberOfColumns = min(4, nChannels);
numberOfRows = ceil(nChannels / numberOfColumns);
spectrumLayout = tiledlayout(spectrumFigure, numberOfRows, numberOfColumns, ...
    'TileSpacing', 'compact', 'Padding', 'compact');

for channelIdx = 1:nChannels
    spectrumAxes = nexttile(spectrumLayout);
    plot(spectrumAxes, frequencyHz, powerDb(:, channelIdx), ...
        'Color', [0.05 0.35 0.75], 'LineWidth', 1);
    hold(spectrumAxes, 'on');
    addLineFrequencyMarkers(spectrumAxes, lineHz, plotMaximumHz);
    hold(spectrumAxes, 'off');
    grid(spectrumAxes, 'on');
    xlim(spectrumAxes, [0 plotMaximumHz]);
    title(spectrumAxes, sprintf('Channel %d', channelLabels(channelIdx)));
    xlabel(spectrumAxes, 'Frequency (Hz)');
    ylabel(spectrumAxes, 'Power (dB/Hz)');
end

title(spectrumLayout, 'EMG power spectra');

end


%% Local function: add power-line harmonic markers

function addLineFrequencyMarkers(ax, lineHz, maximumHz)

if isempty(lineHz) || ~isscalar(lineHz) || lineHz <= 0
    return;
end

for frequency = lineHz:lineHz:maximumHz
    xline(ax, frequency, ':', 'Color', [0.55 0.55 0.55], ...
        'HandleVisibility', 'off');
end

end


%% Local function: plot the most recent EMG window

function plotQualityPreview(ax, previewData, channelLabels, fs, windowSec)

windowSamples = round(windowSec * fs);
firstSample = max(1, size(previewData, 2) - windowSamples + 1);
visibleData = double(previewData(:, firstSample:end));
timeSec = ((firstSample:size(previewData, 2)) - 1) / fs;

channelSpread = std(visibleData, 0, 2);
traceOffset = max(6 * median(channelSpread(channelSpread > 0)), 1);
offsets = (0:size(visibleData, 1) - 1)' * traceOffset;

cla(ax);
plot(ax, timeSec, visibleData + offsets, 'LineWidth', 0.7);
grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Recorded channel');
yticks(ax, offsets);
yticklabels(ax, string(channelLabels));
ylim(ax, [-traceOffset, traceOffset * size(visibleData, 1)]);
xlim(ax, [max(0, timeSec(end) - windowSec), max(windowSec, timeSec(end))]);

end


%% Local function: connect and configure the Novecento+

function dev = connectNovecento(cfg)

% Device constants
auxFsamp = [0 16 32 48];
fsampVal = [500 2000 4000 8000];
sizeAux = [16 64 128 256];
channelsByProbeType = [0 14 22 38 46 70 102 0 0 0 0 0 0 0 0 0];

% Build the 15-byte configuration command
confString = zeros(1, 15, 'uint8');
confString(1) = uint8(128 + auxFsamp(cfg.FSelAux) + ...
    cfg.IN_Active(10) * 2 + cfg.IN_Active(9));

for inputIdx = 1:8
    confString(2) = uint8(double(confString(2)) + ...
        cfg.IN_Active(inputIdx) * 2^(inputIdx - 1));
end

confString(3) = uint8(cfg.AnOutGain + cfg.AnOutINSource);
confString(4) = uint8(cfg.AnOutChan);

for inputIdx = 1:10
    confString(4 + inputIdx) = uint8( ...
        cfg.Mode(inputIdx) * 64 + cfg.Gain(inputIdx) * 16 + ...
        cfg.HPF(inputIdx) * 8 + cfg.HRES(inputIdx) * 4 + ...
        cfg.FsampCode(inputIdx));
end
confString(15) = uint8(crc8(double(confString), 14));

% Open the TCP connection
tcpSocket = tcpclient('169.254.1.10', 23456);
tcpSocket.ByteOrder = "little-endian";
tcpSocket.Timeout = cfg.socketTimeoutSec;

% Request the connected probe configuration
settings = [];
lastError = [];
for attempt = 1:cfg.hardwareQueryRetries
    try
        flush(tcpSocket);
    catch
    end
    pause(cfg.hardwareQueryPauseSec);

    command = uint8([1 0]);
    command(2) = uint8(crc8(double(command(1)), 1));
    write(tcpSocket, command, 'uint8');

    try
        settings = read(tcpSocket, 20, 'uint8')';
        break;
    catch ME
        lastError = ME;
    end
end

if isempty(settings)
    clear tcpSocket;
    error('Hardware settings read failed: %s', lastError.message);
end
if settings(20) == 255
    clear tcpSocket;
    error('Hardware configuration request returned a CRC error.');
end

% Start streaming using the selected configuration
write(tcpSocket, confString, 'uint8');

% Calculate the packet layout for every input
numChan = zeros(10, 1);
ptrIn = ones(11, 1);
sizeIn = zeros(10, 1);
fsInput = zeros(10, 1);

for inputIdx = 1:10
    probeType = double(settings(inputIdx + 1));
    if probeType + 1 <= numel(channelsByProbeType)
        numChan(inputIdx) = channelsByProbeType(probeType + 1);
    end

    if numChan(inputIdx) == 0
        cfg.IN_Active(inputIdx) = 0;
    end

    if cfg.IN_Active(inputIdx) == 1
        fsInput(inputIdx) = fsampVal(cfg.FsampCode(inputIdx) + 1);
        sizeIn(inputIdx) = (cfg.HRES(inputIdx) + 1) * ...
            fsInput(inputIdx) / 500 * numChan(inputIdx);
    end
    ptrIn(inputIdx + 1) = ptrIn(inputIdx) + sizeIn(inputIdx);
end

% Set the TCP receive buffer
packetSize = ptrIn(11) - 1 + sizeAux(cfg.FSelAux) + 128;
try
    tcpSocket.InputBufferSize = max(packetSize * 500 * 4, 1e6);
catch
end

% Store connection information needed while reading
dev.tcpSocket = tcpSocket;
dev.cfg = cfg;
dev.ConfString = confString;
dev.PacketSize1Block = packetSize;
dev.NumChan = numChan;
dev.Ptr_IN = ptrIn;
dev.fsInput = fsInput;

end


%% Local function: read and decode one EMG block

function emg = readEmgBlock(dev, inputIdxList, samplesPerBlock)

% Determine how many complete packet columns to read
fsActive = dev.fsInput(inputIdxList(1));
nBaseCols = samplesPerBlock * 500 / fsActive;
if mod(nBaseCols, 1) ~= 0
    error('The block length does not map to complete Novecento packets.');
end
nBaseCols = round(nBaseCols);

% Read one raw block from the TCP connection
nRead = dev.PacketSize1Block * nBaseCols;
rawValues = read(dev.tcpSocket, nRead, 'int16')';
if numel(rawValues) ~= nRead
    error('Short read: expected %d values, received %d.', ...
    nRead, numel(rawValues));
end

% Extract and decode each selected input
packet = reshape(rawValues, dev.PacketSize1Block, nBaseCols);
blocks = cell(1, numel(inputIdxList));

for listIdx = 1:numel(inputIdxList)
    inputIdx = inputIdxList(listIdx);
    inputRows = dev.Ptr_IN(inputIdx):dev.Ptr_IN(inputIdx + 1) - 1;
    linearValues = reshape(packet(inputRows, :), 1, []);
    nSamples = dev.fsInput(inputIdx) * nBaseCols / 500;

    if dev.cfg.HRES(inputIdx) == 0
        decoded = reshape(linearValues, dev.NumChan(inputIdx), nSamples);
        blocks{listIdx} = dev.cfg.GainFactor * double(decoded);
    else
        % The probe sends [highWord, lowWord], but MATLAB typecast on this
        % little-endian system expects [lowWord, highWord].
        wordPairs = reshape(linearValues, 2, []);
        reorderedWords = reshape(flipud(wordPairs), 1, []);
        decoded = reshape(typecast(reorderedWords, 'int32'), ...
            dev.NumChan(inputIdx), nSamples);

        % HRES uses a conversion step four times smaller than 16-bit mode.
        blocks{listIdx} = (dev.cfg.GainFactor / 4) * double(decoded);
    end
end

% Store all selected inputs in one channels-by-samples matrix
emg = vertcat(blocks{:});

end


%% Local function: stop streaming

function disconnectNovecento(dev)

try
    stopString = dev.ConfString;
    stopString(1) = uint8(0);
    stopString(15) = uint8(crc8(double(stopString), 14));
    write(dev.tcpSocket, stopString, 'uint8');
    pause(0.5);
catch
end

end


%% Local function: calculate CRC-8

function crc = crc8(vector, len)

crc = 0;
for byteIdx = 1:len
    extract = vector(byteIdx);
    for bitIdx = 1:8
        bitSum = xor(mod(crc, 2), mod(extract, 2));
        crc = floor(crc / 2);
        if bitSum > 0
            crc = bitxor(crc, 140);
        end
        extract = floor(extract / 2);
    end
end

end
