%% =========================================================================
% PSEUDO-ONLINE EMG DECOMPOSITION
% Based on decompose3.m pipeline
%
% INPUTS (must exist in workspace):
%   recordedEMG  : raw EMG (nChannels x nSamples)
%   Calib_data   : output struct from decompose3
%   fs           : sampling frequency (Hz)
%
% OUTPUTS:
%   Dischargetimes_online : cell (1 x nMUs) — spike indices per MU
%   Pulsetrain            : matrix (nMUs x nSamples) — pulse amplitudes
%   fr_online             : cell (1 x nMUs) — instantaneous firing rates
%   mean_fr_online        : vector (nMUs x 1) — mean firing rate per MU
%   rate_of_agreement     : vector (1 x nMUs) — RoA vs offline
%% =========================================================================

%% -------------------------------------------------------------------------
%  SECTION 1: PARAMETERS
% -------------------------------------------------------------------------

fs          = 2000;       % sampling frequency (Hz)
badchan     = [];         % bad channels to exclude
window_sec  = 0.125;      % chunk size in seconds (250 samples at 2000Hz)

% Derived
window_samples = round(window_sec * fs);
total_samples  = size(recordedEMG, 2);
nwin           = floor(total_samples / window_samples);
total_duration = total_samples / fs;

fprintf('=== Pseudo-Online Decomposition ===\n')
fprintf('Signal duration:  %.1f seconds\n', total_duration)
fprintf('Window size:      %d samples (%.3f sec)\n', window_samples, window_sec)
fprintf('Total windows:    %d\n', nwin)

%% -------------------------------------------------------------------------
%  SECTION 2: PREPARE EMG MASK AND MU FILTERS
% -------------------------------------------------------------------------

% Build EMG mask (1 = bad channel, 0 = good channel)
EMGmask = zeros(size(recordedEMG,1), 1);
EMGmask(badchan) = 1;

fprintf('Good channels:    %d / %d\n', sum(EMGmask==0), length(EMGmask))

% Load MU filters from calibration
MUFilters = Calib_data.MUFilters;   % (nExtChan x nMUs)
nMUs      = size(MUFilters, 2);

fprintf('Motor units:      %d\n\n', nMUs)

%% -------------------------------------------------------------------------
%  SECTION 3: COMPUTE ONLINE PARAMETERS (once before loop)
% -------------------------------------------------------------------------

fprintf('Computing online parameters...\n')

[extensionfactor, iReSIG, norm, centroid] = getonlineparameters(recordedEMG, EMGmask, MUFilters, fs);

fprintf('Extension factor: %d\n', extensionfactor)
fprintf('iReSIG:           %d x %d\n', size(iReSIG))
fprintf('norm:             %d x %d\n', size(norm))
fprintf('centroid:         %d x %d\n\n', size(centroid))

% Precompute combined filter (used every chunk — done ONCE)
MUfilt = MUFilters' * iReSIG;   % (nMUs x nExtChan)

% Centroid matrices (fixed size = window_samples)
noise_centroids = ones(window_samples, nMUs) .* (centroid(:,1)');
spike_centroids = ones(window_samples, nMUs) .* (centroid(:,2)');

%% -------------------------------------------------------------------------
%  SECTION 4: PSEUDO-ONLINE LOOP
% -------------------------------------------------------------------------

fprintf('Running pseudo-online loop...\n')

% Initialize buffer (carries extension overlap between chunks — critical!)
esample2 = zeros(sum(EMGmask==0) * extensionfactor, extensionfactor-1);

% Preallocate outputs
Pulsetrain = zeros(nMUs, nwin * window_samples);
Distime    = zeros(nwin * window_samples, nMUs);

% Process chunk by chunk
for k = 1:nwin
    start_idx = (k-1) * window_samples + 1;
    end_idx   =  k    * window_samples;

    % Get current chunk (good channels only)
    chunk = recordedEMG(EMGmask==0, start_idx:end_idx);

    % Get spikes online
    [Pulsetrain(:, start_idx:end_idx), ...
     Distime(start_idx:end_idx, :), ...
     esample2] = getspikesonline(chunk, extensionfactor, esample2, ...
                                  MUfilt, norm, noise_centroids, ...
                                  spike_centroids, window_samples, fs);

    % Progress
    if mod(k, 100) == 0
        fprintf('  Window %d / %d  (%.1f sec)\n', k, nwin, end_idx/fs)
    end
end

fprintf('Loop complete.\n\n')

% Convert Distime matrix to cell array of spike indices
Dischargetimes_online = cell(1, nMUs);
for mu = 1:nMUs
    Dischargetimes_online{mu} = find(Distime(:, mu));
end

%% -------------------------------------------------------------------------
%  SECTION 5: COMPUTE FIRING RATES
% -------------------------------------------------------------------------

fr_online      = cell(1, nMUs);
mean_fr_online = zeros(nMUs, 1);

for mu = 1:nMUs
    spikes = Dischargetimes_online{mu};
    if length(spikes) > 1
        fr_online{mu}      = 1 ./ (diff(spikes) / fs);   % instantaneous FR (Hz)
        mean_fr_online(mu) = mean(fr_online{mu});
    else
        fr_online{mu}      = [];
        mean_fr_online(mu) = 0;
    end
end

%% -------------------------------------------------------------------------
%  SECTION 6: COMPARE ONLINE VS OFFLINE (Rate of Agreement)
% -------------------------------------------------------------------------

tolerance = round(fs * 0.010);  % 10ms tolerance
fprintf('=== Online vs Offline Comparison (tolerance = %d samples / 10ms) ===\n', tolerance)

sensitivity       = zeros(1, nMUs);
precision         = zeros(1, nMUs);
rate_of_agreement = zeros(1, nMUs);

for mu = 1:nMUs
    offline_spikes = Calib_data.MUPulses{mu};
    online_spikes  = Dischargetimes_online{mu};

    matched_online  = false(size(online_spikes));
    matched_offline = false(size(offline_spikes));

    for i = 1:length(offline_spikes)
        candidates = find(abs(online_spikes - offline_spikes(i)) <= tolerance);
        for c = candidates'
            if ~matched_online(c)
                matched_online(c)  = true;
                matched_offline(i) = true;
                break;
            end
        end
    end

    TP = sum(matched_offline);
    FN = sum(~matched_offline);
    FP = sum(~matched_online);

    if (TP + FN) > 0; sensitivity(mu)       = TP / (TP + FN); end
    if (TP + FP) > 0; precision(mu)         = TP / (TP + FP); end
    if (TP+FN+FP) > 0; rate_of_agreement(mu) = TP / (TP + FN + FP); end
end

% Print table
fprintf('%-6s %-10s %-10s %-8s %-8s %-8s\n', 'MU','Offline','Online','Sens','Prec','RoA(%)')
fprintf('%s\n', repmat('-',1,55))
for mu = 1:nMUs
    fprintf('%-6d %-10d %-10d %-8.2f %-8.2f %-8.1f\n', ...
        mu, length(Calib_data.MUPulses{mu}), length(Dischargetimes_online{mu}), ...
        sensitivity(mu), precision(mu), rate_of_agreement(mu)*100)
end
fprintf('%s\n', repmat('-',1,55))
fprintf('\nSensitivity:       %.2f ± %.2f\n', mean(sensitivity), std(sensitivity))
fprintf('Precision:         %.2f ± %.2f\n',   mean(precision),   std(precision))
fprintf('Rate of Agreement: %.2f ± %.2f\n\n', mean(rate_of_agreement), std(rate_of_agreement))

%% -------------------------------------------------------------------------
%  SECTION 7: PLOT — RASTER + FIRING RATE + ROA
% -------------------------------------------------------------------------

time = linspace(0, total_duration, nwin * window_samples);

figure('Color','w', 'Position',[50 50 1400 900], 'Name','Pseudo-Online Decomposition');

% --- Panel 1: Raster plot (online vs offline overlaid) ---
ax1 = subplot(3,1,1);
hold on
for mu = 1:nMUs
    % Offline — green
    off_t = Calib_data.MUPulses{mu} / fs;
    plot(off_t, mu*ones(size(off_t)), '|', ...
        'Color',[0.18 0.72 0.18], 'MarkerSize',10, 'LineWidth',1.2)
    % Online — blue
    on_t = Dischargetimes_online{mu} / fs;
    plot(on_t, mu*ones(size(on_t))+0.3, '|', ...
        'Color',[0.20 0.45 0.90], 'MarkerSize',6, 'LineWidth',0.8)
end
% Legend proxies
plot(nan, nan, '|', 'Color',[0.18 0.72 0.18], 'MarkerSize',10, 'DisplayName','Offline')
plot(nan, nan, '|', 'Color',[0.20 0.45 0.90], 'MarkerSize',6,  'DisplayName','Online')
legend('Location','northeast','FontSize',8)
title('Motor Unit Spike Trains — Online vs Offline','FontSize',11)
xlabel('Time (s)'); ylabel('Motor Unit #')
yticks(1:nMUs)
yticklabels(arrayfun(@(x) sprintf('MU%d',x), 1:nMUs, 'UniformOutput',false))
xlim([0 total_duration]); ylim([0 nMUs+1])
grid on; set(ax1,'FontSize',8)

% --- Panel 2: Instantaneous firing rates ---
ax2 = subplot(3,1,2);
hold on
colors = lines(nMUs);
for mu = 1:nMUs
    spikes = Dischargetimes_online{mu};
    if length(spikes) > 1
        spike_times = spikes(1:end-1) / fs;
        plot(spike_times, fr_online{mu}, '.', ...
            'Color',colors(mu,:), 'MarkerSize',3, ...
            'DisplayName', sprintf('MU%d (%.1fHz)', mu, mean_fr_online(mu)))
    end
end
title('Instantaneous Firing Rates (Online)','FontSize',11)
xlabel('Time (s)'); ylabel('Firing Rate (Hz)')
xlim([0 total_duration]); ylim([0 60])
legend('Location','eastoutside','FontSize',6,'NumColumns',2)
grid on; set(ax2,'FontSize',8)

% --- Panel 3: Rate of Agreement per MU ---
ax3 = subplot(3,1,3);
b = bar(rate_of_agreement * 100, 'FaceColor','flat');
for mu = 1:nMUs
    if rate_of_agreement(mu) >= 0.85
        b.CData(mu,:) = [0.18 0.72 0.18];   % green
    elseif rate_of_agreement(mu) >= 0.70
        b.CData(mu,:) = [1.00 0.75 0.00];   % yellow
    else
        b.CData(mu,:) = [0.85 0.20 0.20];   % red
    end
end
hold on
yline(mean(rate_of_agreement)*100, 'k--', 'LineWidth',2, ...
    'Label',sprintf('Mean=%.1f%%', mean(rate_of_agreement)*100), ...
    'LabelHorizontalAlignment','left','FontSize',9)
for mu = 1:nMUs
    text(mu, rate_of_agreement(mu)*100+1.5, ...
        sprintf('%.0f%%', rate_of_agreement(mu)*100), ...
        'HorizontalAlignment','center','FontSize',7)
end
xlabel('Motor Unit #'); ylabel('Rate of Agreement (%)')
title('Online vs Offline: Rate of Agreement','FontSize',11)
xticks(1:nMUs)
xticklabels(arrayfun(@(x) sprintf('MU%d',x), 1:nMUs, 'UniformOutput',false))
ylim([0 105]); grid on; set(ax3,'FontSize',8)

sgtitle(sprintf('Pseudo-Online EMG Decomposition  |  %d MUs  |  Sens=%.2f  Prec=%.2f  RoA=%.2f', ...
    nMUs, mean(sensitivity), mean(precision), mean(rate_of_agreement)), ...
    'FontSize',12,'FontWeight','bold')

fprintf('Done! Figure ready.\n')
