%% ===== COMBINED RASTER + FIRING RATE + FORCE PLOT =====

data      = Calib_data;
fs        = 2000;
fs_force  = 50;

%% --- USER-DEFINED PLOT WINDOW ---
t_start = 1;     % start time in seconds
t_end   = 15;    % end time in seconds

%% --- Extract spike train ---
spike_train        = data.spike_train;
[n_samples, n_MUs] = size(spike_train);
t_total            = n_samples / fs;

% Safety: keep requested window inside signal duration
t_start = max(0, t_start);
t_end   = min(t_end, t_total);

if t_start >= t_end
    error('t_start must be smaller than t_end');
end

%% --- Prepare full force signal ---
f_force_all = recordedForce(:, 2);
t_force_all = (0:length(f_force_all)-1) / fs_force;

if abs(length(f_force_all)/fs_force - t_total) > 1
    warning('Force and EMG durations differ by more than 1 sec. Check alignment.')
end

%% --- Get spike times, spike counts, and recruitment thresholds ---
spike_times = cell(1, n_MUs);
n_spikes    = zeros(1, n_MUs);
rec_thresh  = nan(1, n_MUs);

for mu = 1:n_MUs

    idx_all = find(spike_train(:, mu));
    t_all   = idx_all(:)' / fs;

    % Spikes only inside selected plot window
    t_sel = t_all(t_all >= t_start & t_all <= t_end);

    spike_times{mu} = t_sel;
    n_spikes(mu)    = numel(t_sel);

    % Recruitment threshold = force at first spike in full signal
    if ~isempty(t_all)
        first_spike_time = t_all(1);

        [~, force_idx] = min(abs(t_force_all - first_spike_time));

        rec_thresh(mu) = f_force_all(force_idx);
    end

end

%% --- Sort MUs by recruitment threshold ---
[~, mu_order] = sort(rec_thresh);

%% --- Select force data in chosen time window ---
force_mask = (t_force_all >= t_start) & (t_force_all <= t_end);
t_force    = t_force_all(force_mask);
f_force    = f_force_all(force_mask);

%% --- Scale force to MU raster height ---
if ~isempty(f_force) && max(f_force) ~= min(f_force)
    f_scaled = 0.5 + ...
        (f_force - min(f_force)) / (max(f_force) - min(f_force)) * n_MUs;
else
    f_scaled = ones(size(f_force)) * (0.5 + n_MUs/2);
end

%% -------------------------------------------------------
%  COMBINED FIGURE: Raster + Force (top) + Firing Rate (bottom)
%% -------------------------------------------------------

figure('Color','w','Position',[100 100 1200 800]);
colors = lines(n_MUs);

%% --- TOP: Raster Plot + Force overlay ---
subplot(2,1,1);
hold on;

%% --- Plot raster first ---
for row = 1:n_MUs

    mu = mu_order(row);
    t = spike_times{mu};

    if isempty(t)
        continue
    end

    plot([t; t], ...
         repmat([row-0.4; row+0.4], 1, numel(t)), ...
         'Color', colors(mu,:), ...
         'LineWidth', 1.2);

end

%% --- Plot force after raster, so force is in front ---
plot(t_force, f_scaled, 'k-', 'LineWidth', 2.0);

%% --- Spike count label on right side ---
for row = 1:n_MUs

    mu = mu_order(row);

    text(t_end + 0.01*(t_end - t_start), row, ...
        sprintf('%d spikes', n_spikes(mu)), ...
        'Color', colors(mu,:), ...
        'FontSize', 9, ...
        'VerticalAlignment', 'middle');

end

%% --- Left y-axis: sorted MUs ---
yyaxis left

yticks(1:n_MUs);

mu_labels = cell(1, n_MUs);

for row = 1:n_MUs

    mu = mu_order(row);

    mu_labels{row} = sprintf('MU %d  RT %.1f', ...
        mu, rec_thresh(mu));

end

yticklabels(mu_labels);

xlabel('Time (s)');
ylabel('Motor Unit  Recruitment Threshold');
title('Raster Plot ');

xlim([t_start, t_end + 0.15*(t_end - t_start)]);
ylim([0.5 n_MUs + 0.5]);

grid on;
box on;

%% --- Right y-axis: force values ---
yyaxis right

ylabel('Force');

if ~isempty(f_force)

    force_ticks = linspace(min(f_force), max(f_force), 5);

    scaled_force_ticks = 0.5 + ...
        (force_ticks - min(f_force)) / ...
        (max(f_force) - min(f_force)) * n_MUs;

    yticks(scaled_force_ticks);

    yticklabels(arrayfun(@(x) sprintf('%.1f', x), ...
        force_ticks, 'UniformOutput', false));

end

ylim([0.5 n_MUs + 0.5]);
set(gca, 'YColor', 'k');

%% --- BOTTOM: Instantaneous Firing Rate ---
subplot(2,1,2);
hold on;

for row = 1:n_MUs

    mu = mu_order(row);

    idx_all = find(spike_train(:, mu));
    t_all   = idx_all(:)' / fs;

    if numel(t_all) < 2
        continue
    end

    isi  = diff(t_all);
    ifr  = 1 ./ isi;
    t_fr = t_all(1:end-1) + isi/2;

    fr_mask = (t_fr >= t_start) & (t_fr <= t_end);

    plot(t_fr(fr_mask), ifr(fr_mask), ...
        'Color', colors(mu,:), ...
        'LineWidth', 1.5, ...
        'DisplayName', sprintf('MU %d  (%d spikes)', ...
        mu, n_spikes(mu)));

end

xlabel('Time (s)');
ylabel('Firing Rate (pps)');
title('Instantaneous Firing Rate per Motor Unit');

xlim([t_start t_end]);

legend('Location','northeast','FontSize',9);

grid on;
box on;

%% --- Shared title ---
sgtitle(sprintf('MU decomposition( %.2f s to %.2f s )', ...
    t_start, t_end), ...
    'FontSize', 14, ...
    'FontWeight', 'bold');
