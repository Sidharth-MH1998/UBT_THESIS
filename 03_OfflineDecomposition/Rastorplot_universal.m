%% =========================================================================
% RASTER PLOT FOR MUEDIT SIGNAL/PARAMETERS RESULTS
%
% This script plots the selected time interval.
% Leave plot_start_sec and plot_stop_sec empty ([]) to plot the full
% available recording.
%
% Required in the workspace:
%   signal      - MUedit signal structure containing discharge times
%   parameters  - decomposition parameter structure
%
% Optional overlay:
%   recordedForce(:,2) is plotted when plot_force_overlay is enabled.
% =========================================================================

%% USER SETTINGS
assert(exist('signal','var') == 1, ...
    'signal is not loaded in the workspace.');
assert(exist('parameters','var') == 1, ...
    'parameters is not loaded in the workspace.');

fs = signal.fsamp;         % Sampling frequency saved with the EMG
fs_force = 50;             % recordedForce sampling frequency in Hz

plot_force_overlay = 0;    % 1 = plot force on raster, 0 = no force

plot_start_sec = [];       % Start time in seconds. [] = start at 0 s
plot_stop_sec = [];        % Stop time in seconds. [] = use full recording

plot_firing_rate = 1;      % 1 = add firing-rate subplot, 0 = raster only
fr_ylim = [0 60];          % Firing-rate y-axis limits in Hz

%% GET SPIKES
[spike_times_all, source_name, n_samples] = get_spike_times_from_signal(signal);
n_MUs = numel(spike_times_all);

if n_MUs == 0
    error('No motor units found to plot.')
end

recording_stop_sec = n_samples / fs;

if isempty(plot_start_sec)
    plot_start_sec = 0;
end

if isempty(plot_stop_sec)
    plot_stop_sec = recording_stop_sec;
end

plot_start_sec = max(0, plot_start_sec);
plot_stop_sec = min(plot_stop_sec, recording_stop_sec);

if plot_stop_sec <= plot_start_sec
    error('plot_stop_sec must be greater than plot_start_sec.')
end

%% KEEP ONLY THE REQUESTED TIME INTERVAL
spike_times = cell(1, n_MUs);
n_spikes = zeros(1, n_MUs);
first_spike_sec = inf(1, n_MUs);

for mu = 1:n_MUs
    t = spike_times_all{mu};
    t = t(t >= plot_start_sec & t <= plot_stop_sec);

    spike_times{mu} = t(:).';
    n_spikes(mu) = numel(t);

    if ~isempty(t)
        first_spike_sec(mu) = t(1);
    end
end

% Always plot first-spiking MU first. MUs without spikes in the selected
% interval are placed at the bottom.
[~, mu_order] = sort(first_spike_sec, 'ascend');

%% PREPARE FORCE, IF REQUESTED
force_time = [];
force_signal = [];
force_available = false;

if plot_force_overlay
    if exist('recordedForce','var') ~= 1 || isempty(recordedForce)
        warning(['recordedForce was not found. Plotting without a ' ...
            'force overlay.'])
        plot_force_overlay = false;
    elseif size(recordedForce,2) < 2
        warning(['recordedForce does not contain column 2. Plotting ' ...
            'without a force overlay.'])
        plot_force_overlay = false;
    else
        force_signal = recordedForce(:,2);
        force_signal = force_signal(:).';
        force_time = (0:numel(force_signal)-1)/fs_force;

        keep_force = force_time >= plot_start_sec & force_time <= plot_stop_sec;
        force_time = force_time(keep_force);
        force_signal = force_signal(keep_force);
        force_available = ~isempty(force_signal);

        if ~force_available
            warning('No force samples found in the selected time interval.')
            plot_force_overlay = false;
        end
    end
end

%% PLOT
colors = lines(n_MUs);

if plot_firing_rate
    figure_height = 760;
else
    figure_height = 470;
end

figure('Color', 'w', 'Position', [80 80 1350 figure_height], ...
    'Name', 'Ultimate raster plot');

if plot_firing_rate
    ax_raster = subplot(2, 1, 1);
else
    ax_raster = axes;
end

plot_raster_panel(ax_raster, spike_times, mu_order, n_spikes, colors, ...
    plot_start_sec, plot_stop_sec, plot_force_overlay, ...
    force_time, force_signal);

if plot_firing_rate
    ax_fr = subplot(2, 1, 2);
    plot_firing_rate_panel(ax_fr, spike_times, mu_order, colors, ...
        plot_start_sec, plot_stop_sec, fs, fr_ylim);
end

title_text = sprintf('Motor unit raster plot, %.2f to %.2f s | %s', ...
    plot_start_sec, plot_stop_sec, source_name);
sgtitle(title_text, 'FontSize', 12, 'FontWeight', 'bold', ...
    'Interpreter', 'none')

%% PRINT SUMMARY
summary_table = table( ...
    mu_order(:), ...
    n_spikes(mu_order(:)).', ...
    first_spike_sec(mu_order(:)).', ...
    'VariableNames', {'MU', 'Spike Count', 'First SpikeTime'});

disp(' ')
disp('=== Raster plot summary ===')
disp(summary_table)

%% LOCAL FUNCTIONS
function [spike_times,source_name,n_samples] = ...
        get_spike_times_from_signal(signal)

requiredFields = {'data','fsamp','Dischargetimes'};
for fieldIdx = 1:numel(requiredFields)
    if ~isfield(signal,requiredFields{fieldIdx})
        error('signal.%s is missing.',requiredFields{fieldIdx});
    end
end

if ~iscell(signal.Dischargetimes) || isempty(signal.Dischargetimes)
    error('signal.Dischargetimes must be a non-empty cell array.');
end
if ~isscalar(signal.fsamp) || ~isfinite(signal.fsamp) || ...
        signal.fsamp <= 0
    error('signal.fsamp must be a positive sampling frequency.');
end

n_samples = size(signal.data,2);
discharges = signal.Dischargetimes(1,:);
spike_times = cell(1,numel(discharges));

for mu = 1:numel(discharges)
    samples = unique(round(discharges{mu}(:).'),'sorted');
    samples = samples(isfinite(samples) & samples >= 1 & ...
        samples <= n_samples);
    spike_times{mu} = samples/signal.fsamp;
end

source_name = 'signal.Dischargetimes';
end

function plot_raster_panel(ax, spike_times, mu_order, n_spikes, colors, ...
    plot_start_sec, plot_stop_sec, plot_force_overlay, ...
    force_time, force_signal)

n_MUs = numel(mu_order);
axes(ax)

if plot_force_overlay
    yyaxis(ax, 'left')
end

hold(ax, 'on')

for row = 1:n_MUs
    mu = mu_order(row);
    t = spike_times{mu};

    if isempty(t)
        continue
    end

    x_tick = [t; t; nan(size(t))];
    y_tick = [ ...
        (row - 0.4) * ones(size(t)); ...
        (row + 0.4) * ones(size(t)); ...
        nan(size(t))];

    plot(ax, x_tick(:), y_tick(:), ...
        'Color', colors(mu, :), ...
        'LineStyle', '-', ...
        'Marker', 'none', ...
        'LineWidth', 1.2)
end

hold(ax, 'off')

ylim(ax, [0.5 n_MUs + 0.5])
xlim(ax, [plot_start_sec plot_stop_sec])
yticks(ax, 1:n_MUs)
yticklabels(ax, make_mu_labels(mu_order, n_spikes))
xlabel(ax, 'Time (s)')
ylabel(ax, 'Motor unit')
title(ax, '')
grid(ax, 'on')
box(ax, 'on')

if plot_force_overlay
    force_min = min(force_signal);
    force_max = max(force_signal);

    if force_max == force_min
        force_scaled = ones(size(force_signal)) * 0.5;
        force_labels = force_min * ones(1, 5);
    else
        force_scaled = 0.5 + (force_signal - force_min) ./ ...
            (force_max - force_min) * n_MUs;
        force_labels = linspace(force_min, force_max, 5);
    end

    yyaxis(ax, 'left')
    hold(ax, 'on')
    plot(ax, force_time, force_scaled, 'k-', ...
        'LineStyle', '-', ...
        'Marker', 'none', ...
        'LineWidth', 1.4)
    hold(ax, 'off')

    yyaxis(ax, 'right')
    ylim(ax, [0.5 n_MUs + 0.5])
    yticks(ax, linspace(0.5, n_MUs + 0.5, 5))
    yticklabels(ax, arrayfun(@(x) sprintf('%.2f', x), ...
        force_labels, 'UniformOutput', false))
    ylabel(ax, 'Force')
    set(ax, 'YColor', 'k')
    yyaxis(ax, 'left')
end
end

function labels = make_mu_labels(mu_order, n_spikes)
labels = cell(1, numel(mu_order));

for row = 1:numel(mu_order)
    mu = mu_order(row);
    labels{row} = sprintf('MU%d  (%d spikes)', mu, n_spikes(mu));
end
end

function plot_firing_rate_panel(ax, spike_times, mu_order, colors, ...
    plot_start_sec, plot_stop_sec, fs, fr_ylim)

hold(ax, 'on')

for row = 1:numel(mu_order)
    mu = mu_order(row);
    t = spike_times{mu};

    if numel(t) < 2
        continue
    end

    isi = diff(t);
    fr = 1 ./ isi;
    fr_time = t(1:end-1) + isi / 2;

    plot(ax, fr_time, fr, '.', ...
        'Color', colors(mu, :), ...
        'MarkerSize', 8, ...
        'DisplayName', sprintf('MU%d', mu))
end

hold(ax, 'off')
xlim(ax, [plot_start_sec plot_stop_sec])
ylim(ax, fr_ylim)
xlabel(ax, 'Time (s)')
ylabel(ax, 'Firing rate (Hz)')
title(ax, 'Instantaneous firing rate')
grid(ax, 'on')
box(ax, 'on')
legend(ax, 'Location', 'eastoutside', 'FontSize', 7)

if nargin > 6 && fs <= 0
    error('fs must be positive.')
end
end
