function diagnoseLiveNovecentoEMG(activeInput, channels)
%DIAGNOSELIVENOVECENTOEMG Monitor Novecento EMG quality in real time.
%
%   diagnoseLiveNovecentoEMG
%   diagnoseLiveNovecentoEMG(activeInput, channels)
%
% Defaults: input 1 and channels 1:64. Close the diagnostic window to stop.
% Run this monitor by itself; do not run it while another program is using
% the Novecento TCP connection.

    if nargin < 1 || isempty(activeInput)
        activeInput = 1;
    end
    if nargin < 2 || isempty(channels)
        channels = 1:64;
    end
    validateattributes(activeInput, {'numeric'}, ...
        {'scalar', 'integer', '>=', 1, '<=', 10});
    validateattributes(channels, {'numeric'}, ...
        {'vector', 'integer', 'positive'});

    scriptDirectory = fileparts(mfilename('fullpath'));
    repositoryDirectory = fileparts(scriptDirectory);
    addpath(fullfile(scriptDirectory, 'myStreamFunc'));
    addpath(fullfile(repositoryDirectory, 'StreamNovecento'));

    blockDurationSec = 0.02;
    updatePeriodSec = 0.5;
    analysisWindowSec = 5;
    displayWindowSec = 2;

    cfg = makeNovecentoConfig(blockDurationSec, activeInput, channels);
    fprintf('Connecting to Novecento input %d ...\n', activeInput);
    dev = novecento_connect(cfg);
    connectionCleanup = onCleanup(@() disconnectSafely(dev));

    fs = dev.fsInput(activeInput);
    availableChannels = dev.NumChan(activeInput);
    if fs <= 0
        error('Novecento input %d did not report a valid sample rate.', activeInput);
    end
    if any(channels > availableChannels)
        error('Input %d reports %d channels, but channel %d was requested.', ...
            activeInput, availableChannels, max(channels));
    end

    samplesPerBlock = round(fs * blockDurationSec);
    bufferSamples = round(fs * analysisWindowSec);
    emgBuffer = zeros(numel(channels), bufferSamples);
    writeIndex = 0;
    validSamples = 0;
    previousBlockEnd = [];
    previousBlock = [];
    boundaryJumps = [];
    repeatedBlocks = 0;
    totalBlocks = 0;

    [fig, timeAxes, spectrumAxes, statusText] = createLiveDiagnosticFigure();
    selectedRows = unique(round(linspace(1, numel(channels), ...
        min(8, numel(channels)))));
    lastUpdate = tic;

    fprintf(['Live diagnostic started at %.0f Hz with %d channels. ' ...
        'Close the window to stop.\n'], fs, numel(channels));

    while isgraphics(fig)
        rawBlock = novecento_read_emg_block(dev, activeInput, samplesPerBlock);
        block = double(rawBlock(channels, :));
        totalBlocks = totalBlocks + 1;

        if ~isempty(previousBlockEnd)
            boundaryJumps(end + 1) = median(abs(block(:, 1) - previousBlockEnd)); %#ok<AGROW>
        end
        previousBlockEnd = block(:, end);
        if ~isempty(previousBlock) && isequal(block, previousBlock)
            repeatedBlocks = repeatedBlocks + 1;
        end
        previousBlock = block;

        [emgBuffer, writeIndex, validSamples] = appendCircular( ...
            emgBuffer, writeIndex, validSamples, block);

        if toc(lastUpdate) >= updatePeriodSec && validSamples >= round(fs)
            window = readCircular(emgBuffer, writeIndex, validSamples);
            metrics = calculateLiveMetrics(window, fs, boundaryJumps, ...
                repeatedBlocks, totalBlocks);
            updateLiveDiagnosticPlots(timeAxes, spectrumAxes, statusText, ...
                window, fs, channels, selectedRows, displayWindowSec, metrics);
            drawnow limitrate;
            lastUpdate = tic;

            if numel(boundaryJumps) > 500
                boundaryJumps = boundaryJumps(end - 499:end);
            end
        else
            drawnow limitrate;
        end
    end

    clear connectionCleanup;
end

function [fig, timeAxes, spectrumAxes, statusText] = createLiveDiagnosticFigure()
    fig = figure('Name', 'Live Novecento EMG diagnostic', ...
        'NumberTitle', 'off', 'Color', 'w', 'Position', [80 80 1400 780]);
    timeAxes = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.06 0.10 0.57 0.83]);
    grid(timeAxes, 'on');
    xlabel(timeAxes, 'Time (s)');
    ylabel(timeAxes, 'Selected channels (offset)');
    title(timeAxes, 'Recent raw EMG');

    spectrumAxes = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.68 0.53 0.29 0.40]);
    grid(spectrumAxes, 'on');
    xlabel(spectrumAxes, 'Frequency (Hz)');
    ylabel(spectrumAxes, 'Median PSD');
    title(spectrumAxes, 'Median channel spectrum');

    statusText = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.68 0.08 0.29 0.38], 'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', 'FontName', 'Consolas', ...
        'FontSize', 10, 'String', 'Collecting data ...');
end

function [buffer, writeIndex, validSamples] = appendCircular( ...
        buffer, writeIndex, validSamples, block)
    capacity = size(buffer, 2);
    nNew = size(block, 2);
    if nNew >= capacity
        buffer = block(:, end - capacity + 1:end);
        writeIndex = capacity;
        validSamples = capacity;
        return;
    end
    indices = mod(writeIndex + (0:nNew - 1), capacity) + 1;
    buffer(:, indices) = block;
    writeIndex = indices(end);
    validSamples = min(capacity, validSamples + nNew);
end

function window = readCircular(buffer, writeIndex, validSamples)
    capacity = size(buffer, 2);
    firstIndex = mod(writeIndex - validSamples, capacity) + 1;
    indices = mod(firstIndex - 1 + (0:validSamples - 1), capacity) + 1;
    window = buffer(:, indices);
end

function metrics = calculateLiveMetrics(emg, fs, boundaryJumps, ...
        repeatedBlocks, totalBlocks)
    metrics.nonfiniteFraction = mean(~isfinite(emg(:)));
    emg(~isfinite(emg)) = 0;
    centered = emg - mean(emg, 2);
    channelStd = std(centered, 0, 2);
    flatThreshold = max(eps(max(abs(emg(:)))), eps);
    metrics.flatRows = find(channelStd <= flatThreshold).';
    metrics.zeroFraction = mean(emg(:) == 0);
    metrics.repeatedBlockFraction = repeatedBlocks / max(totalBlocks, 1);

    [metrics.frequency, metrics.medianPSD] = liveMedianPSD(centered, fs);
    emgBand = metrics.frequency >= 20 & ...
        metrics.frequency <= min(450, fs / 2);
    bandPower = sum(metrics.medianPSD(emgBand));
    bandPower = max(bandPower, eps);
    metrics.mains50Ratio = sum(metrics.medianPSD( ...
        metrics.frequency >= 49 & metrics.frequency <= 51)) / bandPower;
    metrics.mains60Ratio = sum(metrics.medianPSD( ...
        metrics.frequency >= 59 & metrics.frequency <= 61)) / bandPower;
    [~, peakIndex] = max(metrics.medianPSD(metrics.frequency >= 1));
    positiveFrequency = metrics.frequency(metrics.frequency >= 1);
    metrics.dominantFrequency = positiveFrequency(peakIndex);

    correlationInput = centered(:, 1:max(1, round(fs / 500)):end);
    correlationMatrix = corrcoef(correlationInput.');
    adjacent = diag(correlationMatrix, 1);
    metrics.adjacentCorrelation = median(adjacent, 'omitnan');

    commonMode = median(centered, 1);
    channelVariance = var(centered, 0, 2);
    residualVariance = var(centered - commonMode, 0, 2);
    valid = channelVariance > 0;
    metrics.commonModeFraction = median(max(0, 1 - ...
        residualVariance(valid) ./ channelVariance(valid)), 'omitnan');

    typicalJump = median(abs(diff(centered, 1, 2)), 'all', 'omitnan');
    if isempty(boundaryJumps) || typicalJump == 0
        metrics.boundaryJumpRatio = NaN;
    else
        metrics.boundaryJumpRatio = median(boundaryJumps, 'omitnan') / typicalJump;
    end
end

function [frequency, medianPSD] = liveMedianPSD(emg, fs)
    nFFT = min(size(emg, 2), max(512, round(2 * fs)));
    segment = emg(:, end - nFFT + 1:end);
    window = 0.5 - 0.5 * cos(2 * pi * (0:nFFT - 1) / (nFFT - 1));
    spectrum = fft(segment .* window, [], 2);
    positiveBins = 1:(floor(nFFT / 2) + 1);
    psd = abs(spectrum(:, positiveBins)).^2 / (fs * sum(window.^2));
    if numel(positiveBins) > 2
        psd(:, 2:end - 1) = 2 * psd(:, 2:end - 1);
    end
    medianPSD = median(psd, 1).';
    frequency = (positiveBins - 1).' * fs / nFFT;
end

function updateLiveDiagnosticPlots(timeAxes, spectrumAxes, statusText, ...
        emg, fs, channelLabels, selectedRows, displayWindowSec, metrics)
    displaySamples = min(size(emg, 2), round(displayWindowSec * fs));
    displayData = emg(selectedRows, end - displaySamples + 1:end);
    time = (0:displaySamples - 1) / fs;
    offset = max(median(std(displayData, 0, 2)) * 6, eps);

    cla(timeAxes);
    hold(timeAxes, 'on');
    for index = 1:numel(selectedRows)
        plot(timeAxes, time, displayData(index, :) + offset * (index - 1));
    end
    hold(timeAxes, 'off');
    grid(timeAxes, 'on');
    xlim(timeAxes, [0 max(displayWindowSec, time(end))]);
    yticks(timeAxes, offset * (0:numel(selectedRows) - 1));
    yticklabels(timeAxes, string(channelLabels(selectedRows)));

    semilogy(spectrumAxes, metrics.frequency, ...
        max(metrics.medianPSD, realmin), 'LineWidth', 1.1);
    grid(spectrumAxes, 'on');
    xlim(spectrumAxes, [0 min(500, fs / 2)]);
    hold(spectrumAxes, 'on');
    xline(spectrumAxes, 50, '--r');
    xline(spectrumAxes, 60, '--m');
    hold(spectrumAxes, 'off');

    warnings = liveWarnings(metrics, channelLabels);
    status = sprintf([ ...
        'LIVE EMG QUALITY\n\n' ...
        'Dominant frequency : %7.2f Hz\n' ...
        '50-Hz / EMG power  : %10.4g\n' ...
        '60-Hz / EMG power  : %10.4g\n' ...
        'Adjacent corr.     : %10.4f\n' ...
        'Common-mode frac.  : %10.4f\n' ...
        'Zero samples       : %9.4f %%\n' ...
        'Repeated blocks    : %9.4f %%\n' ...
        'Block-jump ratio   : %10.4f\n' ...
        'Flat channels      : %s\n\n%s'], ...
        metrics.dominantFrequency, metrics.mains50Ratio, ...
        metrics.mains60Ratio, metrics.adjacentCorrelation, ...
        metrics.commonModeFraction, 100 * metrics.zeroFraction, ...
        100 * metrics.repeatedBlockFraction, metrics.boundaryJumpRatio, ...
        formatLiveChannels(metrics.flatRows, channelLabels), warnings);
    set(statusText, 'String', status, 'ForegroundColor', ...
        warningColor(warnings));
end

function text = liveWarnings(metrics, channelLabels)
    messages = {};
    if ~isempty(metrics.flatRows)
        messages{end + 1} = ['WARNING: flat channel(s): ' ...
            formatLiveChannels(metrics.flatRows, channelLabels)];
    end
    if metrics.mains50Ratio > 0.1
        messages{end + 1} = 'WARNING: strong 50-Hz interference';
    end
    if metrics.mains60Ratio > 0.1
        messages{end + 1} = 'WARNING: strong 60-Hz interference';
    end
    if metrics.adjacentCorrelation > 0.9 || metrics.commonModeFraction > 0.8
        messages{end + 1} = 'WARNING: strong common-mode signal';
    end
    if isfinite(metrics.boundaryJumpRatio) && metrics.boundaryJumpRatio > 3
        messages{end + 1} = 'WARNING: discontinuities at read boundaries';
    end
    if isempty(messages)
        text = 'No major automated warning.';
    else
        text = strjoin(messages, newline);
    end
end

function text = formatLiveChannels(rows, labels)
    if isempty(rows)
        text = 'none';
    else
        text = mat2str(labels(rows));
    end
end

function color = warningColor(warnings)
    if contains(warnings, 'WARNING')
        color = [0.75 0 0];
    else
        color = [0 0.45 0];
    end
end

function disconnectSafely(dev)
    try
        novecento_disconnect(dev);
        fprintf('Novecento live diagnostic stopped.\n');
    catch
    end
end
