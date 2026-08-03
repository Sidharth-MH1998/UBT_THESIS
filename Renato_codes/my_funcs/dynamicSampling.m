function [data_sampled, force_sampled] = dynamicSampling(data, force, fs, fs_middle, focus_duration)
    % Calculate total duration and indices
    n_samples = size(data, 1);
    start_idx = round(focus_duration * fs);
    end_idx = round(n_samples - focus_duration * fs);
    
    % High resolution: Start and end indices (full sampling)
    high_res_start = 1:start_idx;
    high_res_end = (end_idx-1:n_samples);
    
    % Low resolution: Middle indices (reduced sampling)
    downsample_factor = round(fs / fs_middle);
    middle_indices = start_idx+downsample_factor : downsample_factor : end_idx-downsample_factor;
    
    % Combine indices
    dynamic_indices = unique([high_res_start, middle_indices, high_res_end]);
    
    % Apply sampling
    data_sampled = data(dynamic_indices, :);
    force_sampled = force(dynamic_indices);
end