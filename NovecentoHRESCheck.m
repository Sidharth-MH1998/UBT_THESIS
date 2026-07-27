% NOVECENTOHRESCHECK
% Stand-alone diagnostic based on the official Novecento+ v3.0 routine.
%
% Run this file once with hresMode = 0 and once with hresMode = 1.
% IMPORTANT: power-cycle the Novecento+ before each run. Allow this script
% to finish normally so that it sends the stop-streaming command.

clear;
close all;

%% User settings

hresMode = 0;          % 0 = 16-bit transfer; 1 = high-resolution transfer.
activeInput = 1;       % Test only one Bio64-HD input to isolate the format.
recordDurationSec = 5; % Short diagnostic recording.
edgeDiscardSec = 1;    % Ignore startup and ending transients in statistics.

%% Official device settings

ipAddress = '169.254.1.10';
tcpPort = 23456;
socketTimeoutSec = 100;

gainFactor = 0.2861;
fSelAux = 2;

inActive = zeros(10, 1);
modeCode = zeros(10, 1);
gainCode = zeros(10, 1);
hresCode = zeros(10, 1);
hpfCode = zeros(10, 1);
fsampCode = zeros(10, 1);

inActive(activeInput) = 1;
modeCode(activeInput) = 0;
gainCode(activeInput) = 1;
hresCode(activeInput) = hresMode;
hpfCode(activeInput) = 1;
fsampCode(activeInput) = 1; % 2000 Hz

auxFsamp = [0 16 32 48];
fsampValues = [500 2000 4000 8000];
sizeAux = [16 64 128 256];
channelsByProbeType = [0 14 22 38 46 70 102 0 0 0 0 0 0 0 0 0];

%% Build the official configuration string

confString = zeros(1, 15, 'uint8');
confString(1) = uint8(128 + auxFsamp(fSelAux) + ...
    inActive(10) * 2 + inActive(9));

for inputIdx = 1:8
    confString(2) = uint8(double(confString(2)) + ...
        inActive(inputIdx) * 2^(inputIdx - 1));
end

confString(3) = uint8(0); % Analog output gain + source.
confString(4) = uint8(1); % Analog output channel.

for inputIdx = 1:10
    confString(4 + inputIdx) = uint8( ...
        modeCode(inputIdx) * 64 + gainCode(inputIdx) * 16 + ...
        hpfCode(inputIdx) * 8 + hresCode(inputIdx) * 4 + ...
        fsampCode(inputIdx));
end
confString(15) = uint8(crc8Official(double(confString), 14));

%% Connect and query the hardware

tcpSocket = tcpclient(ipAddress, tcpPort);
tcpSocket.ByteOrder = "little-endian";
tcpSocket.Timeout = socketTimeoutSec;

stopGuard = onCleanup(@() stopNovecentoCheck(tcpSocket, confString));

hardwareCommand = uint8([1 0]);
hardwareCommand(2) = uint8(crc8Official(double(hardwareCommand(1)), 1));
write(tcpSocket, hardwareCommand, 'uint8');
settings = read(tcpSocket, 20, 'uint8')';

if numel(settings) ~= 20
    error('Expected a 20-byte hardware response, but received %d bytes.', ...
        numel(settings));
end
if settings(20) == 255
    error('The hardware query returned a CRC error.');
end

%% Calculate the packet layout using the official formula

numChannels = zeros(10, 1);
ptrInput = zeros(11, 1);
sizeInput = zeros(10, 1);
ptrInput(1) = 1;

for inputIdx = 1:10
    probeType = double(settings(inputIdx + 1));
    if probeType + 1 <= numel(channelsByProbeType)
        numChannels(inputIdx) = channelsByProbeType(probeType + 1);
    end

    if numChannels(inputIdx) == 0
        inActive(inputIdx) = 0;
    end

    if inActive(inputIdx) == 1
        sizeInput(inputIdx) = (hresCode(inputIdx) + 1) * ...
            fsampValues(fsampCode(inputIdx) + 1) / 500 * ...
            numChannels(inputIdx);
    end
    ptrInput(inputIdx + 1) = ptrInput(inputIdx) + sizeInput(inputIdx);
end

if numChannels(activeInput) == 0
    error('No supported probe was detected on input %d.', activeInput);
end

packetSizeOneColumn = ptrInput(11) - 1 + sizeAux(fSelAux) + 128;
samplingFrequency = fsampValues(fsampCode(activeInput) + 1);
nBaseColumns = 500 * recordDurationSec;
nRead = packetSizeOneColumn * nBaseColumns;

fprintf('\nNovecento+ HRES diagnostic\n');
fprintf('HRES mode:                 %d\n', hresMode);
fprintf('Detected probe type code:  %d\n', settings(activeInput + 1));
fprintf('Detected transmitted ch.:  %d\n', numChannels(activeInput));
fprintf('Input configuration byte:  %d\n', confString(4 + activeInput));
fprintf('Packet size (int16/column): %d\n', packetSizeOneColumn);
fprintf('Sampling frequency:        %d Hz\n', samplingFrequency);
fprintf('Recording duration:        %.1f s\n\n', recordDurationSec);

%% Start, read and decode exactly as in the official routine

write(tcpSocket, confString, 'uint8');

rawWords = read(tcpSocket, nRead, 'int16')';
if numel(rawWords) ~= nRead
    error('Short read: expected %d int16 words, received %d.', ...
        nRead, numel(rawWords));
end

packet = reshape(rawWords, packetSizeOneColumn, nBaseColumns);
inputRows = ptrInput(activeInput):ptrInput(activeInput + 1) - 1;
linearWords = reshape(packet(inputRows, :), 1, []);
nSamples = samplingFrequency * recordDurationSec;

if hresMode == 0
    decodedValues = int32(reshape(linearWords, ...
        numChannels(activeInput), nSamples));
else
    combinedValues = typecast(linearWords, 'int32');
    decodedValues = int32(reshape(combinedValues, ...
        numChannels(activeInput), nSamples));
end

convertedValues = gainFactor * double(decodedValues);
emgValues = convertedValues(1:min(64, size(convertedValues, 1)), :);

%% Report statistics after removing the first and last second

edgeSamples = round(edgeDiscardSec * samplingFrequency);
if 2 * edgeSamples >= nSamples
    error('edgeDiscardSec removes the complete diagnostic recording.');
end

qualityRange = edgeSamples + 1:nSamples - edgeSamples;
qualityEMG = emgValues(:, qualityRange);

channelMean = mean(qualityEMG, 2);
channelStd = std(qualityEMG, 0, 2);
channelRMS = sqrt(mean(qualityEMG.^2, 2));
channelMinimum = min(qualityEMG, [], 2);
channelMaximum = max(qualityEMG, [], 2);

fprintf('Statistics exclude the first and last %.1f second(s).\n', ...
    edgeDiscardSec);
fprintf('Channel 1 mean: %g\n', channelMean(1));
fprintf('Channel 1 STD:  %g\n', channelStd(1));
fprintf('Channel 1 RMS:  %g\n', channelRMS(1));
fprintf('Channel 1 min:  %g\n', channelMinimum(1));
fprintf('Channel 1 max:  %g\n', channelMaximum(1));
fprintf('All-channel decoded min: %g\n', min(qualityEMG(:)));
fprintf('All-channel decoded max: %g\n', max(qualityEMG(:)));

%% Plot channel 1 and RMS for all 64 EMG channels

qualityTime = (qualityRange - 1) / samplingFrequency;

figure('Name', sprintf('Novecento HRES=%d diagnostic', hresMode), ...
    'NumberTitle', 'off', 'Color', 'w');

subplot(2, 1, 1);
plot(qualityTime, qualityEMG(1, :));
grid on;
xlabel('Time (s)');
ylabel('Converted amplitude');
title(sprintf('Input %d, EMG channel 1, HRES=%d', ...
    activeInput, hresMode));

subplot(2, 1, 2);
bar(1:size(qualityEMG, 1), channelRMS);
grid on;
xlabel('EMG channel');
ylabel('RMS');
title('RMS after edge removal');
xlim([0.5 size(qualityEMG, 1) + 0.5]);

%% Preserve diagnostic results in one workspace structure

hresCheckResult = struct();
hresCheckResult.hresMode = hresMode;
hresCheckResult.settings = settings;
hresCheckResult.confString = confString;
hresCheckResult.numChannels = numChannels;
hresCheckResult.packetSizeOneColumn = packetSizeOneColumn;
hresCheckResult.samplingFrequency = samplingFrequency;
hresCheckResult.decodedValues = decodedValues;
hresCheckResult.emgValues = emgValues;
hresCheckResult.qualityEMG = qualityEMG;
hresCheckResult.channelMean = channelMean;
hresCheckResult.channelStd = channelStd;
hresCheckResult.channelRMS = channelRMS;
hresCheckResult.channelMinimum = channelMinimum;
hresCheckResult.channelMaximum = channelMaximum;

resultFile = sprintf('NovecentoHRESCheck_HRES%d.mat', hresMode);
save(resultFile, 'hresCheckResult');

clear stopGuard tcpSocket;
fprintf('\nDiagnostic completed and streaming stopped normally.\n');
fprintf('Results saved to %s\n', resultFile);


function stopNovecentoCheck(tcpSocket, confString)

try
    stopString = confString;
    stopString(1) = uint8(0);
    stopString(15) = uint8(crc8Official(double(stopString), 14));
    write(tcpSocket, stopString, 'uint8');
    pause(1);
catch
end

end


function crc = crc8Official(vector, len)

crc = 0;
byteIdx = 1;

while len > 0
    extract = vector(byteIdx);
    for bitIdx = 8:-1:1
        bitSum = xor(mod(crc, 2), mod(extract, 2));
        crc = floor(crc / 2);

        if bitSum > 0
            crc = bitxor(crc, 140);
        end

        extract = floor(extract / 2);
    end

    len = len - 1;
    byteIdx = byteIdx + 1;
end

end
