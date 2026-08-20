function [badchan, badChannelReport] = FindBadchan(emgData, samplingRate, lineFrequencyHz)
%IDENTIFY_BAD_EMG_CHANNELS Find potentially bad channels in an EMG matrix.
%   badchan = Identify_Bad_EMG_Channels(emgData)
%   badchan = Identify_Bad_EMG_Channels(emgData, samplingRate)
%   badchan = Identify_Bad_EMG_Channels(emgData, samplingRate, lineFrequencyHz)
%   [badchan, report] = Identify_Bad_EMG_Channels(...)
%
% emgData must be channels x samples. Defaults are 2000 Hz sampling and
% 50 Hz line frequency. The function saves nothing and prints its findings.

if nargin < 2 || isempty(samplingRate)
    samplingRate = 2000;
end
if nargin < 3 || isempty(lineFrequencyHz)
    lineFrequencyHz = 50;
end

% Conservative thresholds. Visually confirm every reported channel.
lowRmsFactor = 0.10;       % RMS below 10% of the channel median
highRmsFactor = 5.00;      % RMS above 5 times the channel median
lineNoiseRatioLimit = 0.35;% Fraction of spectral power near line harmonics
lowFreqRatioLimit = 0.60;  % Fraction of power below 20 Hz
maxFlatDifferenceRatio = 0.995;
minBestCorrelation = 0.05;

%% Validate input
if ~isnumeric(emgData) || ~ismatrix(emgData) || isempty(emgData)
    error('emgData must be a non-empty numeric channels-by-samples matrix.');
end
if size(emgData, 1) > size(emgData, 2)
    error('Transpose emgData so its orientation is channels x samples.');
end
if any(~isfinite(emgData), 'all')
    error('emgData contains NaN or Inf values.');
end
if ~isscalar(samplingRate) || ~isfinite(samplingRate) || samplingRate <= 0
    error('samplingRate must be a positive finite scalar.');
end
if ~isscalar(lineFrequencyHz) || ~isfinite(lineFrequencyHz) || ...
        lineFrequencyHz <= 0 || lineFrequencyHz >= samplingRate / 2
    error('lineFrequencyHz must lie between 0 and the Nyquist frequency.');
end

data = double(emgData);
[channelCount, sampleCount] = size(data);
if channelCount < 2
    error('At least two channels are required.');
end

%% Channel metrics
data = data - mean(data, 2);
channelRms = sqrt(mean(data.^2, 2));
positiveRms = channelRms(channelRms > 0);
if isempty(positiveRms)
    medianRms = 0;
else
    medianRms = median(positiveRms);
end

flatDifferenceRatio = mean(abs(diff(data, 1, 2)) <= ...
    max(abs(data), [], 2) * 1e-12 + eps, 2);

% Best absolute correlation with any other channel. This avoids assuming a
% particular electrode-grid ordering; physical-neighbour checks are better
% when the grid map is known.
correlationMatrix = corrcoef(data');
correlationMatrix(1:(channelCount + 1):end) = NaN;
bestCorrelation = max(abs(correlationMatrix), [], 2, 'omitnan');

lineNoiseRatio = zeros(channelCount, 1);
lowFrequencyRatio = zeros(channelCount, 1);
for channelIndex = 1:channelCount
    [powerSpectrum, frequencyHz] = periodogram( ...
        data(channelIndex, :), [], [], samplingRate);
    totalPower = sum(powerSpectrum) + eps;

    lowFrequencyRatio(channelIndex) = ...
        sum(powerSpectrum(frequencyHz < 20)) / totalPower;

    lineMask = false(size(frequencyHz));
    for harmonicHz = lineFrequencyHz:lineFrequencyHz:(samplingRate / 2)
        lineMask = lineMask | abs(frequencyHz - harmonicHz) <= 1;
    end
    lineNoiseRatio(channelIndex) = sum(powerSpectrum(lineMask)) / totalPower;
end

%% Conservative classification
isFlat = channelRms == 0 | flatDifferenceRatio >= maxFlatDifferenceRatio;
isLowRms = channelRms < lowRmsFactor * medianRms;
isHighRms = channelRms > highRmsFactor * medianRms;
hasLineNoise = lineNoiseRatio > lineNoiseRatioLimit;
hasLowFrequencyArtifact = lowFrequencyRatio > lowFreqRatioLimit;
hasPoorCorrelation = bestCorrelation < minBestCorrelation;

isBad = isFlat | isLowRms | isHighRms | hasLineNoise | ...
    hasLowFrequencyArtifact | hasPoorCorrelation;
badchan = find(isBad)';

reason = strings(channelCount, 1);
for channelIndex = 1:channelCount
    channelReasons = strings(0, 1);
    if isFlat(channelIndex), channelReasons(end+1) = "flat/dropout"; end
    if isLowRms(channelIndex), channelReasons(end+1) = "very low RMS"; end
    if isHighRms(channelIndex), channelReasons(end+1) = "very high RMS"; end
    if hasLineNoise(channelIndex), channelReasons(end+1) = "line noise"; end
    if hasLowFrequencyArtifact(channelIndex)
        channelReasons(end+1) = "low-frequency artifact";
    end
    if hasPoorCorrelation(channelIndex)
        channelReasons(end+1) = "poor correlation";
    end
    if isempty(channelReasons)
        reason(channelIndex) = "OK";
    else
        reason(channelIndex) = strjoin(channelReasons, ", ");
    end
end

%% Print results only
fprintf('\nChecked %d channels and %d samples at %.1f Hz.\n', ...
    channelCount, sampleCount, samplingRate);
fprintf('Potential bad-channel list for decompose4:\n');
fprintf('badchan = %s;\n\n', mat2str(badchan));

if isempty(badchan)
    badChannelReport = table;
    fprintf('No channel exceeded the configured thresholds.\n');
else
    badChannelReport = table(badchan', channelRms(badchan), ...
        lineNoiseRatio(badchan), lowFrequencyRatio(badchan), ...
        bestCorrelation(badchan), reason(badchan), ...
        'VariableNames', {'Channel','RMS','LineNoiseRatio', ...
        'LowFrequencyRatio','BestCorrelation','Reason'});
    disp(badChannelReport);
    fprintf('These are candidates only; visually confirm them before exclusion.\n');
end

end
