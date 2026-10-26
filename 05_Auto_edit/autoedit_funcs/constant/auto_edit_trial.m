function [edited_MUPulses, original_MUPulses, stats] = auto_edit_trial_v0(subject_id, digit, force_level, trial, root_path, do_plot)
% AUTO_EDIT_TRIAL Loads a trial, runs auto-editor, and plots comparison.
%
% Inputs:
%   subject: string or int (e.g., "24" or 24)
%   digit: int (1, 2, or 3)
%   force_level: string or int ("10" or 10)
%   trial: int (1-5)
%   root_data_path: string, path to 'proc' folder (e.g. 'D:\...\proc\')
%   do_plot: boolean, true to generate comparison figures
%
% Outputs:
%   edited_MUPulses: Cell array of edited spike trains (sample indices)
%   original_MUPulses: Cell array of original spike trains
%   stats: Struct containing add/remove counts per MU

    % 1. Handle Input Formats
    if isnumeric(subject_id), subject_id = num2str(subject_id); end
    if isnumeric(force_level), force_level = num2str(force_level); end
    
    % 2. Construct File Path (matching analyseSingleSubject.m structure)
    % Path format: proc/decomposed_sil_07_cov_on/S{Subj}_100/S{Subj}_ss1_dig{d}_f{f}_t{t}.mat
    decomp_folder = fullfile(root_path, "decomposed_sil_07_cov_on", strcat('S', subject_id, '_100'));
    file_name = sprintf('S%s_ss1_dig%d_f%s_t%d.mat', subject_id, digit, force_level, trial);
    full_path = fullfile(decomp_folder, file_name);
    
    if ~isfile(full_path)
        error('File not found: %s', full_path);
    end
    
    fprintf('Loading: %s\n', file_name);
    data = load(full_path);
    
    % 3. Extract and Merge Data from Grids
    % Concatenate MUPulses from Grid 1 and Grid 2
    if isfield(data, 'decomp_results_g1') && isfield(data, 'decomp_results_g2')
        original_MUPulses = [data.decomp_results_g1.MUPulses, ...
                             data.decomp_results_g2.MUPulses];
    else
        error('Decomposition results (g1/g2) not found in file.');
    end
    
    % Extract Raw EMG, valid (good) channels and sampling rate
    % Data has 'emg' (128 x samples) and 'goodchan' / 'badchan'
    raw_emg = data.emg; 
    fs = data.fs; % EMG/spikes sampling rate
    % The auto-editor needs "clean" signals for whitening. 
    % We will remove bad channels row-wise before passing to extension/whitening.
    % Note: extend_and_whiten expects a cell array for grid signals.
    valid_emg = raw_emg(data.goodchan, :); 
    
    % 4. Pre-processing for Auto-Editor (Whiten Signal)
    % Create a cell array of row vectors
    [n_channels, n_samples] = size(valid_emg);
    SIG_cell = mat2cell(valid_emg, ones(n_channels, 1), n_samples);
    % Create a matching discard vector (all zeros since we already removed bad channels)
    % It must match the dimensions of SIG_cell (chans x 1)
    discard_vec = zeros(n_channels, 1);

    fprintf('Whitening signal (Channels: %d)...\n', size(valid_emg,1));
    % Ensure mu_auto_editor-main is in path
    [~, ~, wSIG_m, ~] = extend_and_whiten(SIG_cell, discard_vec);
    
    % 5. Initialize Auto Editor
    autoEd = auto_editor();
    % Standard parameters from the paper/codebase
    autoEd = autoEd.set_para(0.331, 0.339, 0.539, 0.508); 
    autoEd = autoEd.set_fsamp(fs); % set sampling rate
    autoEd.disp_flag = 0; % Suppress verbose individual spike logging
    
    % 6. Iterative Editing Loop
    edited_MUPulses = original_MUPulses;
    num_mus = length(edited_MUPulses);
    stats = struct('added', zeros(1,num_mus), 'removed', zeros(1,num_mus));
    
    fprintf('Processing %d Motor Units...\n', num_mus);
    
    % Use a parallel pool if available for speed, otherwise change to 'for'
    for mu = 1:num_mus
        spikes = edited_MUPulses{mu};
        spikes_orig = spikes;
        
        if length(spikes) < 10
            continue; 
        end
        
        % A. Update IPT (Innervation Pulse Train)
        [autoEd, ipt, ~] = autoEd.update_ipts(spikes, wSIG_m);
        autoEd = autoEd.reset();
        
        % B. Editing Cycles
        max_cycles = 5;
        changed = true;
        iter = 0;
        
        while changed && iter < max_cycles
            iter = iter + 1;
            spikes_pre = spikes;
            
            % 1. Remove High FR (Noise/Artifacts)
            [autoEd, spikes, ~] = autoEd.remove_high_fr_pre(ipt, spikes, 50);
            [autoEd, ipt, ~] = autoEd.update_ipts(spikes, wSIG_m);
            
            % 2. Remove Low IPT (False Positives)
            [autoEd, spikes, ~] = autoEd.remove_low_ipt(ipt, spikes, 50);
            [autoEd, ipt, ~] = autoEd.update_ipts(spikes, wSIG_m);
            
            % 3. Add High IPT (False Negatives)
            [autoEd, spikes, ~] = autoEd.add_high_ipt(ipt, spikes, 50);
            
            % 4. Add Low FR (Fill Gaps)
            [autoEd, spikes, ~] = autoEd.add_low_fr(ipt, spikes, 50);
            
            % Update IPT for convergence check
            [autoEd, ipt, ~] = autoEd.update_ipts(spikes, wSIG_m);
            
            % Check convergence
            [added, removed, ~] = compare_mupulses(spikes_pre, spikes);
            if isempty(added) && isempty(removed)
                changed = false;
            end
        end
        
        % Save Results
        edited_MUPulses{mu} = spikes;
        
        % Calculate Stats
        [added, removed, ~] = compare_mupulses(spikes_orig, spikes);
        stats.added(mu) = length(added);
        stats.removed(mu) = length(removed);
        
        if mod(mu, 5) == 0
            fprintf('MU %d/%d processed.\n', mu, num_mus);
        end
    end
    
    % 7. Plotting
    if do_plot
        plot_comparison(original_MUPulses, edited_MUPulses, data.fs);
        sgtitle(sprintf('Auto-Edit Results: S%s D%d F%s T%d', subject_id, digit, force_level, trial));
    end
end