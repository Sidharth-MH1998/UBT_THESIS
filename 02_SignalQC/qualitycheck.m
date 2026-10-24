%% Offline EMG quality check: raw diagnostics and filtering comparison
% Select a MAT recording. The original file and signal are not modified.
% Outputs: emgData, filteredEMG, diagnosticReport, rawBadchan,
% filteredBadchan, badchan (union), badChannelReport (rows labeled by stage).
close all

%% 1. User settings
channelsToPlot = [];       % [] = all channels; or e.g. 1:4:64
spectrumChannel = 1;
visibleWindowSec = Inf;    % Limits plots only; diagnostics use the full recording
lineFrequencyHz = 50;
forceChannel = 2;          % Original force channel, when recordedForce is available
recordingBlockDurationSec = []; % [] = unknown; set actual acquisition block duration for jump checks
useAdaptiveNotch = true;
baseFreqRange = [45 55];
numHarmonics = 9;
notchWidth = 1;
useBandpass = true;

%% 2. Select and load recording
scriptDirectory = fileparts(mfilename('fullpath'));
repositoryDirectory = fileparts(scriptDirectory);
addpath(scriptDirectory,fullfile(repositoryDirectory,'000_Library','my_funcs'), ...
    fullfile(repositoryDirectory,'000_Library','lib'));
[fileName,fileDirectory] = uigetfile('*.mat','Select an EMG recording for quality check');
if isequal(fileName,0)
    fprintf('No recording selected.\n');
    return;
end
matFile = fullfile(fileDirectory,fileName);
loadedRecording = load(matFile);
[emgData,samplingRate,forceData,forceSamplingRate,forceLabel,gridCount,emgSource] = ...
    localReadRecording(loadedRecording,forceChannel);
[numberOfChannels,numberOfSamples] = size(emgData);
assert(numberOfSamples>=max(16,numberOfChannels), ...
    'Recording is too short or transposed; expected channels x samples (at least 16 samples).');
assert(isscalar(visibleWindowSec) && visibleWindowSec>0 && ~isnan(visibleWindowSec), ...
    'visibleWindowSec must be positive or Inf.');
if isempty(channelsToPlot), channelsToPlot=1:numberOfChannels; end
assert(all(ismember(channelsToPlot,1:numberOfChannels)), 'Invalid channelsToPlot.');
assert(isscalar(spectrumChannel) && ismember(spectrumChannel,1:numberOfChannels), ...
    'Invalid spectrumChannel.');
if isempty(recordingBlockDurationSec) && isfield(loadedRecording,'emgBlockDurationSec')
    recordingBlockDurationSec=loadedRecording.emgBlockDurationSec;
end
plotSamples=min(numberOfSamples,max(1,round(visibleWindowSec*samplingRate)));
fprintf('Loaded %s: %d channels, %d samples, %.3f s at %g Hz.\n', ...
    fileName,numberOfChannels,numberOfSamples,numberOfSamples/samplingRate,samplingRate);

%% 3. Diagnose raw EMG before filtering can hide interference
% Full raw-recording metrics, time/common-mode, spectrum, RMS/correlation plots.
diagnosticReport=localDiagnoseRecordedEMG(double(emgData),samplingRate,matFile, ...
    emgSource,recordingBlockDurationSec);
[rawBadchan,rawBadChannelReport]=localFindBadChannels(emgData,samplingRate, ...
    lineFrequencyHz,gridCount,'Raw');

%% 4. Filter finite channels using the existing filtering functions
validChannels=all(isfinite(emgData),2);
filteredEMG=nan(size(emgData));
filterInput=double(emgData(validChannels,:));
if any(~validChannels)
    warning('qualitycheck:InvalidChannels', ...
        'Nonfinite channels %s excluded from filtering; raw data remain unchanged.', ...
        mat2str(find(~validChannels).'));
end
if ~isempty(filterInput) && useAdaptiveNotch
    assert(numel(baseFreqRange)==2 && baseFreqRange(1)>0 && ...
        baseFreqRange(2)>baseFreqRange(1) && baseFreqRange(2)<samplingRate/2, ...
        'Notch search range must lie between zero and Nyquist.');
    effectiveHarmonics=min(numHarmonics,floor((samplingRate/2-notchWidth)/baseFreqRange(2)));
    bins=(0:numberOfSamples-1)*samplingRate/numberOfSamples;
    if effectiveHarmonics>=1 && any(bins>=baseFreqRange(1) & bins<=baseFreqRange(2))
        filterInput=adaptiveNotchFilter(filterInput,samplingRate,baseFreqRange, ...
            effectiveHarmonics,notchWidth);
    else
        warning('qualitycheck:NotchSkipped','Notch skipped: insufficient frequency range/resolution.');
    end
end
if ~isempty(filterInput) && useBandpass
    assert(samplingRate>1000,'Existing 20-500 Hz surface-EMG filter requires samplingRate > 1000 Hz.');
    filterInput=bandpassingals(filterInput,samplingRate,1);
end
filteredEMG(validChannels,:)=filterInput;

%% 5. Before/after traces, force and selected-channel spectrum
localPlotStackedComparison(double(emgData(channelsToPlot,1:plotSamples)), ...
    filteredEMG(channelsToPlot,1:plotSamples),channelsToPlot,samplingRate);
if ~isempty(forceData)
    forcePlotSamples=min(numel(forceData),max(1,round(visibleWindowSec*forceSamplingRate)));
    localPlotForce(forceData(1:forcePlotSamples),forceSamplingRate,forceLabel);
else
    fprintf('No force data with a known sampling rate available; force plot skipped.\n');
end
if validChannels(spectrumChannel)
    localPlotSpectrum(double(emgData(spectrumChannel,:)), ...
        filteredEMG(spectrumChannel,:),samplingRate,spectrumChannel);
else
    fprintf('Spectrum comparison skipped: channel %d contains NaN/Inf.\n',spectrumChannel);
end

%% 6. Bad-channel candidates after filtering; retain raw findings too
[filteredBadchan,filteredBadChannelReport]=localFindBadChannels(filteredEMG, ...
    samplingRate,lineFrequencyHz,gridCount,'Filtered');
badchan=union(rawBadchan,filteredBadchan);
badChannelReport=[rawBadChannelReport;filteredBadChannelReport];
localPrintSummary(diagnosticReport,badchan,badChannelReport,numberOfChannels,gridCount);

%% Local functions: load current signal files and older recordings
function localPrintSummary(diagnostic,bad,report,nChannels,ng)
fprintf('\nQUALITY SUMMARY\n');
fprintf('Raw spectrum: peak %.1f Hz | 50 Hz / EMG %.2f%% | 60 Hz / EMG %.2f%%\n', ...
    diagnostic.dominantFrequencyHz,100*diagnostic.mains50ToEMGRatio, ...
    100*diagnostic.mains60ToEMGRatio);
fprintf('Correlation: consecutive %.3f | common-mode fraction %.3f\n', ...
    diagnostic.medianAdjacentCorrelation,diagnostic.medianCommonModeFraction);
messages=localInterpretation(diagnostic);
for k=1:numel(messages), fprintf('  Note: %s\n',messages{k}); end
if isempty(bad)
    fprintf('Bad-channel candidates: none\n');
else
    fprintf('Bad-channel candidates: %d\n',numel(bad));
    if ng>1 && mod(nChannels,ng)==0, perGrid=nChannels/ng; else, perGrid=nChannels; end
    for ch=reshape(bad,1,[])
        selected=report.Channel==ch;
        reasons=unique(report.Reason(selected),'stable');
        stages=unique(report.Stage(selected));
        if all(ismember(["Raw" "Filtered"],stages))
            status='raw + filtered';
        elseif any(stages=="Raw")
            status='raw only; not flagged after filtering';
        else
            status='filtered only';
        end
        fprintf('  Channel %d (grid %d, channel %d): %s [%s]\n', ...
            ch,floor((ch-1)/perGrid)+1,mod(ch-1,perGrid)+1,strjoin(reasons,'; '),status);
    end
end
fprintf('badchan = %s;\n',mat2str(bad));
if ~isfinite(diagnostic.blockSamples)
    fprintf('Block-boundary check skipped: acquisition block duration unknown.\n');
end
fprintf('Details: diagnosticReport, badChannelReport. Candidates require visual confirmation.\n\n');
end

function [emg,fs,force,forceFs,forceLabel,ng,source]=localReadRecording(loaded,forceChannel)
force=[]; forceFs=[]; forceLabel=''; ng=1;
if isfield(loaded,'signal') && isstruct(loaded.signal) && isscalar(loaded.signal) && ...
        isfield(loaded.signal,'data') && isfield(loaded.signal,'fsamp')
    s=loaded.signal; emg=s.data; fs=double(s.fsamp); source='signal.data';
    if isfield(s,'ngrid'), ng=s.ngrid; end
    if isfield(s,'recordedForce') && ~isempty(s.recordedForce) && isfield(s,'fs_force')
        force=s.recordedForce; forceFs=double(s.fs_force); forceLabel='signal.recordedForce';
    elseif isfield(s,'path') && ~isempty(s.path)
        assert(isvector(s.path) && numel(s.path)==size(emg,2), ...
            'signal.path must be a vector matched to the EMG sample count.');
        force=s.path(:); forceFs=fs; forceLabel='signal.path (matched to EMG samples)';
    end
elseif isfield(loaded,'recordedEMG') && isfield(loaded,'fs_emg')
    emg=loaded.recordedEMG; fs=double(loaded.fs_emg); source='recordedEMG';
    if isfield(loaded,'activeEMGInputs'), ng=numel(loaded.activeEMGInputs); end
else
    error('Recording must contain signal.data / signal.fsamp or recordedEMG / fs_emg.');
end
validateattributes(emg,{'numeric'},{'2d','nonempty','real'});
validateattributes(fs,{'numeric'},{'scalar','finite','positive'});
validateattributes(ng,{'numeric'},{'scalar','integer','positive','finite'});
if isempty(force) && isfield(loaded,'recordedForce') && isfield(loaded,'fs_force')
    force=loaded.recordedForce; forceFs=double(loaded.fs_force); forceLabel='recordedForce';
end
if ~isempty(force)
    validateattributes(force,{'numeric'},{'2d','real'});
    validateattributes(forceFs,{'numeric'},{'scalar','finite','positive'});
    if ~contains(forceLabel,'path')
        validateattributes(forceChannel,{'numeric'},{'scalar','integer','positive'});
        if forceChannel>size(force,2)
            warning('qualitycheck:ForceChannel','Requested force channel absent; plotting channel 1.');
            forceChannel=1;
        end
        force=force(:,forceChannel);
        forceLabel=sprintf('%s channel %d',forceLabel,forceChannel);
    end
    force=force(:);
end
end

function [bad,report]=localFindBadChannels(data,fs,lineHz,ng,stage)
% Check each grid independently when ngrid and channel count support it.
bad=[]; report=table;
count=size(data,1);
if ng>1 && mod(count,ng)==0, groups=ng; else, groups=1; end
perGrid=count/groups;
for g=1:groups
    rows=(g-1)*perGrid+(1:perGrid);
    finiteRows=rows(all(isfinite(data(rows,:)),2));
    invalid=setdiff(rows,finiteRows);
    bad=union(bad,invalid);
    if numel(finiteRows)>=2
        [localBad,t]=FindBadchan(data(finiteRows,:),fs,lineHz,false);
        bad=union(bad,finiteRows(localBad));
        if ~isempty(t)
            t.Channel=reshape(finiteRows(t.Channel),[],1);
            t.Grid=repmat(g,height(t),1);
            t.Stage=repmat(string(stage),height(t),1);
            report=[report;t]; %#ok<AGROW>
        end
    end
    if ~isempty(invalid)
        n=numel(invalid);
        t=table(invalid(:),nan(n,1),nan(n,1),nan(n,1),nan(n,1), ...
            repmat("NaN/Inf: excluded from analysis",n,1),repmat(g,n,1), ...
            repmat(string(stage),n,1),'VariableNames', ...
            {'Channel','RMS','LineNoiseRatio','LowFrequencyRatio','BestCorrelation','Reason','Grid','Stage'});
        report=[report;t]; %#ok<AGROW>
    end
end
bad=reshape(bad,1,[]);
end

function localPlotForce(forceSignal, fsamp, forceLabel)
timeSec = (0:numel(forceSignal)-1) / fsamp;
figure('Name', forceLabel, 'Color', 'w');
plot(timeSec, forceSignal, 'LineWidth', 1);
grid on;
xlabel('Time (s)');
ylabel('Force');
title(forceLabel,'Interpreter','none');
xlim([0 max(timeSec(end), 1/fsamp)]);
end

function localPlotStackedComparison(rawSignal, filteredSignal,channelNumbers, fsamp)
% Display raw and filtered channels side by side with identical scaling.
combinedSignal = [rawSignal filteredSignal];
channelScale = std(combinedSignal, 0, 2);
channelScale = channelScale(isfinite(channelScale) & channelScale > 0);
if isempty(channelScale)
    offset = 1;
else
    offset = max(6 * median(channelScale), eps);
end

figure('Name', 'EMG Visualisation', 'Color', 'w');
layout = tiledlayout(1, 2, 'TileSpacing', 'compact', ...
    'Padding', 'compact');
rawAxes = nexttile(layout);
localDrawStacked(rawAxes, rawSignal, channelNumbers, fsamp, offset, ...
    'Before');
filteredAxes = nexttile(layout);
localDrawStacked(filteredAxes, filteredSignal, channelNumbers, fsamp, ...
    offset, 'After');
linkaxes([rawAxes filteredAxes], 'xy');
title(layout, 'EMG quality comparison');
end

function localDrawStacked(ax, signal, channelNumbers, fsamp, offset, plotTitle)
timeSec = (0:size(signal, 2)-1) / fsamp;
hold(ax, 'on');
for index = 1:size(signal, 1)
    plot(ax, timeSec, signal(index, :) + offset * (index - 1), ...
        'LineWidth', 0.75);
end
hold(ax, 'off');
grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Channel');
title(ax, plotTitle);
yticks(ax, offset * (0:numel(channelNumbers)-1));
yticklabels(ax, string(channelNumbers));
xlim(ax, [0 max(timeSec(end), 1/fsamp)]);
ylim(ax, [-offset, offset * numel(channelNumbers)]);
end

function localPlotSpectrum(rawSignal, filteredSignal, fsamp, channelNumber)
rawSignal = rawSignal - mean(rawSignal);
filteredSignal = filteredSignal - mean(filteredSignal);
windowLength = min(numel(rawSignal), max(8, round(fsamp)));
window = hann(windowLength, 'periodic');
overlap = floor(windowLength / 2);
nfft = max(2048, 2^nextpow2(windowLength));
[rawPower, frequencyHz] = pwelch(rawSignal, window, overlap, nfft, fsamp);
filteredPower = pwelch(filteredSignal, window, overlap, nfft, fsamp);

figure('Name', sprintf('EMG spectrum - channel %d', channelNumber), ...
    'Color', 'w');
plot(frequencyHz, 10*log10(rawPower + eps), 'DisplayName', 'Before');
hold on;
plot(frequencyHz, 10*log10(filteredPower + eps), 'DisplayName', 'After');
hold off;
grid on;
xlim([0 min(700, fsamp/2)]);
xlabel('Frequency (Hz)');
ylabel('Power (dB/Hz)');
title(sprintf('EMG frequency spectrum at Channel %d', ...
    channelNumber));
legend('Location', 'best');
end

function report=localDiagnoseRecordedEMG(emg,fs,matFile,emgSource,blockDuration)
    nChannels = size(emg, 1);
    nSamples = size(emg, 2);
    durationSec = nSamples / fs;
    finiteMask = isfinite(emg);
    nonfiniteFraction = nnz(~finiteMask) / numel(emg);

    analysisEMG = emg;
    analysisEMG(~finiteMask) = 0;
    channelMean = mean(analysisEMG, 2);
    centered = analysisEMG - channelMean;
    channelStd = std(centered, 0, 2);
    channelRMS = sqrt(mean(centered.^2, 2));

    zeroFraction = mean(emg(:) == 0);
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

    validFrequency = frequency(frequency >= 1);
    validPower = medianPSD(frequency >= 1);
    dominantFrequencyHz = NaN;
    if any(validPower>0)
        [~, dominantIndex] = max(validPower);
        dominantFrequencyHz = validFrequency(dominantIndex);
    end

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
    [boundaryJumpRatio, blockSamples] = blockBoundaryCheck(centered, fs, struct('emgBlockDurationSec',blockDuration));

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

    plotDiagnostics(centered, commonMode, channelRMS, channelCorrelation, ...
        frequency, medianPSD, fs, matFile);
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
        if mod(segmentLength,2)==0
            powerSpectrum(:, 2:end - 1) = 2 * powerSpectrum(:, 2:end - 1);
        else
            powerSpectrum(:, 2:end) = 2 * powerSpectrum(:, 2:end);
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
    blockDuration = [];
    if isfield(loaded, 'emgBlockDurationSec') && ...
            ~isempty(loaded.emgBlockDurationSec)
        blockDuration = double(loaded.emgBlockDurationSec);
    end
    if isempty(blockDuration)
        ratio = NaN;
        blockSamples = NaN;
        return;
    end
    validateattributes(blockDuration,{'numeric'},{'scalar','positive','finite'});
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

function messages = localInterpretation(report)
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


