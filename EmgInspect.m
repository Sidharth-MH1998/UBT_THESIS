% Stand-alone Novecento+ EMG acquisition script.
% The recorded channels x samples matrix is stored in emgValues.
% record the emg and find bad channels, baseline noise and inspect the frequency spectrum.

%% 1. EMG quality-check settings

cfg.activeInputs = [1 2];             % Novecento inputs used for recording.
cfg.emgChannels = [1:64 71:134];      % Channels retained from the stacked inputs.
cfg.previewChannels = 1:8:128;        % Retained-channel indices shown in the plot.
cfg.blockDurationSec = 1;             % Amount of data read on each loop, in seconds.
cfg.visibleWindowSec = 15;            % Duration shown in the moving plot, in seconds.
cfg.recordDurationSec = 60;           % USER SETTING: total recording time in seconds.

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
cfg.HRES(activeInputs) = 1;      % Acquire active inputs using 32-bit resolution.
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

%% 7. Calculate and display RMS for every recorded EMG channel

channelRMS = sqrt(mean(double(emgValues).^2, 2));

fprintf('\nRMS values for all recorded EMG channels:\n');
fprintf('Recorded row\tSource channel\tRMS\n');
for channelIdx = 1:numel(channelRMS)
    fprintf('%d\t\t%d\t\t%.6f\n', channelIdx, ...
        cfg.emgChannels(channelIdx), channelRMS(channelIdx));
end

%% 8. Close the live plot, then show the power spectra

if isgraphics(qualityFigure)
    title(qualityAxes, ...
        'Recording complete - close this window to show the power spectra');
    drawnow;
    waitfor(qualityFigure);
end

previewLabels = cfg.emgChannels(cfg.previewChannels);
plotPowerSpectrum(emgValues(cfg.previewChannels, :), ...
    previewLabels, samplingFrequency);


%% Local function: plot all preview-channel power spectra

function plotPowerSpectrum(previewData, channelLabels, fs)

% Remove the channel means so DC offsets do not dominate the spectrum.
spectrumData = double(previewData);
spectrumData = spectrumData - mean(spectrumData, 2);

% Calculate a one-sided power spectral density using the complete recording.
nSamples = size(spectrumData, 2);
nFft = 2^nextpow2(nSamples);
fftValues = fft(spectrumData, nFft, 2);
nPositive = floor(nFft / 2) + 1;
powerDensity = abs(fftValues(:, 1:nPositive)).^2 / (fs * nSamples);

if nPositive > 2
    powerDensity(:, 2:end-1) = 2 * powerDensity(:, 2:end-1);
end

frequencyHz = (0:nPositive - 1) * fs / nFft;
powerDb = 10 * log10(powerDensity + eps);

figure('Name', 'Preview-channel EMG power spectra', ...
    'NumberTitle', 'off', 'Color', 'w');
plot(frequencyHz, powerDb', 'LineWidth', 0.8);
grid on;
xlabel('Frequency (Hz)');
ylabel('Power spectral density (dB/Hz)');
title('Power spectra of all previewed EMG channels');
xlim([0 fs / 2]);

legendLabels = arrayfun(@(channel) sprintf('Channel %d', channel), ...
    channelLabels, 'UniformOutput', false);
legend(legendLabels, 'Location', 'eastoutside');

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
    else
        decoded = reshape(typecast(linearValues, 'int32'), ...
            dev.NumChan(inputIdx), nSamples);
    end
    blocks{listIdx} = dev.cfg.GainFactor * double(decoded);
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
