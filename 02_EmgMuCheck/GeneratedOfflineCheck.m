function report = diagnoseRecordedEMG(matFile)
%DIAGNOSERECORDEDEMG Diagnose common causes of distorted recorded EMG.
%
%   report = diagnoseRecordedEMG()
%   report = diagnoseRecordedEMG(matFile)
%
% The function reads a recording without changing it. It uses recordedEMG
% when available and otherwise uses signal.data. Results are printed in the
% Command Window and summarized in three figures.

    if nargin < 1 || isempty(matFile)
        [fileName, filePath] = uigetfile('*.mat', 'Select an EMG recording');
        if isequal(fileName, 0)
            report = struct();
            fprintf('No file selected.\n');
            return;
        end
        matFile = fullfile(filePath, fileName);
    end

    if ~(ischar(matFile) || (isstring(matFile) && isscalar(matFile)))
        error('matFile must be a character vector or scalar string.');
    end
    matFile = char(matFile);
    if ~isfile(matFile)
        error('File not found: %s', matFile);
    end

    loaded = load(matFile);
    [emg, emgSource] = selectEMG(loaded);
    fs = selectSampleRate(loaded);

    if ~isnumeric(emg) || ~ismatrix(emg) || isempty(emg)
        error('EMG data must be a nonempty channels-by-samples numeric matrix.');
    end
    emg = double(emg);
    if size(emg, 1) > size(emg, 2)
        warning(['EMG has more rows than columns. Expected channels-by-samples; ' ...
            'the recording may be transposed.']);
    end

    nChannels = size(emg, 1);
    nSamples = size(emg, 2);
    durationSec = nSamples / fs;
    finiteMask = isfinite(emg);
    nonfiniteFraction = 1 - nnz(finiteMask) / numel(emg);

    analysisEMG = emg;
    analysisEMG(~finiteMask) = 0;
    channelMean = mean(analysisEMG, 2);
    centered = analysisEMG - channelMean;
    channelStd = std(centered, 0, 2);
    channelRMS = sqrt(mean(centered.^2, 2));

    zeroFraction = mean(analysisEMG(:) == 0);
    flatChannelMask = channelStd <= max(eps(max(abs(analysisEMG(:)))), eps);
    repeatedColumnFraction = repeatedColumns(analysisEMG);
    [clipFraction, clippedChannelMask] = estimateClipping(analysisEMG);
    [frequency, medianPSD] = medianChannelPSD(centered, fs);

    emgBandMask = frequency >= 20 & frequency <= min(450, fs / 2);
    mains50Mask = frequency >= 49 & frequency <= 51;
    mains60Mask = frequency >= 59 & frequency <= 61;
    lowFrequencyMask = frequency >= 0.5 & frequency <= 10;
    emgBandPower = integrateBand(medianPSD, emgBandMask);
    mains50Ratio = integrateBand(medianPSD, mains50Mask) / max(emgBandPower, eps);
    mains60Ratio = integrateBand(medianPSD, mains60Mask) / max(emgBandPower, eps);
    lowFrequencyRatio = integrateBand(medianPSD, lowFrequencyMask) / max(emgBandPower, eps);

    [~, dominantIndex] = max(medianPSD(frequency >= 1));
    validFrequency = frequency(frequency >= 1);
    dominantFrequencyHz = validFrequency(dominantIndex);

    channelCorrelation = corrcoef(centered.');
    adjacentCorrelation = diag(channelCorrelation, 1);
    if isempty(adjacentCorrelation)
        medianAdjacentCorrelation = NaN;
    else
        medianAdjacentCorrelation = median(adjacentCorrelation, 'omitnan');
    end
    offDiagonal = channelCorrelation(~eye(nChannels));
    medianAbsoluteCorrelation = median(abs(offDiagonal), 'omitnan');

    commonMode = median(centered, 1);
    commonModeFraction = medianCommonModeFraction(centered, commonMode);
    [boundaryJumpRatio, blockSamples] = blockBoundaryCheck(centered, fs, loaded);

    report = struct();
    report.file = matFile;
    report.emgSource = emgSource;
    report.fs = fs;
    report.nChannels = nChannels;
    report.nSamples = nSamples;
    report.durationSec = durationSec;
    report.nonfiniteFraction = nonfiniteFraction;
    report.zeroFraction = zeroFraction;
    report.flatChannels = find(flatChannelMask).';
    report.clippedChannels = find(clippedChannelMask).';
    report.clipFraction = clipFraction;
    report.repeatedColumnFraction = repeatedColumnFraction;
    report.dominantFrequencyHz = dominantFrequencyHz;
    report.mains50ToEMGRatio = mains50Ratio;
    report.mains60ToEMGRatio = mains60Ratio;
    report.lowFrequencyToEMGRatio = lowFrequencyRatio;
    report.medianAdjacentCorrelation = medianAdjacentCorrelation;
    report.medianAbsoluteChannelCorrelation = medianAbsoluteCorrelation;
    report.medianCommonModeFraction = commonModeFraction;
    report.blockSamples = blockSamples;
    report.blockBoundaryJumpRatio = boundaryJumpRatio;
    report.channelMean = channelMean;
    report.channelRMS = channelRMS;

    printReport(report);
    plotDiagnostics(centered, commonMode, channelRMS, channelCorrelation, ...
        frequency, medianPSD, fs, matFile);
end

function [emg, source] = selectEMG(loaded)
    if isfield(loaded, 'recordedEMG') && ~isempty(loaded.recordedEMG)
        emg = loaded.recordedEMG;
        source = 'recordedEMG';
    elseif isfield(loaded, 'signal') && isstruct(loaded.signal) && ...
            isfield(loaded.signal, 'data') && ~isempty(loaded.signal.data)
        emg = loaded.signal.data;
        source = 'signal.data';
    else
        error('The MAT file contains neither recordedEMG nor signal.data.');
    end
end

function fs = selectSampleRate(loaded)
    if isfield(loaded, 'fs_emg') && isscalar(loaded.fs_emg)
        fs = double(loaded.fs_emg);
    elseif isfield(loaded, 'signal') && isstruct(loaded.signal) && ...
            isfield(loaded.signal, 'fsamp') && isscalar(loaded.signal.fsamp)
        fs = double(loaded.signal.fsamp);
    else
        error('No scalar EMG sample rate found in fs_emg or signal.fsamp.');
    end
    if ~isfinite(fs) || fs <= 0
        error('Invalid EMG sample rate: %g', fs);
    end
end

function fraction = repeatedColumns(emg)
    if size(emg, 2) < 2
        fraction = 0;
    else
        fraction = mean(all(diff(emg, 1, 2) == 0, 1));
    end
end

function [fraction, channelMask] = estimateClipping(emg)
    fraction = zeros(size(emg, 1), 1);
    for channel = 1:size(emg, 1)
        x = emg(channel, :);
        low = min(x);
        high = max(x);
        if high > low
            fraction(channel) = mean(x == low | x == high);
        end
    end
    channelMask = fraction > 0.01;
end

function [frequency, medianPSD] = medianChannelPSD(emg, fs)
    nSamples = size(emg, 2);
    segmentLength = min(nSamples, max(256, round(2 * fs)));
    if segmentLength < 2
        frequency = 0;
        medianPSD = 0;
        return;
    end

    overlap = floor(segmentLength / 2);
    step = max(1, segmentLength - overlap);
    starts = 1:step:(nSamples - segmentLength + 1);
    maxSegments = 30;
    if numel(starts) > maxSegments
        starts = starts(round(linspace(1, numel(starts), maxSegments)));
    end

    window = 0.5 - 0.5 * cos(2 * pi * (0:segmentLength - 1) / ...
        (segmentLength - 1));
    windowPower = sum(window.^2);
    positiveBins = 1:(floor(segmentLength / 2) + 1);
    accumulatedPSD = zeros(size(emg, 1), numel(positiveBins));

    for startIndex = starts
        segment = emg(:, startIndex:startIndex + segmentLength - 1);
        spectrum = fft(segment .* window, [], 2);
        powerSpectrum = abs(spectrum(:, positiveBins)).^2 / (fs * windowPower);
        if numel(positiveBins) > 2
            powerSpectrum(:, 2:end - 1) = 2 * powerSpectrum(:, 2:end - 1);
        end
        accumulatedPSD = accumulatedPSD + powerSpectrum;
    end

    accumulatedPSD = accumulatedPSD / numel(starts);
    medianPSD = median(accumulatedPSD, 1).';
    frequency = (positiveBins - 1).' * fs / segmentLength;
end

function power = integrateBand(psd, mask)
    if any(mask)
        power = sum(psd(mask));
    else
        power = 0;
    end
end

function fraction = medianCommonModeFraction(centered, commonMode)
    channelVariance = var(centered, 0, 2);
    residualVariance = var(centered - commonMode, 0, 2);
    valid = channelVariance > 0;
    if any(valid)
        fraction = median(max(0, 1 - residualVariance(valid) ./ ...
            channelVariance(valid)), 'omitnan');
    else
        fraction = NaN;
    end
end

function [ratio, blockSamples] = blockBoundaryCheck(emg, fs, loaded)
    blockDuration = 0.02;
    if isfield(loaded, 'emgBlockDurationSec') && ...
            isscalar(loaded.emgBlockDurationSec)
        blockDuration = double(loaded.emgBlockDurationSec);
    end
    blockSamples = max(1, round(fs * blockDuration));
    sampleDifference = abs(diff(emg, 1, 2));
    typicalJump = median(sampleDifference(:), 'omitnan');
    boundaryIndices = blockSamples:blockSamples:(size(emg, 2) - 1);
    if isempty(boundaryIndices) || typicalJump == 0
        ratio = NaN;
    else
        boundaryJump = median(sampleDifference(:, boundaryIndices), 'all', 'omitnan');
        ratio = boundaryJump / typicalJump;
    end
end

function printReport(report)
    fprintf('\n============================================================\n');
    fprintf('EMG diagnostic: %s\n', report.file);
    fprintf('Source: %s | %d channels x %d samples | %.1f Hz | %.3f s\n', ...
        report.emgSource, report.nChannels, report.nSamples, report.fs, ...
        report.durationSec);
    fprintf('------------------------------------------------------------\n');
    fprintf('Nonfinite samples             : %.6g %%\n', 100 * report.nonfiniteFraction);
    fprintf('Zero-valued samples           : %.6g %%\n', 100 * report.zeroFraction);
    fprintf('Repeated sample columns       : %.6g %%\n', 100 * report.repeatedColumnFraction);
    fprintf('Channels with clipping pattern: %s\n', formatIndices(report.clippedChannels));
    fprintf('Flat channels                 : %s\n', formatIndices(report.flatChannels));
    fprintf('Dominant frequency            : %.3f Hz\n', report.dominantFrequencyHz);
    fprintf('50-Hz power / 20-450-Hz power: %.6g\n', report.mains50ToEMGRatio);
    fprintf('60-Hz power / 20-450-Hz power: %.6g\n', report.mains60ToEMGRatio);
    fprintf('0.5-10-Hz / 20-450-Hz power  : %.6g\n', report.lowFrequencyToEMGRatio);
    fprintf('Median adjacent correlation   : %.6g\n', report.medianAdjacentCorrelation);
    fprintf('Median absolute correlation   : %.6g\n', report.medianAbsoluteChannelCorrelation);
    fprintf('Median common-mode fraction   : %.6g\n', report.medianCommonModeFraction);
    fprintf('%d-sample block jump ratio     : %.6g\n', ...
        report.blockSamples, report.blockBoundaryJumpRatio);
    fprintf('------------------------------------------------------------\n');

    messages = {};
    if report.nonfiniteFraction > 0
        messages{end + 1} = 'NaN/Inf values exist; inspect acquisition or post-processing.';
    end
    if ~isempty(report.flatChannels)
        messages{end + 1} = 'Flat channels suggest disconnected or inactive electrodes.';
    end
    if ~isempty(report.clippedChannels)
        messages{end + 1} = 'Some channels repeatedly hit their extrema; check gain and saturation.';
    end
    if report.repeatedColumnFraction > 1e-4
        messages{end + 1} = 'Repeated columns may indicate duplicated or stalled stream data.';
    end
    if report.mains50ToEMGRatio > 0.1
        messages{end + 1} = ['Strong 50-Hz contamination: check reference/ground, skin contact, ' ...
            'connectors, nearby mains devices, and laptop charger.'];
    elseif report.mains60ToEMGRatio > 0.1
        messages{end + 1} = ['Strong 60-Hz contamination: check reference/ground, skin contact, ' ...
            'connectors, and nearby mains devices.'];
    end
    if report.medianAdjacentCorrelation > 0.9 || ...
            report.medianCommonModeFraction > 0.8
        messages{end + 1} = ['Most channels share the same waveform; this strongly suggests ' ...
            'common-mode interference or a reference/ground problem.'];
    end
    if report.lowFrequencyToEMGRatio > 0.2
        messages{end + 1} = 'Large low-frequency content suggests motion artifact or baseline drift.';
    end
    if isfinite(report.blockBoundaryJumpRatio) && report.blockBoundaryJumpRatio > 3
        messages{end + 1} = ['Jumps are concentrated at read-block boundaries; investigate ' ...
            'packet alignment or dropped blocks.'];
    end
    if isempty(messages)
        messages = {'No strong automated warning was detected; inspect the plots and electrode setup.'};
    end

    fprintf('Interpretation:\n');
    for index = 1:numel(messages)
        fprintf('  %d. %s\n', index, messages{index});
    end
    fprintf('============================================================\n\n');
end

function text = formatIndices(indices)
    if isempty(indices)
        text = 'none';
    else
        text = mat2str(indices);
    end
end

function plotDiagnostics(emg, commonMode, channelRMS, correlationMatrix, ...
        frequency, medianPSD, fs, matFile)
    [~, fileName, extension] = fileparts(matFile);
    plotTitle = [fileName extension];
    nChannels = size(emg, 1);
    nDisplayChannels = min(8, nChannels);
    displayChannels = unique(round(linspace(1, nChannels, nDisplayChannels)));
    displaySamples = min(size(emg, 2), round(5 * fs));
    time = (0:displaySamples - 1) / fs;
    scale = max(median(std(emg(displayChannels, :), 0, 2)) * 6, eps);

    figure('Name', 'Recorded EMG: time-domain diagnostic', 'Color', 'w');
    tiledlayout(2, 1);
    nexttile;
    hold on;
    for index = 1:numel(displayChannels)
        channel = displayChannels(index);
        plot(time, emg(channel, 1:displaySamples) + scale * (index - 1));
    end
    hold off;
    grid on;
    xlabel('Time (s)');
    ylabel('Selected channels (offset)');
    title(sprintf('%s: first %.1f seconds', plotTitle, time(end)));
    yticks(scale * (0:numel(displayChannels) - 1));
    yticklabels(string(displayChannels));

    nexttile;
    plot(time, commonMode(1:displaySamples), 'k');
    grid on;
    xlabel('Time (s)');
    ylabel('Median across channels');
    title('Common-mode waveform');

    figure('Name', 'Recorded EMG: frequency diagnostic', 'Color', 'w');
    semilogy(frequency, max(medianPSD, realmin), 'LineWidth', 1.2);
    grid on;
    xlim([0 min(500, fs / 2)]);
    xlabel('Frequency (Hz)');
    ylabel('Median PSD');
    title([plotTitle ': median channel spectrum']);
    hold on;
    xline(50, '--r', '50 Hz');
    xline(60, '--m', '60 Hz');
    hold off;

    figure('Name', 'Recorded EMG: channel diagnostic', 'Color', 'w');
    tiledlayout(1, 2);
    nexttile;
    bar(1:nChannels, channelRMS);
    grid on;
    xlabel('Channel');
    ylabel('Centered RMS');
    title('Channel amplitude');
    nexttile;
    imagesc(correlationMatrix, [-1 1]);
    axis image;
    colorbar;
    xlabel('Channel');
    ylabel('Channel');
    title('Channel correlation');
end
