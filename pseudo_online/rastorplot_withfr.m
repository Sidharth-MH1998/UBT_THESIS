%% ===== COMBINED RASTER + FIRING RATE + FORCE PLOT =====
data  = Calib_data;
fs    = 2000;
fs_force = 50;

%% --- Extract spike train ---
spike_train         = data.spike_train;
[n_samples, n_MUs]  = size(spike_train);
t_total             = n_samples / fs;

%% --- Get spike times per MU ---
spike_times = cell(1, n_MUs);
n_spikes    = zeros(1, n_MUs);
for mu = 1:n_MUs
    idx             = find(spike_train(:, mu));
    spike_times{mu} = idx(:)' / fs;
    n_spikes(mu)    = numel(idx);
end

%% --- Prepare force signal ---
% recordedEMG and recordedForce are both already cropped to same session
% Same duration: 156000/2000 = 3900/50 = 78 sec
% → no time offset needed, just build matching time axis
f_force = recordedForce(:, 2);
t_force = (0:length(f_force)-1) / fs_force;

% Sanity check — warn if durations differ by more than 1 sec
if abs(length(f_force)/fs_force - t_total) > 1
    warning('Force and EMG durations differ by more than 1 sec. Check alignment.')
end

%% -------------------------------------------------------
%  COMBINED FIGURE: Raster + Force (top) + Firing Rate (bottom)
%% -------------------------------------------------------

figure('Color','w','Position',[100 100 1200 800]);
colors = lines(n_MUs);

%% --- TOP: Raster Plot + Force overlay ---
subplot(2,1,1);
hold on;
for mu = 1:n_MUs
    t = spike_times{mu};
    if isempty(t), continue; end
    plot([t; t], repmat([mu-0.4; mu+0.4], 1, numel(t)), ...
        'Color', colors(mu,:), 'LineWidth', 1.2);
end

% Spike count label on right side of each MU row
for mu = 1:n_MUs
    text(t_total * 1.01, mu, sprintf('%d spikes', n_spikes(mu)), ...
        'Color', colors(mu,:), 'FontSize', 9, 'VerticalAlignment', 'middle');
end

% --- Overlay force trace on raster plot ---
% Scale force to fit within MU y-axis range [0.5, n_MUs+0.5]
% so it sits underneath the spike ticks without obscuring them
f_scaled = 0.5 + (f_force - min(f_force)) / ...
           (max(f_force) - min(f_force)) * n_MUs;
plot(t_force, f_scaled, 'k-', 'LineWidth', 1.5, ...
    'DisplayName', 'Force');

% Add a second y-axis on the right showing real force values
yyaxis right
ylabel('Force');
yticks(linspace(0.5, n_MUs+0.5, 5));
yticklabels(arrayfun(@(x) sprintf('%.1f', x), ...
    linspace(min(f_force), max(f_force), 5), 'UniformOutput', false));
set(gca, 'YColor', 'k');
yyaxis left

yticks(1:n_MUs);
yticklabels(arrayfun(@(x) sprintf('MU %d', x), 1:n_MUs, 'UniformOutput', false));
xlabel('Time (s)');
ylabel('Motor Unit');
title('Raster Plot — Motor Unit Spike Trains + Force');
xlim([0 t_total * 1.15]);
ylim([0.5 n_MUs + 0.5]);
grid on; box on;

%% --- BOTTOM: Instantaneous Firing Rate ---
subplot(2,1,2);
hold on;
for mu = 1:n_MUs
    t = spike_times{mu};
    if numel(t) < 2, continue; end
    isi  = diff(t);
    ifr  = 1 ./ isi;
    t_fr = t(1:end-1) + isi/2;   % plot FR at midpoint between spikes
    plot(t_fr, ifr, 'Color', colors(mu,:), 'LineWidth', 1.5, ...
        'DisplayName', sprintf('MU %d  (%d spikes)', mu, n_spikes(mu)));
end
xlabel('Time (s)');
ylabel('Firing Rate (pps)');
title('Instantaneous Firing Rate per Motor Unit');
xlim([0 t_total]);
legend('Location','northeast','FontSize',9);
grid on; box on;

%% --- Shared title ---
sgtitle('Motor Unit Spike Train Analysis', 'FontSize', 14, 'FontWeight', 'bold');
