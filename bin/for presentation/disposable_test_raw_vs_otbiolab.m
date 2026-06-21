% DISPOSABLE_TEST_RAW_VS_OTBIOLAB
% Temporary test script. Safe to delete after use.
%
% Purpose:
%   Capture the unfiltered Novecento data from MATLAB before any notch or
%   bandpass filtering, so it can be compared with an OTBioLab raw export.

clear; clc;

repoRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(repoRoot, 'testcodes'));

cfg = novecento_default_config();

% Match your current live script settings.
cfg.WiFi = 0;
cfg.IP_eth = '169.254.1.10';
cfg.IP_wifi = '192.168.1.1';
cfg.activeInputs = [1 2];
cfg.emgChannels = 1:64;
cfg.previewChannels = 1:4:64;
cfg.blockDurationSec = 5;
cfg.visibleWindowSec = Inf;
cfg.forceInputChannelCounts = [64 64 0 0 0 0 0 0 0 0];

fprintf('Connecting to Novecento and capturing %.1f seconds of RAW data...\n', cfg.blockDurationSec);

dev = novecento_connect(cfg);
cleanupObj = onCleanup(@() novecento_disconnect(dev)); %#ok<NASGU>

fsVals = dev.fsInput(cfg.activeInputs);
if any(fsVals <= 0) || numel(unique(fsVals)) ~= 1
    error('Active inputs must have one valid common sampling frequency.');
end

fs = fsVals(1);
samplesPerBlock = round(fs * cfg.blockDurationSec);

rawAll = novecento_read_emg_block(dev, cfg.activeInputs, samplesPerBlock);
rawBlock = double(rawAll(cfg.emgChannels, :));

timestamp = datestr(now, 'yyyymmdd_HHMMSS');
outFile = fullfile(repoRoot, ['raw_matlab_capture_' timestamp '.mat']);
save(outFile, 'rawAll', 'rawBlock', 'cfg', 'fs', 'samplesPerBlock');

fprintf('Saved unfiltered MATLAB capture:\n%s\n', outFile);
fprintf('rawBlock size: %d channels x %d samples\n', size(rawBlock, 1), size(rawBlock, 2));
fprintf('Sampling rate: %.0f Hz\n', fs);
fprintf('Value range: %.3f to %.3f\n', min(rawBlock(:)), max(rawBlock(:)));
fprintf('Mean absolute value: %.3f\n', mean(abs(rawBlock(:))));

previewRows = cfg.previewChannels;
previewRows = previewRows(previewRows >= 1 & previewRows <= size(rawBlock, 1));
timeSec = (0:(size(rawBlock, 2) - 1)) / fs;

figure('Name', 'Disposable raw MATLAB capture', 'Color', 'w');
ax = axes;
hold(ax, 'on');
plotBlock = rawBlock(previewRows, :);
offset = max(max(std(plotBlock, 0, 2) * 6), 1);

for ii = 1:numel(previewRows)
    plot(ax, timeSec, plotBlock(ii, :) + offset * (ii - 1), 'LineWidth', 1);
end

hold(ax, 'off');
grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Channel');
title(ax, sprintf('RAW MATLAB capture before filtering | showing %d channel(s)', numel(previewRows)));
yticks(ax, offset * (0:(numel(previewRows) - 1)));
yticklabels(ax, cellstr(num2str(previewRows(:))));
xlim(ax, [timeSec(1) max(timeSec(end), 1 / fs)]);
ylim(ax, [-offset offset * numel(previewRows)]);

fprintf('\nNext check:\n');
fprintf('1. Export the same RAW time segment from OTBioLab.\n');
fprintf('2. Compare it with rawBlock from the saved MAT file.\n');
fprintf('3. If rawBlock matches OTBioLab raw export, the difference is only display/filtering/scaling.\n');
