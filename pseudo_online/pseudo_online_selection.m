%% =========================================================================
% PSEUDO-ONLINE EMG DECOMPOSITION — REAL-TIME VERSION
% Plot updates every chunk (0.125s window)
%
% INPUTS (must exist in workspace):
%   recordedEMG  : raw EMG from CALIBRATION (nChannels x nSamples)
%   Calib_data   : output struct from decompose3
%   fs           : sampling frequency (Hz)
% =========================================================================

%% -------------------------------------------------------------------------
%  SECTION 1: PARAMETERS
% -------------------------------------------------------------------------

fs             = 2000;
badchan        = [];
window_sec     = 0.125;
window_samples = round(window_sec * fs);   % 250 samples

fprintf('=== Pseudo-Online Decomposition ===\n')

%% -------------------------------------------------------------------------
%  SECTION 2: PREPARE FILTERS AND ONLINE PARAMETERS
%             (computed on calibration signal — ISpin behaviour)
% -------------------------------------------------------------------------

EMGmask   = zeros(size(recordedEMG, 1), 1);
EMGmask(badchan) = 1;

MUFilters = Calib_data.MUFilters;
nMUs      = size(MUFilters, 2);

fprintf('Computing online parameters on calibration signal...\n')
[extensionfactor, iReSIG, norm, centroid] = getonlineparameters( ...
    recordedEMG, EMGmask, MUFilters, fs);

% Precompute combined filter (fixed — derived from calibration)
MUfilt          = MUFilters' * iReSIG;
noise_centroids = ones(window_samples, nMUs) .* (centroid(:,1)');
spike_centroids = ones(window_samples, nMUs) .* (centroid(:,2)');

fprintf('Online parameters ready. %d MUs loaded.\n\n', nMUs)

%% -------------------------------------------------------------------------
%  SECTION 3: LOAD NEW SAMPLE VIA FILE BROWSER
% -------------------------------------------------------------------------

fprintf('Select the new sample .mat file...\n')
[fname, fpath] = uigetfile('*.mat', 'Select new sample .mat file');

if isequal(fname, 0)
    error('No file selected. Aborting.')
end

newdata = load(fullfile(fpath, fname), 'recordedEMG');

if ~isfield(newdata, 'recordedEMG')
    error('Variable ''recordedEMG'' not found in selected file: %s', fname)
end

newEMG = newdata.recordedEMG;

% Validate channel count matches calibration
if size(newEMG, 1) ~= size(recordedEMG, 1)
    error('Channel mismatch: calibration has %d channels, new sample has %d.', ...
        size(recordedEMG, 1), size(newEMG, 1))
end

total_samples  = size(newEMG, 2);
nwin           = floor(total_samples / window_samples);
total_duration = total_samples / fs;

fprintf('Loaded: %s\n', fname)
fprintf('Duration: %.1f sec | Windows: %d | Chunk: %d samples\n\n', ...
    total_duration, nwin, window_samples)

%% -------------------------------------------------------------------------
%  SECTION 4: SETUP LIVE FIGURE
% -------------------------------------------------------------------------

colors = lines(nMUs);

fig = figure('Color','w', 'Position',[50 50 1400 800], ...
    'Name', sprintf('Pseudo-Online Decomposition — %s', fname));

% --- Raster axes ---
ax_raster = subplot(2,1,1);
hold(ax_raster, 'on')
title(ax_raster, 'Real-Time Spike Trains', 'FontSize',11)
xlabel(ax_raster, 'Time (s)')
ylabel(ax_raster, 'Motor Unit #')
xlim(ax_raster, [0 total_duration])
ylim(ax_raster, [0 nMUs+1])
yticks(ax_raster, 1:nMUs)
yticklabels(ax_raster, arrayfun(@(x) sprintf('MU%d',x), 1:nMUs, 'UniformOutput',false))
grid(ax_raster, 'on')
set(ax_raster, 'FontSize', 8)

% --- Firing rate axes ---
ax_fr = subplot(2,1,2);
hold(ax_fr, 'on')
title(ax_fr, 'Instantaneous Firing Rate (Hz)', 'FontSize',11)
xlabel(ax_fr, 'Time (s)')
ylabel(ax_fr, 'Firing Rate (Hz)')
xlim(ax_fr, [0 total_duration])
ylim(ax_fr, [0 60])
grid(ax_fr, 'on')
set(ax_fr, 'FontSize', 8)

% Create one plot handle per MU for raster
h_raster = gobjects(nMUs, 1);
for mu = 1:nMUs
    h_raster(mu) = plot(ax_raster, nan, nan, '|', ...
        'Color', colors(mu,:), 'MarkerSize',10, 'LineWidth',1.5);
end

% Create one plot handle per MU for firing rate
h_fr = gobjects(nMUs, 1);
for mu = 1:nMUs
    h_fr(mu) = plot(ax_fr, nan, nan, '.', ...
        'Color', colors(mu,:), 'MarkerSize', 4, ...
        'DisplayName', sprintf('MU%d', mu));
end
legend(ax_fr, 'Location','eastoutside', 'FontSize',6)

% Time indicator lines
tline_raster = xline(ax_raster, 0, 'r--', 'LineWidth', 1.5);
tline_fr     = xline(ax_fr,     0, 'r--', 'LineWidth', 1.5);

%% -------------------------------------------------------------------------
%  SECTION 5: REAL-TIME LOOP (runs on newEMG)
% -------------------------------------------------------------------------

% Initialise carry-over buffer for online extension
esample2 = zeros(sum(EMGmask==0)*extensionfactor, extensionfactor-1);

Pulsetrain = zeros(nMUs, nwin*window_samples);
Distime    = zeros(nwin*window_samples, nMUs);

Dischargetimes_online = cell(1, nMUs);
fr_online             = cell(1, nMUs);
for mu = 1:nMUs
    Dischargetimes_online{mu} = [];
    fr_online{mu}             = [];
end

fprintf('Starting real-time loop on new sample...\n')

for k = 1:nwin
    start_idx    = (k-1)*window_samples + 1;
    end_idx      =  k   *window_samples;
    current_time =  end_idx / fs;

    %--- Process current chunk (from NEW sample) ---%
    chunk = newEMG(EMGmask==0, start_idx:end_idx);

    [Pulsetrain(:,start_idx:end_idx), ...
     Distime(start_idx:end_idx,:), ...
     esample2] = getspikesonline(chunk, extensionfactor, esample2, ...
                                  MUfilt, norm, noise_centroids, ...
                                  spike_centroids, window_samples, fs);

    %--- Accumulate new spikes ---%
    for mu = 1:nMUs
        new_spikes = find(Distime(start_idx:end_idx, mu)) + start_idx - 1;
        Dischargetimes_online{mu} = [Dischargetimes_online{mu}; new_spikes];

        if length(Dischargetimes_online{mu}) > 1
            all_spikes    = Dischargetimes_online{mu};
            fr_online{mu} = 1 ./ (diff(all_spikes) / fs);
        end
    end

    %--- Update raster plot ---%
    for mu = 1:nMUs
        spikes_t = Dischargetimes_online{mu} / fs;
        if ~isempty(spikes_t)
            set(h_raster(mu), 'XData', spikes_t, ...
                              'YData', mu * ones(size(spikes_t)))
        end
    end

    %--- Update firing rate plot ---%
    for mu = 1:nMUs
        if length(Dischargetimes_online{mu}) > 1
            spike_times = Dischargetimes_online{mu}(1:end-1) / fs;
            set(h_fr(mu), 'XData', spike_times, ...
                          'YData', fr_online{mu})
        end
    end

    %--- Move time indicator ---%
    set(tline_raster, 'Value', current_time)
    set(tline_fr,     'Value', current_time)

    %--- Update title ---%
    title(ax_raster, sprintf('Real-Time Spike Trains  |  t = %.2f / %.2f sec  |  %s', ...
        current_time, total_duration, fname), 'FontSize',11)

    drawnow limitrate
end

%% -------------------------------------------------------------------------
%  SECTION 6: FINAL SUMMARY
% -------------------------------------------------------------------------

title(ax_raster, sprintf('Done  |  %d MUs  |  %.1f s  |  %s', ...
    nMUs, total_duration, fname), 'FontSize',11)

% Compute mean firing rate per MU
mean_fr_online = zeros(nMUs, 1);
for mu = 1:nMUs
    if ~isempty(fr_online{mu})
        mean_fr_online(mu) = mean(fr_online{mu});
    end
end

fprintf('\n=== Done ===\n')
for mu = 1:nMUs
    fprintf('MU %2d: %d spikes  |  Mean FR = %.1f Hz\n', ...
        mu, length(Dischargetimes_online{mu}), ...
        mean_fr_online(mu))
end
