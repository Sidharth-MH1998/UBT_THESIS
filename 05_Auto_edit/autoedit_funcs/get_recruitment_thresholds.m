function recruitThresh = get_recruitment_thresholds(recruitTimes, force, fs, fs_force)
%GET_RECRUITMENT_THRESHOLDS Takes motor unit spike trains sampled at 'fs'
% and a force time series sampled at 'fs_force', and computes the 
% recruitment thresholds of each MU

    % Resample force from fs_force to fs if needed
    if fs ~= fs_force
        trial_duration = length(force) / fs_force;
        t_force = (0:length(force)-1) / fs_force;
        % match trial duration length exactly
        n_target = trial_duration*fs;
        t_target = (0:n_target-1) / fs;
        force_resampled = interp1(t_force, force, t_target, 'linear');
    else
        force_resampled = force;
    end

    % Get recruitment thresholds from resampled force
    recruitSamples = max(1, min(round(recruitTimes * fs), length(force_resampled)));
    recruitThresh = force_resampled(recruitSamples);

end

