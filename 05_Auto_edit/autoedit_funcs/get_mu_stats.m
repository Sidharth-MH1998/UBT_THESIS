function stats = get_mu_stats(mu_pulses, fs)
% GET_POPULATION_STATS Computes FR and CoV statistics across the MU population.
% Adapted from logic in 'minimizeCOVISI.m' and 'remoutliers.m'.
%
% Input:
%   mu_pulses: Cell array of spike indices {1 x N_MUs}
%   fs: Sampling rate (Hz)
%
% Output:
%   stats: Struct containing population metrics (Mean/Std of FR and CoV)

    % Initialize storage
    all_mean_fr = [];
    all_cov_isi = [];
    
    for i = 1:length(mu_pulses)
        spikes = double(mu_pulses{i});
        
        % Need at least 2 spikes to calculate ISI
        if length(spikes) < 2
            continue;
        end
        
        % 1. Calculate Inter-Spike Intervals (in seconds)
        % Adapted from minimizeCOVISI.m
        isi = diff(spikes) / fs;
        
        % 2. Calculate Instantaneous Firing Rates (Hz)
        inst_fr = 1 ./ isi;
        
        % 3. Calculate Metrics for this MU
        mean_fr = mean(inst_fr);
        
        % CoV of ISI: std(ISI) / mean(ISI)
        % Adapted from minimizeCOVISI.m
        cov_isi = std(isi) / mean(isi);
        
        % Store
        all_mean_fr = [all_mean_fr, mean_fr];
        all_cov_isi = [all_cov_isi, cov_isi];
    end
    
    % 4. Compute Population Statistics (Mean +- Std across MUs)
    stats.fr_pop_mean = mean(all_mean_fr);
    stats.fr_pop_std  = std(all_mean_fr);
    
    stats.cov_pop_mean = mean(all_cov_isi);
    stats.cov_pop_std  = std(all_cov_isi);
    
    stats.num_mus = length(all_mean_fr);
end