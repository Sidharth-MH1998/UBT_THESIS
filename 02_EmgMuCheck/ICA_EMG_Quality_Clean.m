%% ICA-based EMG quality assessment and artifact removal
% First load your MAT file, then assign its channels-by-samples matrix to
% emgData in the USER SETTINGS section below. Do not use clearvars here,
% because it would erase the loaded data.

%% USER SETTINGS
emgData = recordedEMG;      % Change recordedEMG to your loaded variable name
samplingRate = 2000;        % Hz

bandpassHz = [20 450];      % Set [] to disable; upper edge is clipped to Nyquist
lineFrequencyHz = 50;       % 50 in Europe, 60 in North America
restIntervalSec = [];       % Example: [0 2]; [] if no known rest interval
activeIntervalSec = [];     % Example: [3 8]; [] if no known contraction interval

automaticRejection = true;
manualRejectComponents = [];% Example: [4 11]; added to automatic rejection
randomSeed = 1;
maxIterations = 1000;
convergenceTolerance = 1e-6;

outputMatFile = 'ica_cleaned_emg.mat';
saveResults = true;

%% Validate and preprocess
if ~isnumeric(emgData) || ~ismatrix(emgData) || isempty(emgData)
    error('EMG data must be a non-empty numeric channels-by-samples matrix.');
end
if size(emgData, 1) > size(emgData, 2)
    error(['Data has more rows than columns. Transpose it so its shape is ' ...
        'channels x samples.']);
end
if samplingRate <= 0 || ~isscalar(samplingRate)
    error('samplingRate must be a positive scalar.');
end

rawEMG = double(emgData);
if any(~isfinite(rawEMG), 'all')
    error('EMG contains NaN or Inf values. Repair/remove them before ICA.');
end

channelStd = std(rawEMG, 0, 2);
validChannels = channelStd > max(channelStd) * 1e-10;
if nnz(validChannels) < 2
    error('ICA requires at least two non-flat channels.');
end
if any(~validChannels)
    warning('Ignoring flat channels: %s', mat2str(find(~validChannels)'));
end

processedEMG = rawEMG(validChannels, :);
processedEMG = processedEMG - mean(processedEMG, 2);

if ~isempty(bandpassHz)
    highEdge = min(bandpassHz(2), 0.95 * samplingRate / 2);
    if bandpassHz(1) >= highEdge
        error('Invalid bandpass for sampling rate %.1f Hz.', samplingRate);
    end
    [bBand, aBand] = butter(4, [bandpassHz(1) highEdge] / ...
        (samplingRate / 2), 'bandpass');
    processedEMG = filtfilt(bBand, aBand, processedEMG')';
end

%% Run symmetric FastICA
[components, mixingMatrix, unmixingMatrix, componentMean] = ...
    localFastICA(processedEMG, randomSeed, maxIterations, ...
    convergenceTolerance);

%% Score components
numberOfComponents = size(components, 1);
lowFrequencyRatio = zeros(numberOfComponents, 1);
lineNoiseRatio = zeros(numberOfComponents, 1);
excessKurtosis = zeros(numberOfComponents, 1);
activeRestDb = nan(numberOfComponents, 1);

restSamples = localIntervalToSamples(restIntervalSec, samplingRate, ...
    size(components, 2));
activeSamples = localIntervalToSamples(activeIntervalSec, samplingRate, ...
    size(components, 2));

for componentIndex = 1:numberOfComponents
    component = components(componentIndex, :);
    [powerSpectrum, frequencyHz] = periodogram(component, [], [], samplingRate);
    totalPower = sum(powerSpectrum) + eps;
    lowFrequencyRatio(componentIndex) = ...
        sum(powerSpectrum(frequencyHz < 20)) / totalPower;

    lineMask = false(size(frequencyHz));
    harmonicHz = lineFrequencyHz:lineFrequencyHz:(samplingRate / 2);
    for harmonicIndex = 1:numel(harmonicHz)
        lineMask = lineMask | abs(frequencyHz - harmonicHz(harmonicIndex)) <= 1;
    end
    lineNoiseRatio(componentIndex) = sum(powerSpectrum(lineMask)) / totalPower;
    excessKurtosis(componentIndex) = kurtosis(component) - 3;

    if ~isempty(restSamples) && ~isempty(activeSamples)
        restPower = mean(component(restSamples).^2) + eps;
        activePower = mean(component(activeSamples).^2) + eps;
        activeRestDb(componentIndex) = 10 * log10(activePower / restPower);
    end
end

% Conservative rules: obvious narrow-band, low-frequency, or impulsive sources.
automaticRejectComponents = [];
if automaticRejection
    automaticRejectComponents = find(lineNoiseRatio > 0.35 | ...
        lowFrequencyRatio > 0.60 | excessKurtosis > 20)';
end
rejectComponents = unique([automaticRejectComponents, ...
    manualRejectComponents(:)']);
rejectComponents = rejectComponents(rejectComponents >= 1 & ...
    rejectComponents <= numberOfComponents);

componentScores = table((1:numberOfComponents)', lowFrequencyRatio, ...
    lineNoiseRatio, excessKurtosis, activeRestDb, ...
    ismember((1:numberOfComponents)', rejectComponents), ...
    'VariableNames', {'Component','LowFrequencyRatio','LineNoiseRatio', ...
    'ExcessKurtosis','ActiveRestDb','Rejected'});
disp(componentScores);

%% Remove rejected components and reconstruct channels
cleanComponents = components;
cleanComponents(rejectComponents, :) = 0;
cleanValidEMG = mixingMatrix * cleanComponents + componentMean;

cleanedEMG = rawEMG;
cleanedEMG(validChannels, :) = cleanValidEMG;

removedVariancePercent = 100 * (1 - var(cleanValidEMG, 0, 2) ./ ...
    max(var(processedEMG, 0, 2), eps));
removedVariancePercent = max(0, min(100, removedVariancePercent));

fprintf('\nRejected ICA components: %s\n', mat2str(rejectComponents));
fprintf('Median removed channel variance: %.2f %%\n', ...
    median(removedVariancePercent));

%% Diagnostic plots
localPlotComponents(components, samplingRate, componentScores);
localPlotBeforeAfter(rawEMG(validChannels, :), cleanValidEMG, samplingRate);

%% Save outputs
if saveResults
    save(outputMatFile, 'cleanedEMG', 'processedEMG', 'components', ...
        'cleanComponents', 'mixingMatrix', 'unmixingMatrix', ...
        'componentScores', 'rejectComponents', 'validChannels', ...
        'removedVariancePercent', 'samplingRate', '-v7.3');
    fprintf('Saved results to %s\n', outputMatFile);
end

%% Local functions
function sampleIndices = localIntervalToSamples(intervalSec, fs, sampleCount)
if isempty(intervalSec)
    sampleIndices = [];
    return;
end
if numel(intervalSec) ~= 2 || intervalSec(1) < 0 || ...
        intervalSec(2) <= intervalSec(1)
    error('Intervals must have the form [startSec endSec].');
end
firstSample = max(1, floor(intervalSec(1) * fs) + 1);
lastSample = min(sampleCount, ceil(intervalSec(2) * fs));
sampleIndices = firstSample:lastSample;
if isempty(sampleIndices)
    error('An interval lies outside the recording.');
end
end

function [sources, mixing, unmixing, dataMean] = localFastICA(data, seed, maxIter, tol)
dataMean = mean(data, 2);
centered = data - dataMean;
covariance = (centered * centered') / size(centered, 2);
[eigenvectors, eigenvaluesMatrix] = eig(covariance, 'vector');
[eigenvalues, order] = sort(real(eigenvaluesMatrix), 'descend');
eigenvectors = real(eigenvectors(:, order));
rankTolerance = max(eigenvalues) * max(size(data)) * eps;
keep = eigenvalues > rankTolerance;
eigenvalues = eigenvalues(keep);
eigenvectors = eigenvectors(:, keep);

whitening = diag(1 ./ sqrt(eigenvalues)) * eigenvectors';
dewhitening = eigenvectors * diag(sqrt(eigenvalues));
whitened = whitening * centered;
componentCount = size(whitened, 1);

rng(seed);
weights = localSymmetricDecorrelate(randn(componentCount));
for iteration = 1:maxIter
    oldWeights = weights;
    projection = weights * whitened;
    nonlinearity = tanh(projection);
    derivativeMean = mean(1 - nonlinearity.^2, 2);
    weights = (nonlinearity * whitened') / size(whitened, 2) - ...
        derivativeMean .* weights;
    weights = localSymmetricDecorrelate(weights);
    change = max(abs(abs(diag(weights * oldWeights')) - 1));
    if change < tol
        break;
    end
end
if iteration == maxIter
    warning('FastICA reached maxIterations without full convergence.');
end

unmixing = weights * whitening;
sources = unmixing * centered;
mixing = dewhitening * weights';
end

function decorrelated = localSymmetricDecorrelate(matrix)
[vectors, values] = eig(matrix * matrix', 'vector');
values = max(real(values), eps);
decorrelated = vectors * diag(1 ./ sqrt(values)) * vectors' * matrix;
end

function localPlotComponents(components, fs, scores)
componentCount = size(components, 1);
sampleCount = size(components, 2);
timeSec = (0:(sampleCount - 1)) / fs;
scale = max(6 * median(std(components, 0, 2)), eps);

figure('Color', 'w', 'Name', 'ICA components');
hold on;
for index = 1:componentCount
    color = [0.1 0.65 0.45];
    if scores.Rejected(index), color = [0.85 0.2 0.2]; end
    plot(timeSec, components(index, :) / scale + index, 'Color', color);
end
hold off;
xlabel('Time (s)'); ylabel('ICA component');
title('ICA components (red = rejected)');
yticks(1:componentCount); grid on; axis tight;
end

function localPlotBeforeAfter(before, after, fs)
channelCount = min(size(before, 1), 16);
sampleCount = size(before, 2);
timeSec = (0:(sampleCount - 1)) / fs;
scale = max(6 * median(std(before(1:channelCount, :), 0, 2)), eps);

figure('Color', 'w', 'Name', 'EMG before and after ICA');
subplot(2, 1, 1); hold on;
for index = 1:channelCount
    plot(timeSec, before(index, :) / scale + index);
end
hold off; title('Before ICA cleaning'); ylabel('Channel'); grid on; axis tight;

subplot(2, 1, 2); hold on;
for index = 1:channelCount
    plot(timeSec, after(index, :) / scale + index);
end
hold off; title('After ICA cleaning'); xlabel('Time (s)');
ylabel('Channel'); grid on; axis tight;
end
