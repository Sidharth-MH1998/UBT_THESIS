function [edited_spikes, stats, quality] = auto_edit_spikes(emg, spikes, fs, do_plot, label)
% AUTO_EDIT_GRID Process a single grid's worth of data.
%
% Inputs:
%   emg:        (Channels x Samples) matrix. MUST BE CLEAN (Bad channels removed).
%   spikes:     Cell array of spike indices {1 x N_MUs}
%   fs:         Sampling rate (Hz)
%   do_plot:    (Optional) Boolean. Default = false.
%   label:      (Optional) String for plot titles (e.g. "S1 Grid 1")
%
% Outputs:
%   edited_spikes: Cell array of processed spike indices
%   stats:         Struct with 'added', 'removed', 'cov_improvement', 'fr'
%
% Author: Renato Mio (02.12.2025)


    if nargin < 4, do_plot = false; end
    if nargin < 5, label = 'Grid'; end

    % 1. Pre-processing (Whitening)
    % Convert matrix to cell array of row vectors (Required by extend_and_whiten)
    [n_channels, n_samples] = size(emg);
    SIG_cell = mat2cell(emg, ones(n_channels, 1), n_samples);
    
    % Discard vector is 0 because we assume input EMG is already clean
    discard_vec = zeros(n_channels, 1); 
    
    % Run whitening (Suppress output if needed)
    [~, ~, wSIG_m, ~] = extend_and_whiten(SIG_cell, discard_vec, fs);

    % 2. Initialize Auto Editor
    autoEd = auto_editor();
    autoEd = autoEd.set_para(0.331, 0.339, 0.539, 0.508);
    autoEd = autoEd.set_fsamp(fs);
    autoEd.disp_flag = 0; % Keep console clean

    % 3. Editing Loop
    edited_spikes = spikes;
    num_mus = length(spikes);
    % Optional SIL diagnostics use the existing decomposition calcSIL method.
    % It reclusters peaks, so this evaluates the reconstructed MU filter,
    % rather than scoring every accepted/rejected edited event directly.
    quality.sil_pre = NaN(1, num_mus);
    quality.sil_post = NaN(1, num_mus);
    if nargout > 2
        quality.pulsetrain = NaN(num_mus, size(wSIG_m, 2));
    end
    count_added = zeros(1, num_mus);
    count_removed = zeros(1, num_mus);
    fprintf('Auto-editing %d Motor Units...\n', num_mus);
    
    % Parallel loop option (change to 'for' if parallel pool not available)
    for mu = 1:num_mus
        curr_spikes = edited_spikes{mu};
        orig_spikes = curr_spikes;
        if nargout > 2
            quality.sil_pre(mu) = filter_sil(curr_spikes, wSIG_m, fs);
        end
        
        if length(curr_spikes) < 10
            quality.sil_post(mu) = quality.sil_pre(mu);
            if nargout > 2
                [~, quality.pulsetrain(mu,:)] = filter_sil(curr_spikes, wSIG_m, fs);
            end
            continue; 
        end
        
        % A. Update IPT
        [autoEd, ipt, ~] = autoEd.update_ipts(curr_spikes, wSIG_m);
        autoEd = autoEd.reset();
        
        % B. Iterative Rules
        max_cycles = 5;
        iter = 0;
        changed = true;
        
        while changed && iter < max_cycles
            iter = iter + 1;
            spikes_pre = curr_spikes;
            
            % Apply Rules (High FR -> Low IPT -> High IPT -> Low FR)
            % 1. Remove High FR (Noise/Artifacts)
            [autoEd, curr_spikes, ~] = autoEd.remove_high_fr_pre(ipt, curr_spikes, 50);
            [autoEd, ipt, ~] = autoEd.update_ipts(curr_spikes, wSIG_m);
            % 2. Remove Low IPT (False Positives)
            [autoEd, curr_spikes, ~] = autoEd.remove_low_ipt(ipt, curr_spikes, 50);
            [autoEd, ipt, ~] = autoEd.update_ipts(curr_spikes, wSIG_m);
            % 3. Add High IPT (False Negatives)
            [autoEd, curr_spikes, ~] = autoEd.add_high_ipt(ipt, curr_spikes, 50);
            % 4. Add Low FR (Fill Gaps)
            [autoEd, curr_spikes, ~] = autoEd.add_low_fr(ipt, curr_spikes, 50);
            [autoEd, ipt, ~] = autoEd.update_ipts(curr_spikes, wSIG_m);
            
            % Check Convergence
            [added, removed, ~] = compare_mupulses(spikes_pre, curr_spikes);
            if isempty(added) && isempty(removed)
                changed = false;
            end
        end
        
        % Store
        edited_spikes{mu} = curr_spikes;
        if nargout > 2
            [quality.sil_post(mu), quality.pulsetrain(mu,:)] = ...
                filter_sil(curr_spikes, wSIG_m, fs);
        end
        
        % Stats
        [added_final, removed_final, ~] = compare_mupulses(orig_spikes, curr_spikes);
        count_added(mu) = length(added_final);
        count_removed(mu) = length(removed_final);

    end

    % 4. Statistics & Visualization
    stats_pre = get_mu_stats(spikes, fs);
    stats_post = get_mu_stats(edited_spikes, fs);
    
    % Store detailed stats
    stats.added_per_mu = count_added;
    stats.removed_per_mu = count_removed;
    stats.total_added = sum(count_added);
    stats.total_removed = sum(count_removed);
    stats.cov_pre = stats_pre.cov_pop_mean;
    stats.cov_post = stats_post.cov_pop_mean;
    stats.fr_pre = stats_pre.fr_pop_mean;
    stats.fr_post = stats_post.fr_pop_mean;
    
    % Print Summary
    fprintf('[%s] MUs: %d | Added: %d | Removed: %d | CoV: %.2f%% -> %.2f%%\n', ...
        label, num_mus, stats.total_added, stats.total_removed, ...
        stats.cov_pre*100, stats.cov_post*100);
    
    % Print Table
    fprintf('%-20s | %-25s | %-25s\n', 'Metric', 'Original', 'Auto-Edited');
    fprintf('---------------------|---------------------------|---------------------------\n');
    fprintf('%-20s | %.2f +/- %.2f pps        | %.2f +/- %.2f pps\n', ...
        'Mean Firing Rate', ...
        stats_pre.fr_pop_mean, stats_pre.fr_pop_std, ...
        stats_post.fr_pop_mean, stats_post.fr_pop_std);
        
    fprintf('%-20s | %.2f +/- %.2f (%%%.1f)    | %.2f +/- %.2f (%%%.1f)\n', ...
        'CoV of ISI', ...
        stats_pre.cov_pop_mean, stats_pre.cov_pop_std, stats_pre.cov_pop_mean*100, ...
        stats_post.cov_pop_mean, stats_post.cov_pop_std, stats_post.cov_pop_mean*100);
    fprintf('------------------------------------------------\n');


    if do_plot
        plot_comparison(spikes, edited_spikes, fs, label, stats.cov_pre, stats.cov_post);
    end
end

function [sil, pulse] = filter_sil(spikes, whitened, fs)
    sil = NaN;
    pulse = NaN(1, size(whitened, 2));
    if numel(spikes) <= 5, return; end
    weights = sum(whitened(:,spikes), 2);
    projection = weights' * whitened;
    pulse = projection .* abs(projection);
    [peaks, ~] = findpeaks(pulse, 'MinPeakDistance', round(fs*0.02));
    if numel(peaks) < 2 || numel(unique(peaks)) < 2, return; end
    % calcSIL uses random kmeans initialization; seed locally for repeatability
    % and restore the caller's RNG so optional diagnostics do not alter edits.
    previous_rng = rng;
    restore_rng = onCleanup(@() rng(previous_rng)); %#ok<NASGU>
    rng(0, 'twister');
    [pulse, ~, sil] = calcSIL(whitened, weights, fs);
    if ~isfinite(sil), sil = NaN; end
end
