function [spiketrains_clean, survivor_indices] = remduplicateMUs(spiketrains, fs)
% REMOVEDUPLICATEMUS Adapted from original remduplicates for sparse matrices
% Inputs:
%   spiketrains: sparse matrix [samples x MUs]
%   fs: sampling rate
% Outputs:
%   spiketrains_clean: sparse matrix with duplicates removed
%   survivor_indices: indices of the MUs from the original matrix that were kept

    % Parameters from original function
    maxlag = round(fs/40); % approx 25ms
    tol = 0.3; % 30% overlap threshold
    
    nMUs = size(spiketrains, 2);
    if nMUs < 2
        spiketrains_clean = spiketrains;
        survivor_indices = 1:nMUs;
        return;
    end

    % Convert sparse to cell array of discharge times (needed for the logic)
    distime = cell(1, nMUs);
    for i = 1:nMUs
        distime{i} = find(spiketrains(:,i));
    end

    % Calculate CoV for all MUs upfront (used for survivor selection)
    CoV_list = zeros(1, nMUs);
    for i = 1:nMUs
        if length(distime{i}) > 1
            isi = diff(distime{i});
            CoV_list(i) = std(isi) / mean(isi);
        else
            CoV_list(i) = 100; % High penalty for empty/single-spike MUs
        end
    end

    % Initialize survivor list
    current_indices = 1:nMUs; % Tracks global index
    
    % Iterative removal (Logic adapted from your provided function)
    i = 1;
    while i <= length(distime)
        % Get reference MU
        ref_spikes = zeros(size(spiketrains,1), 1);
        ref_spikes(distime{i}) = 1;
        
        candidates_to_remove = [];
        
        % Compare against all subsequent MUs
        for j = (i+1):length(distime)
            comp_spikes = zeros(size(spiketrains,1), 1);
            comp_spikes(distime{j}) = 1;
            
            % Check Cross-Correlation for lag
            [c, lags] = xcorr(ref_spikes, comp_spikes, maxlag, 'normalized');
            [correl, idx] = max(c);
            lag_val = lags(idx);
            
            % Apply lag to comparison spikes for overlap check
            if correl > 0.1 % Optimisation: Only check intersection if xcorr shows some promise
                comp_times_shifted = distime{j} + lag_val;
                
                % Intersect
                common = intersect(distime{i}, comp_times_shifted);
                % Remove consecutive indices (burst artifacts in intersection)
                if ~isempty(common)
                    common([false; diff(common) == 1]) = [];
                end
                
                % Calculate overlap ratio
                denom = max([length(distime{i}), length(distime{j})]);
                overlap = length(common) / denom;
                
                if overlap >= tol
                    candidates_to_remove = [candidates_to_remove, j];
                end
            end
        end
        
        if ~isempty(candidates_to_remove)
            % We found duplicates. Include the current reference 'i' in the comparison group
            group_indices = [i, candidates_to_remove];
            
            % Find who has the lowest CoV
            group_covs = CoV_list(group_indices);
            [~, best_local_idx] = min(group_covs);
            best_idx_in_distime = group_indices(best_local_idx);
            
            % The logic here is tricky: we want to keep BEST, remove others.
            % But 'i' is the iterator. 
            
            % Simpler approach than original while-loop modification:
            % Mark losers for deletion in a tracking array
            % But to stick to your original logic of removing on the fly:
            
            if best_idx_in_distime == i
                % Reference is the best. Remove candidates.
                % Delete from end to start to maintain indices
                candidates_to_remove = sort(candidates_to_remove, 'descend');
                for k = candidates_to_remove
                    distime(k) = [];
                    CoV_list(k) = [];
                    current_indices(k) = [];
                end
                i = i + 1; % Move to next
            else
                % Reference 'i' is NOT the best. One of the candidates is better.
                % Actually, if 'i' is a duplicate of 'j', and 'j' is better, 
                % we should remove 'i'.
                % However, usually we iterate forward.
                
                % To keep it robust: If ANY duplicate exists, remove the one with higher CoV.
                % Let's delete the candidates, but if 'i' was worse than a candidate,
                % we should technically swap 'i' for the candidate, or just delete 'i' 
                % and stay at the same index.
                
                % Simplified greedy approach: 
                % If 'i' overlaps with 'j', remove the one with worse CoV.
                % If 'i' is removed, don't increment i.
                % If 'j' is removed, remove j and continue checking i.
                
                recheck_i = false;
                % Sort candidates descending to delete safely
                candidates_to_remove = sort(candidates_to_remove, 'descend');
                
                for k = candidates_to_remove
                    if CoV_list(i) > CoV_list(k)
                        % 'i' is worse than 'k'. Remove 'i'.
                        distime(i) = [];
                        CoV_list(i) = [];
                        current_indices(i) = [];
                        recheck_i = true;
                        break; % Stop checking candidates, 'i' is gone.
                    else
                        % 'k' is worse. Remove 'k'.
                        distime(k) = [];
                        CoV_list(k) = [];
                        current_indices(k) = [];
                    end
                end
                
                if ~recheck_i
                    i = i + 1;
                end
            end
        else
            i = i + 1;
        end
    end
    
    % Reconstruct sparse matrix from survivors
    spiketrains_clean = spiketrains(:, current_indices);
    survivor_indices = current_indices;
end