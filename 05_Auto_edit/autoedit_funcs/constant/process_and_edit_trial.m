function process_and_edit_trial(subject, digit, force_lvl, trial, paths)
% PROCESS_AND_EDIT_TRIAL Automated cleaning pipeline for a single trial.
%
% Inputs:
%   subject, digit, force_lvl, trial: Identifiers
%   paths: Struct with fields .root (input) and .save (output)
%
% Author: Renato Mio (02.12.2025)

    % 1. Construct File Path
    sub_folder = sprintf("S%s_100", num2str(subject));
    filename = sprintf("S%s_ss1_dig%d_f%s_t%d.mat", num2str(subject), digit, num2str(force_lvl), trial);
    full_path = fullfile(paths.root, "decomposed_sil_07_cov_on", sub_folder, filename);
    
    if ~isfile(full_path)
        warning('File not found: %s', filename);
        return;
    end
    
    fprintf('Processing: %s ...\n', filename);
    data = load(full_path);
    
    % Initialize Output Structure
    processed_data = struct();
    processed_data.info = struct('subject', subject, 'digit', digit, 'force', force_lvl, 'trial', trial);
    processed_data.fs = data.fs;
    processed_data.force = data.force; % Keep force for later regression
    
    % --- PROCESS GRID 1 (Channels 1-64) ---
    fprintf('  > Grid 1: ');
    bad_g1 = data.badchan(data.badchan <= 64);
    good_g1_local = setdiff(1:64, bad_g1);
    
    % Prepare Data
    emg_g1 = data.emg(1:64, :); 
    emg_g1_clean = emg_g1(good_g1_local, :); % For auto-editor whitening
    spikes_g1 = data.decomp_results_g1.MUPulses;
    sil_g1 = data.decomp_results_g1.sil_all; % also extract SIL
    
    % 1. Run Auto-Editor
    [edited_spikes_g1, stats_g1] = auto_edit_spikes(emg_g1_clean, spikes_g1, data.fs, false, "Grid 1");
    
    % 2. Recalculate Metrics (pass FULL emg_g1 to preserve channel indices, with bad_g1 mask)
    metrics_g1 = recalc_mu_metrics(edited_spikes_g1, emg_g1, data.fs, bad_g1);
    
    % Store
    processed_data.grid1.original_spikes = spikes_g1;
    processed_data.grid1.original_sil = sil_g1;
    processed_data.grid1.results_edited = metrics_g1;
    processed_data.grid1.edit_stats = stats_g1;
    processed_data.grid1.bad_channels = bad_g1;
    
    
    % --- PROCESS GRID 2 (Channels 65-128) ---
    fprintf('  > Grid 2: ');
    bad_g2 = data.badchan(data.badchan > 64); % Indices are 65-128
    bad_g2_local = bad_g2 - 64; % Convert to 1-64 local frame
    good_g2_global = setdiff(65:128, bad_g2);
    
    % Prepare Data
    emg_g2 = data.emg(65:128, :);
    emg_g2_clean = data.emg(good_g2_global, :); % For auto-editor whitening
    spikes_g2 = data.decomp_results_g2.MUPulses;
    sil_g2 = data.decomp_results_g2.sil_all;
    
    % 1. Run Auto-Editor
    [edited_spikes_g2, stats_g2] = auto_edit_spikes(emg_g2_clean, spikes_g2, data.fs, false, "Grid 2");
    
    % 2. Recalculate Metrics (pass FULL emg_g2 with local bad mask)
    metrics_g2 = recalc_mu_metrics(edited_spikes_g2, emg_g2, data.fs, bad_g2_local);
    
    % Store
    processed_data.grid2.original_spikes = spikes_g2;
    processed_data.grid2.original_sil = sil_g2;
    processed_data.grid2.results_edited = metrics_g2;
    processed_data.grid2.edit_stats = stats_g2;
    processed_data.grid2.bad_channels = bad_g2;
    
    % --- SAVE ---
    out_name = strrep(filename, '.mat', '_edited.mat');
    save_full_path = fullfile(paths.save, out_name);
    
    % Using -struct to save fields as individual variables if preferred, 
    % or save the whole struct. Saving struct is cleaner for loading later.
    save(save_full_path, 'processed_data');
    fprintf('  > Saved to: %s\n', out_name);
end