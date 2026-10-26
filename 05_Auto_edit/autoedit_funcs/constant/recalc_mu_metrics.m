function metrics = recalc_mu_metrics(spike_trains, emg_sig, fs, bad_channels)
% RECALC_MU_METRICS Computes physiological metrics for a set of spike trains.
% Created initially for recalculations needed after MU spike train edition.
% Inputs:
%   spike_trains: Cell array of spike indices {1 x N_MUs}
%   emg_sig:      Raw/Preprocessed EMG matrix (Channels x Samples)
%   fs:           Sampling frequency (Hz)
%   bad_channels: Vector of bad channel indices (to set as NaN)
%
% Output: 'metrics' struct containing:
%   - MUPulses: The input spike trains
%   - MUAPs: Cell array of waveforms (Channels x Window)
%   - p2ps: Matrix of peak-to-peak amplitudes (Channels x MUs)
%   - MU_locs: Vector of channel indices with max amplitude
%   - mean_fr: Vector of mean firing rates
%   - CoV: Vector of Coefficient of Variation of ISI
%   - ISI: Cell array of Inter-Spike Intervals
% 
% Author: Renato Mio (02.12.2025)

    num_mus = length(spike_trains);
    num_channels = size(emg_sig, 1);
    
    % Initialize outputs
    metrics.MUPulses = spike_trains;
    metrics.MUAPs = cell(1, num_mus);
    metrics.p2ps = zeros(num_channels, num_mus);
    metrics.MU_locs = zeros(num_mus, 1);
    metrics.mean_fr = zeros(num_mus, 1);
    metrics.CoV = zeros(num_mus, 1);
    metrics.ISI = cell(1, num_mus);
    
    % MUAP Window Parameters (0.025s as per your previous code)
    win_sec = 0.025; 
    win_samples = round(win_sec * fs);
    
    for mu = 1:num_mus
        spikes = spike_trains{mu};
        
        if length(spikes) < 2
            % Handle empty/sparse MUs
            metrics.MUAPs{mu} = NaN(num_channels, 2*win_samples+1);
            metrics.p2ps(:, mu) = NaN;
            continue;
        end
        
        % 1. Discharge Statistics
        isi_sec = diff(spikes) / fs;
        metrics.ISI{mu} = isi_sec;
        metrics.mean_fr(mu) = mean(1 ./ isi_sec);
        metrics.CoV(mu) = std(isi_sec) / mean(isi_sec);
        
        % 2. Spike Triggered Averaging (MUAPs)
        % Using logic similar to your 'batchprocessfilters_1win' loop
        waveform = zeros(num_channels, 2*win_samples+1);
        
        % Iterate channels to cut MUAPs
        for ch = 1:num_channels
            % Use your existing library function 'cutMUAP'
            cuts = cutMUAP(spikes, win_samples, emg_sig(ch, :));
            if ~isempty(cuts)
                waveform(ch, :) = mean(cuts, 1);
            end
        end
        
        % Handle bad channels
        if ~isempty(bad_channels)
            waveform(bad_channels, :) = NaN;
        end
        
        metrics.MUAPs{mu} = waveform;
        
        % 3. Peak-to-Peak and Location
        % Calculate p2p for every channel
        % peak2peak is a standard Matlab function (max - min)
        mu_p2ps = peak2peak(waveform, 2); 
        metrics.p2ps(:, mu) = mu_p2ps;
        
        % Find channel with max amplitude (ignoring NaNs)
        [~, max_idx] = max(mu_p2ps, [], 'omitnan');
        if ~isempty(max_idx)
            metrics.MU_locs(mu) = max_idx;
        else
            metrics.MU_locs(mu) = NaN;
        end
    end
end