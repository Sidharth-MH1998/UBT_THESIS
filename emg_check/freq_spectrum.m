%% EMG frequency-spectrum analysis
% Put the channels-by-samples EMG matrix in emgData.
% Welch's method is used to obtain a stable power spectral density (PSD).

emgData = trimmedEMG;
samplingRate = 2000;

channelsToAnalyse = [1]; % [] analyses all channels
analysisWindowSec = Inf;  % Inf uses the full recording
maximumFrequency = 700;   % Hz; automatically limited to Nyquist
lineFrequency = 50;       % Hz; set [] to hide line-noise markers

%% Validate and select the data
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
    channelsToAnalyse >= 1 & channelsToAnalyse <= numberOfChannels & ...
    channelsToAnalyse == round(channelsToAnalyse));

if isempty(channelsToAnalyse)
    error('No valid channels selected in channelsToAnalyse.');
end

analysisSamples = numberOfSamples;
if isfinite(analysisWindowSec)
    analysisSamples = min(numberOfSamples, ...
        max(1, round(analysisWindowSec * samplingRate)));
end

selectedEMG = double(emgData(channelsToAnalyse, 1:analysisSamples));
selectedEMG = selectedEMG - mean(selectedEMG, 2); % remove DC offset

nyquistFrequency = samplingRate / 2;
plotMaximumFrequency = min(maximumFrequency, nyquistFrequency);

%% Estimate the power spectrum with Welch's method
% Use approximately one-second segments, with 50% overlap.
welchWindowSamples = min(analysisSamples, max(8, round(samplingRate)));
welchWindow = hann(welchWindowSamples, 'periodic');
welchOverlap = floor(welchWindowSamples / 2);
nfft = max(2048, 2^nextpow2(welchWindowSamples));

numberOfSelectedChannels = numel(channelsToAnalyse);
powerSpectra = zeros(nfft / 2 + 1, numberOfSelectedChannels);

for ii = 1:numberOfSelectedChannels
    [powerSpectra(:, ii), frequencies] = pwelch( ...
        selectedEMG(ii, :), welchWindow, welchOverlap, ...
        nfft, samplingRate, 'onesided');
end

powerSpectraDb = 10 * log10(powerSpectra + eps);
meanPowerSpectrumDb = 10 * log10(mean(powerSpectra, 2) + eps);

fprintf('Analysed %d channel(s): %s\n', ...
    numberOfSelectedChannels, mat2str(channelsToAnalyse));
fprintf('Samples used: %d (%.3f seconds)\n', ...
    analysisSamples, analysisSamples / samplingRate);
fprintf('Frequency resolution: %.3f Hz\n', ...
    frequencies(2) - frequencies(1));

%% Plot each channel separately
numberOfColumns = min(4, numberOfSelectedChannels);
numberOfRows = ceil(numberOfSelectedChannels / numberOfColumns);

figure('Name', 'EMG frequency spectrum by channel', 'Color', 'w');
channelLayout = tiledlayout(numberOfRows, numberOfColumns, ...
    'TileSpacing', 'compact', 'Padding', 'compact');

for ii = 1:numberOfSelectedChannels
    ax = nexttile(channelLayout);
    plot(ax, frequencies, powerSpectraDb(:, ii), ...
        'Color', [0.05 0.35 0.75], 'LineWidth', 1);
    hold(ax, 'on');
    add_line_frequency_markers(ax, lineFrequency, plotMaximumFrequency);
    hold(ax, 'off');
    grid(ax, 'on');
    xlim(ax, [0 plotMaximumFrequency]);
    title(ax, sprintf('Channel %d', channelsToAnalyse(ii)));
    xlabel(ax, 'Frequency (Hz)');
    ylabel(ax, 'Power (dB/Hz)');
end

title(channelLayout, 'EMG power spectra');

%% Plot the mean spectrum across selected channels
figure('Name', 'Mean EMG frequency spectrum', 'Color', 'w');
meanAxis = axes;
plot(meanAxis, frequencies, meanPowerSpectrumDb, ...
    'Color', [0.8 0.15 0.1], 'LineWidth', 1.5);
hold(meanAxis, 'on');
add_line_frequency_markers(meanAxis, lineFrequency, plotMaximumFrequency);
hold(meanAxis, 'off');
grid(meanAxis, 'on');
xlim(meanAxis, [0 plotMaximumFrequency]);
xlabel(meanAxis, 'Frequency (Hz)');
ylabel(meanAxis, 'Mean power (dB/Hz)');
title(meanAxis, sprintf('Mean EMG spectrum across %d channels', ...
    numberOfSelectedChannels));

%% Local helper
function add_line_frequency_markers(ax, lineFrequency, maximumFrequency)

if isempty(lineFrequency) || ~isscalar(lineFrequency) || lineFrequency <= 0
    return;
end

harmonics = lineFrequency:lineFrequency:maximumFrequency;
for frequency = harmonics
    xline(ax, frequency, ':', 'Color', [0.55 0.55 0.55], ...
        'HandleVisibility', 'off');
end

end
