%% =========================================================================
% PSEUDO-ONLINE DECOMPOSITION, FIRST 20 SECONDS ONLY
% Force overlay + MUs ordered by recruitment threshold
%
% Required in workspace before running:
%   recordedEMG : calibration EMG used for offline decomposition
%   Calib_data  : output of decompose3(), containing Calib_data.MUFilters
%
% The selected trial .mat file must contain:
%   recordedEMG
%   recordedForce
%
% Outputs left in workspace:
%   Dischargetimes_online
%   Pulsetrain_online
%   fr_online
%   mean_fr_online
%   recruitThresh_online
%   MU_order_recruitment
% =========================================================================

%% Parameters
fs = 2000;          % EMG sampling frequency (Hz)
fs_force = 50;      % force sampling frequency (Hz)
badchan = [];       % bad channels from calibration, e.g. [5 23]
window_sec = 0.125; % pseudo-online chunk size
duration_sec = 20;  % only analyse first 20 seconds

addpath('online_decomp_renato/lib');
addpath('offline_decomp_renato/lib');

%% Validate calibration inputs
assert(exist('recordedEMG', 'var') == 1, ...
    'recordedEMG calibration signal not found in workspace.')
assert(exist('Calib_data', 'var') == 1, ...
    'Calib_data not found in workspace. Run decompose3() first.')
assert(isfield(Calib_data, 'MUFilters') && ~isempty(Calib_data.MUFilters), ...
    'Calib_data.MUFilters is missing or empty.')

fprintf('\n=== Pseudo-online first 20 s + force + recruitment order ===\n')

%% Channel mask
nChan = size(recordedEMG, 1);
if ~isempty(badchan)
    assert(all(badchan >= 1 & badchan <= nChan), ...
        'badchan contains invalid channel indices.')
    badchan = unique(badchan(:).');
end

EMGmask = zeros(nChan, 1); % 0 = good channel, 1 = bad channel
EMGmask(badchan) = 1;
nGoodChan = sum(EMGmask == 0);

%% Calibration filters and online parameters
MUFilters = Calib_data.MUFilters;
nMUs = size(MUFilters, 2);

fprintf('Calibration MUs: %d\n', nMUs)
fprintf('Channels: %d total | %d good | %d bad\n', nChan, nGoodChan, numel(badchan))

[extensionfactor, iReSIG, norm_fac, centroid] = getonlineparameters( ...
    recordedEMG, EMGmask, MUFilters, fs);

MUfilt = MUFilters' * iReSIG;

%% Load new trial
fprintf('\nSelect new trial .mat file containing recordedEMG and recordedForce...\n')
[fname, fpath] = uigetfile('*.mat', ...
    'Select new EMG + force trial for pseudo-online decomposition');

if isequal(fname, 0)
    error('No file selected.')
end

newdata = load(fullfile(fpath, fname), 'recordedEMG', 'recordedForce');
assert(isfield(newdata, 'recordedEMG'), ...
    'Selected file does not contain recordedEMG.')
assert(isfield(newdata, 'recordedForce'), ...
    'Selected file does not contain recordedForce.')

newEMG = newdata.recordedEMG;
assert(size(newEMG, 1) == nChan, ...
    'Channel mismatch: calibration has %d channels, selected trial has %d.', ...
    nChan, size(newEMG, 1))

% Force convention used in the existing scripts: force is column 2.
assert(size(newdata.recordedForce, 2) >= 2, ...
    'recordedForce must contain force in column 2.')
force_signal = newdata.recordedForce(:, 2);
force_signal = force_signal(:).';

%% Restrict to first 20 seconds
max_samples = min(round(duration_sec * fs), size(newEMG, 2));
newEMG = newEMG(:, 1:max_samples);
total_samples = size(newEMG, 2);
total_duration = total_samples / fs;

window_samples = round(window_sec * fs);
nwin = floor(total_samples / window_samples);
usable_samples = nwin * window_samples;

if nwin < 1
    error('The selected trial is shorter than one pseudo-online window.')
end

newEMG = newEMG(:, 1:usable_samples);
total_samples = usable_samples;
total_duration = total_samples / fs;

% Resample force onto EMG timeline and keep the same 20 s region.
t_emg = (0:total_samples-1) / fs;
t_force = (0:length(force_signal)-1) / fs_force;
force_resampled = interp1(t_force, force_signal, t_emg, 'linear', 'extrap');

fprintf('Loaded: %s\n', fname)
fprintf('Analysing first %.2f s | %d windows | %d samples/window\n\n', ...
    total_duration, nwin, window_samples)

%% Preallocate pseudo-online outputs
noise_centroids = ones(window_samples, nMUs) .* (centroid(:, 1)');
spike_centroids = ones(window_samples, nMUs) .* (centroid(:, 2)');

esample2 = zeros(nGoodChan * extensionfactor, extensionfactor - 1);
Pulsetrain_online = zeros(nMUs, total_samples);
Distime = false(total_samples, nMUs);

Dischargetimes_online = cell(1, nMUs);
fr_online = cell(1, nMUs);
for mu = 1:nMUs
    Dischargetimes_online{mu} = [];
    fr_online{mu} = [];
end

%% Pseudo-online loop over only the first 20 seconds
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

        if length(Dischargetimes_online{mu}) > 1
            fr_online{mu} = fs ./ diff(Dischargetimes_online{mu});
        end
    end
end

%% Recruitment threshold from force at first detected spike
recruitThresh_online = nan(nMUs, 1);
firstSpike_online = nan(nMUs, 1);

for mu = 1:nMUs
    if ~isempty(Dischargetimes_online{mu})
        firstSpike_online(mu) = Dischargetimes_online{mu}(1);
        recruitThresh_online(mu) = force_resampled(firstSpike_online(mu));
    end
end

% Sort by absolute force threshold. MUs without spikes go last.
sortKey = abs(recruitThresh_online);
sortKey(isnan(sortKey)) = inf;
[~, MU_order_recruitment] = sort(sortKey, 'ascend');

%% Mean firing rate
mean_fr_online = nan(nMUs, 1);
for mu = 1:nMUs
    if ~isempty(fr_online{mu})
        mean_fr_online(mu) = mean(fr_online{mu});
    end
end

%% Plot: force + recruitment-ordered raster + firing rate
time = (0:total_samples-1) / fs;
colors = lines(nMUs);

figure('Color', 'w', 'Position', [60 60 1450 850], ...
    'Name', 'Pseudo-online first 20 s, force, recruitment order');

% Top: spike trains ordered by recruitment threshold + force overlay.
ax1 = subplot(2, 1, 1);

yyaxis(ax1, 'left')
hold(ax1, 'on')
for row = 1:nMUs
    mu = MU_order_recruitment(row);
    spikes = Dischargetimes_online{mu};
    if ~isempty(spikes)
        plot(ax1, spikes / fs, row * ones(size(spikes)), '|', ...
            'Color', colors(mu, :), 'MarkerSize', 10, 'LineWidth', 1.5);
    end
end
hold(ax1, 'off')
ylim(ax1, [0 nMUs + 1])
yticks(ax1, 1:nMUs)
yticklabels(ax1, arrayfun(@(row) label_mu(MU_order_recruitment(row), ...
    recruitThresh_online(MU_order_recruitment(row))), ...
    1:nMUs, 'UniformOutput', false))
ylabel(ax1, 'MUs ')
grid(ax1, 'on')

yyaxis(ax1, 'right')
plot(ax1, time, force_resampled, 'k-', 'LineWidth', 1.4)
ylabel(ax1, 'Force')

xlim(ax1, [0 total_duration])
xlabel(ax1, 'Time (s)')
title(ax1, sprintf('First %.1f s pseudo-online spike trains ', ...
    total_duration))

% Bottom: instantaneous firing rate, same MU order.
ax2 = subplot(2, 1, 2);
hold(ax2, 'on')
for row = 1:nMUs
    mu = MU_order_recruitment(row);
    spikes = Dischargetimes_online{mu};
    if length(spikes) > 1
        fr_t = spikes(2:end) / fs;
        plot(ax2, fr_t, fr_online{mu}, '.', ...
            'Color', colors(mu, :), 'MarkerSize', 6, ...
            'DisplayName', sprintf('MU%d', mu));
    end
end
hold(ax2, 'off')
grid(ax2, 'on')
xlim(ax2, [0 total_duration])
ylim(ax2, [0 60])
xlabel(ax2, 'Time (s)')
ylabel(ax2, 'Instantaneous firing rate (Hz)')
title(ax2, 'Firing rates ')
legend(ax2, 'Location', 'eastoutside', 'FontSize', 6)

%% Summary table
summary_recruitment_order = table( ...
    MU_order_recruitment(:), ...
    recruitThresh_online(MU_order_recruitment), ...
    firstSpike_online(MU_order_recruitment) / fs, ...
    cellfun(@numel, Dischargetimes_online(MU_order_recruitment(:))), ...
    mean_fr_online(MU_order_recruitment), ...
    'VariableNames', {'MU', 'RecruitmentForce', 'FirstSpikeTime_s', ...
                      'SpikeCount', 'MeanFR_Hz'});

disp(' ')
disp('=== Recruitment-threshold order, first 20 seconds ===')
disp(summary_recruitment_order)

fprintf('\nOutputs in workspace:\n')
fprintf('  Dischargetimes_online\n')
fprintf('  Pulsetrain_online\n')
fprintf('  fr_online\n')
fprintf('  mean_fr_online\n')
fprintf('  recruitThresh_online\n')
fprintf('  MU_order_recruitment\n')
fprintf('  summary_recruitment_order\n\n')

%% Local helper
function txt = label_mu(mu, recruitForce)
if isnan(recruitForce)
    txt = sprintf('MU%d | RT: n/a', mu);
else
    txt = sprintf('MU%d | RT: %.2f', mu, recruitForce);
end
end
