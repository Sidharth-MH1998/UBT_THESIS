%% EMG frequency spectrum before and after filtering
% The EMG matrix must be channels x samples.

emgData = emgValues;
samplingRate = 2000; % Set this to the true recording sampling rate.

channelsToAnalyse = 1; % [] analyses all channels
analysisWindowSec = Inf;  % Inf uses the full recording
maximumFrequency = 700;   % Hz; automatically limited to Nyquist
lineFrequency = 50;       % Hz; set [] to hide harmonic markers

%% Same filtering settings used in preprocessfilter.m
useAdaptiveNotch = true;
baseFreqRange = [45 55];
numHarmonics = 9;
notchWidth = 1;

useBandpass = true;
emgtype = 1; % 1 = surface EMG, 2 = intramuscular EMG


%% Validate and select data
if ~isnumeric(emgData) || ~ismatrix(emgData) || isempty(emgData)
    error('emgData must be a non-empty numeric channels-by-samples matrix.');
end
if ~isscalar(samplingRate) || ~isfinite(samplingRate) || samplingRate <= 0
    error('samplingRate must be a positive finite scalar.');
end

[numberOfChannels, numberOfSamples] = size(emgData);

if isempty(channelsToAnalyse)
    channelsToAnalyse = 1:numberOfChannels;
end

channelsToAnalyse = unique(channelsToAnalyse(:).', 'stable');
channelsToAnalyse = channelsToAnalyse( ...
    channelsToAnalyse >= 1 & ...
    channelsToAnalyse <= numberOfChannels & ...
    channelsToAnalyse == round(channelsToAnalyse));

if isempty(channelsToAnalyse)
    error('No valid channels selected in channelsToAnalyse.');
end

analysisSamples = numberOfSamples;
if isfinite(analysisWindowSec)
    analysisSamples = min(numberOfSamples, ...
        max(1, round(analysisWindowSec * samplingRate)));
end

rawEMG = double(emgData(:, 1:analysisSamples));

%% Apply the preprocessing pipeline
filteredEMG = rawEMG;

if useAdaptiveNotch
    filteredEMG = adaptiveNotchFilter(filteredEMG, samplingRate, ...
        baseFreqRange, numHarmonics, notchWidth);
end

if useBandpass
    filteredEMG = bandpassingals(filteredEMG, samplingRate, emgtype);
end

%% Calculate matched Welch spectra before and after filtering
rawSelected = rawEMG(channelsToAnalyse, :);
filteredSelected = filteredEMG(channelsToAnalyse, :);

rawSelected = rawSelected - mean(rawSelected, 2);
filteredSelected = filteredSelected - mean(filteredSelected, 2);

welchWindowSamples = min(analysisSamples, max(8, round(samplingRate)));
welchWindow = hann(welchWindowSamples, 'periodic');
welchOverlap = floor(welchWindowSamples / 2);
nfft = max(2048, 2^nextpow2(welchWindowSamples));

numberOfSelectedChannels = numel(channelsToAnalyse);
rawPower = zeros(nfft / 2 + 1, numberOfSelectedChannels);
filteredPower = zeros(size(rawPower));

for ii = 1:numberOfSelectedChannels
    [rawPower(:, ii), frequencies] = pwelch( ...
        rawSelected(ii, :), welchWindow, welchOverlap, ...
        nfft, samplingRate, 'onesided');
    filteredPower(:, ii) = pwelch( ...
        filteredSelected(ii, :), welchWindow, welchOverlap, ...
        nfft, samplingRate, 'onesided');
end

rawPowerDb = 10 * log10(rawPower + eps);
filteredPowerDb = 10 * log10(filteredPower + eps);
meanRawPowerDb = 10 * log10(mean(rawPower, 2) + eps);
meanFilteredPowerDb = 10 * log10(mean(filteredPower, 2) + eps);

plotMaximumFrequency = min(maximumFrequency, samplingRate / 2);

fprintf('Analysed %d channel(s): %s\n', ...
    numberOfSelectedChannels, mat2str(channelsToAnalyse));
fprintf('Samples used: %d (%.3f seconds)\n', ...
    analysisSamples, analysisSamples / samplingRate);
fprintf('Frequency resolution: %.3f Hz\n', ...
    frequencies(2) - frequencies(1));

%% Plot before and after together for every channel
numberOfColumns = min(4, numberOfSelectedChannels);
numberOfRows = ceil(numberOfSelectedChannels / numberOfColumns);

figure('Name', 'EMG spectra before and after filtering', 'Color', 'w');
channelLayout = tiledlayout(numberOfRows, numberOfColumns, ...
    'TileSpacing', 'compact', 'Padding', 'compact');

for ii = 1:numberOfSelectedChannels
    ax = nexttile(channelLayout);
    plot(ax, frequencies, rawPowerDb(:, ii), ...
        'Color', [0.1 0.4 0.8], 'LineWidth', 1, ...
        'DisplayName', 'Before');
    hold(ax, 'on');
    plot(ax, frequencies, filteredPowerDb(:, ii), ...
        'Color', [0.85 0.2 0.1], 'LineWidth', 1, ...
        'DisplayName', 'After');
    add_line_frequency_markers(ax, lineFrequency, plotMaximumFrequency);
    hold(ax, 'off');
    grid(ax, 'on');
    xlim(ax, [0 plotMaximumFrequency]);
    title(ax, sprintf('Channel %d', channelsToAnalyse(ii)));
    xlabel(ax, 'Frequency (Hz)');
    ylabel(ax, 'Power (dB/Hz)');
    if ii == 1
        legend(ax, 'Location', 'best');
    end
end

title(channelLayout, 'EMG spectra before and after filtering');

%% Plot mean spectrum across selected channels
figure('Name', 'Mean EMG spectrum before and after filtering', 'Color', 'w');
meanAxis = axes;
plot(meanAxis, frequencies, meanRawPowerDb, ...
    'Color', [0.1 0.4 0.8], 'LineWidth', 1.5, ...
    'DisplayName', 'Before');
hold(meanAxis, 'on');
plot(meanAxis, frequencies, meanFilteredPowerDb, ...
    'Color', [0.85 0.2 0.1], 'LineWidth', 1.5, ...
    'DisplayName', 'After');
add_line_frequency_markers(meanAxis, lineFrequency, plotMaximumFrequency);
hold(meanAxis, 'off');
grid(meanAxis, 'on');
xlim(meanAxis, [0 plotMaximumFrequency]);
xlabel(meanAxis, 'Frequency (Hz)');
ylabel(meanAxis, 'Mean power (dB/Hz)');
title(meanAxis, sprintf('Mean spectrum across %d channels', ...
    numberOfSelectedChannels));
legend(meanAxis, 'Location', 'best');

%% Local helper
function add_line_frequency_markers(ax, lineFrequency, maximumFrequency)

if isempty(lineFrequency) || ~isscalar(lineFrequency) || lineFrequency <= 0
    return;
end

for frequency = lineFrequency:lineFrequency:maximumFrequency
    xline(ax, frequency, ':', 'Color', [0.55 0.55 0.55], ...
        'HandleVisibility', 'off');
end

end
