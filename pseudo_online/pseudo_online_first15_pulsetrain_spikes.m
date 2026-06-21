%% =========================================================================
% PSEUDO-ONLINE PULSE TRAIN VISUALISATION, 10 TO 20 SECONDS
%
% This script reuses offline calibration filters and applies them to a new
% EMG trial in pseudo-online chunks. It plots the pulse train after applying
% the MU filters and marks only the detected spikes.
%
% Required in workspace before running:
%   recordedEMG : calibration EMG used for offline decomposition
%   Calib_data  : output from decompose3(), containing Calib_data.MUFilters
%
% Selected .mat file must contain:
%   recordedEMG : new trial EMG, channels x samples
%
% Outputs left in workspace:
%   Pulsetrain_online
%   Distime
%   Dischargetimes_online
% =========================================================================

%% Parameters
fs = 2000;
badchan = [];
window_sec = 0.125;
segment_start_sec = 15;
segment_end_sec = 20;
muToPlot = 1; % change to another MU index if needed

addpath('online_decomp_renato/lib');
addpath('offline_decomp_renato/lib');

%% Validate calibration inputs
assert(exist('recordedEMG', 'var') == 1, ...
    'recordedEMG calibration signal not found in workspace.')
assert(exist('Calib_data', 'var') == 1, ...
    'Calib_data not found in workspace. Run decompose3() first.')
assert(isfield(Calib_data, 'MUFilters') && ~isempty(Calib_data.MUFilters), ...
    'Calib_data.MUFilters is missing or empty.')

fprintf('\n=== 10 to 20 s pseudo-online pulse train + spikes ===\n')

%% Channel mask
EMGmask = zeros(size(recordedEMG, 1), 1); % 0 = good, 1 = bad
EMGmask(badchan) = 1;
nGoodChan = sum(EMGmask == 0);

%% Load calibration filters and compute online parameters
MUFilters = Calib_data.MUFilters;
nMUs = size(MUFilters, 2);

if nMUs == 0
    error('No MU filters found in Calib_data.')
end

[extensionfactor, iReSIG, norm_fac, centroid] = getonlineparameters( ...
    recordedEMG, EMGmask, MUFilters, fs);

% Online projection filter. This is the filter applied to the extended,
% demeaned online EMG inside getspikesonline.
MUfilt = MUFilters' * iReSIG;

%% Load new trial
fprintf('Select the new sample .mat file...\n')
[fname, fpath] = uigetfile('*.mat', ...
    'Select new EMG trial for 10-to-20-s pulse-train plot');

if isequal(fname, 0)
    error('No file selected.')
end

newdata = load(fullfile(fpath, fname), 'recordedEMG');
assert(isfield(newdata, 'recordedEMG'), ...
    'Variable recordedEMG not found in selected file: %s', fname)

newEMG = newdata.recordedEMG;
if size(newEMG, 1) ~= size(recordedEMG, 1)
    error('Channel mismatch: calibration has %d channels, new file has %d.', ...
        size(recordedEMG, 1), size(newEMG, 1))
end

%% Keep only 10 to 20 seconds and align to whole windows
window_samples = round(window_sec * fs);
segment_start_sample = round(segment_start_sec * fs) + 1;
segment_end_sample = min(round(segment_end_sec * fs), size(newEMG, 2));

if segment_start_sample > size(newEMG, 2)
    error('Selected trial is shorter than %.1f seconds.', segment_start_sec)
end

newEMG = newEMG(:, segment_start_sample:segment_end_sample);
nwin = floor(size(newEMG, 2) / window_samples);

if nwin < 1
    error('Selected trial is shorter than one pseudo-online window.')
end

total_samples = nwin * window_samples;
newEMG = newEMG(:, 1:total_samples);
time = segment_start_sec + (0:total_samples-1) / fs;

fprintf('Loaded: %s\n', fname)
fprintf('Plotting %.2f to %.2f s | %d windows | %d samples/window\n', ...
    segment_start_sec, segment_start_sec + total_samples / fs, nwin, window_samples)

%% Build centroid matrices and preallocate outputs
noise_centroids = ones(window_samples, nMUs) .* (centroid(:, 1)');
spike_centroids = ones(window_samples, nMUs) .* (centroid(:, 2)');

esample2 = zeros(nGoodChan * extensionfactor, extensionfactor - 1);
Pulsetrain_online = zeros(nMUs, total_samples);
Distime = false(total_samples, nMUs);
Dischargetimes_online = cell(1, nMUs);

for mu = 1:nMUs
    Dischargetimes_online{mu} = [];
end

%% Pseudo-online processing loop
for k = 1:nwin
    start_idx = (k-1) * window_samples + 1;
    end_idx = k * window_samples;

    EMGchunk = newEMG(:, start_idx:end_idx);
    EMGchunkGood = EMGchunk(EMGmask == 0, :);

    [Pulsetrain_online(:, start_idx:end_idx), ...
     Distime(start_idx:end_idx, :), ...
     esample2] = getspikesonline(EMGchunkGood, extensionfactor, esample2, ...
                                 MUfilt, norm_fac, noise_centroids, ...
                                 spike_centroids, window_samples, fs);

    for mu = 1:nMUs
        new_spikes = find(Distime(start_idx:end_idx, mu)) + start_idx - 1;
        if ~isempty(new_spikes)
            Dischargetimes_online{mu} = [Dischargetimes_online{mu}; new_spikes(:)];
        end
    end
end

%% Plot selected MU pulse train and spike-only row
if muToPlot > nMUs
    warning('muToPlot = %d exceeds nMUs = %d. Plotting MU1 instead.', muToPlot, nMUs)
    muToPlot = 1;
end

spikes = Dischargetimes_online{muToPlot};

figure('Color', 'w', 'Position', [80 80 1450 420], ...
    'Name', sprintf('MU%d pulse train, 10 to 20 s', muToPlot));

subplot(2, 1, 1)
plot(time, Pulsetrain_online(muToPlot, :), 'b', 'LineWidth', 0.8)
hold on
if ~isempty(spikes)
    plot(time(spikes), Pulsetrain_online(muToPlot, spikes), ...
        'r.', 'MarkerSize', 10)
end
hold off
grid on
xlabel('Time (s)')
ylabel('Pulse')
title(sprintf('MU%d pulse train after MU filter projection, spikes = %d', ...
    muToPlot, length(spikes)))

subplot(2, 1, 2)
hold on
if ~isempty(spikes)
    plot(time(spikes), ones(size(spikes)), 'r.', 'MarkerSize', 10)
end
hold off
grid on
xlim([segment_start_sec segment_start_sec + total_samples / fs])
ylim([0 2])
yticks(1)
yticklabels({sprintf('MU%d', muToPlot)})
xlabel('Time (s)')
ylabel('Motor unit')
title(sprintf('Detected spikes from pseudo-online pulse train, MU%d, 10 to 20 seconds', ...
    muToPlot))

fprintf('\nDone. Outputs in workspace:\n')
fprintf('  Pulsetrain_online\n')
fprintf('  Distime\n')
fprintf('  Dischargetimes_online\n\n')
