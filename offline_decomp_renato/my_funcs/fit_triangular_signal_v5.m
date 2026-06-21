function [t1, t2, t3, t4, t5, t6, t7, rmse, pos_amp1, pos_amp2, neg_amp, c1, c_end] = fit_triangular_signal_v5(force_data, step, num_starts)
    % Fits a noisy time series data to the ideal triangular signal with specified amplitudes and constants for the first and last segments, and calculates RMSE.
    %
    % Parameters:
    %    data: Real time series data (must be 2500 samples).
    %    step: Time step for sampling (default is 0.01 seconds).
    %    num_starts: Number of multi-start runs (default is 10).
    %
    % Returns:
    %    t1, t2, t3, t4, t5, t6, t7: Fitted durations for each segment.
    %    rmse: Root mean square error of the fit.
    %    pos_amp1: Estimated positive amplitude for the first peak.
    %    pos_amp2: Estimated positive amplitude for the second peak.
    %    neg_amp: Estimated negative amplitude.

    if nargin < 2
        step = 0.01; % Default step size if not provided
    end
    if nargin < 3
        num_starts = 10; % Default number of multi-start runs if not provided
    end

    % Number of samples
    num_samples = length(force_data);
    time = (0:num_samples-1) * step;

    % Estimate constants for the first and last segments
    first_10_percent = force_data(1:round(0.1 * num_samples));
    last_10_percent = force_data(end-round(0.1 * num_samples)+1:end);
    
    c1 = mean(first_10_percent);
    c_end = mean(last_10_percent);

    % Identify peaks in the real signal
    [pks, locs] = findpeaks(force_data);
    [neg_pks, neg_locs] = findpeaks(-force_data);
    neg_pks = -neg_pks; % Convert back to positive values

    % Find the two largest positive peaks at least 5 seconds apart
    min_separation = 5 / step; % Convert seconds to samples
    [sorted_pks, sorted_idx] = sort(pks, 'descend');
    largest_peak_loc = locs(sorted_idx(1));
    second_peak_idx = find(abs(locs(sorted_idx(2:end)) - largest_peak_loc) >= min_separation, 1, 'first');
    second_largest_peak_loc = locs(sorted_idx(second_peak_idx + 1));

    % Find the lowest negative peak
    [min_neg_peak, min_neg_idx] = min(neg_pks);
    lowest_neg_peak_loc = neg_locs(min_neg_idx);

    % Use the identified peaks to refine the initial guesses
    pos_amp1 = force_data(largest_peak_loc);
    pos_amp2 = force_data(second_largest_peak_loc);
    neg_amp = min_neg_peak;

    % Initial guesses for durations based on peak locations
    t1_guess = largest_peak_loc * step;
    t2_guess = abs(second_largest_peak_loc - largest_peak_loc) * step / 2;
    t3_guess = abs(lowest_neg_peak_loc - second_largest_peak_loc) * step / 2;
    t4_guess = abs(lowest_neg_peak_loc - second_largest_peak_loc) * step / 2;
    t5_guess = abs(lowest_neg_peak_loc - second_largest_peak_loc) * step / 2;
    t6_guess = abs(second_largest_peak_loc - lowest_neg_peak_loc) * step / 2;
    t7_guess = abs(num_samples - second_largest_peak_loc) * step - t1_guess - t2_guess - t3_guess - t4_guess - t5_guess - t6_guess;

    % Lower bounds for the time durations to ensure they are positive.
    lb = [2.5, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0, 0, -1];
    % Upper bounds for the time durations and amplitudes to prevent excessive values
    ub = [7, 5, 5, 5, 5, 5, 5, 1, 1, 0];

    % Objective function to minimize
    function error = objective_function(params)
        [t, ideal_signal] = generate_triangular_signal_v5(params(1), params(2), params(3), params(4), params(5), params(6), params(7), params(8), params(9), params(10), c1, c_end, step);
        % Interpolate the ideal signal to the same length as the data
        ideal_signal_interp = interp1(t, ideal_signal, time, 'linear', 'extrap');
        
        % Calculate the RMSE
        rmse_error = sum((force_data - ideal_signal_interp).^2);
        
        % Identify peaks in the real and fitted signals
        [~, real_locs] = findpeaks(force_data);
        [~, fitted_locs] = findpeaks(ideal_signal_interp);
        
        % Match the number of peaks by truncating the longer array
        num_peaks = min(length(real_locs), length(fitted_locs));
        real_peaks = force_data(real_locs(1:num_peaks));
        fitted_peaks = ideal_signal_interp(fitted_locs(1:num_peaks));
        
        % Penalize the differences between real and fitted peaks
        peak_penalty = sum((real_peaks - fitted_peaks).^2);
 
        % Combine the errors with a weight for the peak penalty
        error = rmse_error + 0 * peak_penalty; % Adjust the weight as necessary
    end
    
    % Constraints: sum of durations must be 25 seconds
    Aeq = [1, 1, 1, 1, 1, 1, 1, 0, 0, 0];
    beq = 25;
    
    % Perform the optimization with constraints and multi-start
    options = optimoptions('fmincon', 'Display', 'off', 'Algorithm', 'sqp', 'MaxIterations', 2000, 'StepTolerance', 1e-12);

    best_params = [];
    best_error = inf;

    for i = 1:num_starts
        % Randomize initial guesses within reasonable bounds
        initial_guess = [t1_guess, t2_guess, t3_guess, t4_guess, t5_guess, t6_guess, t7_guess] + randn(1, 7) * 0.5;
        initial_guess = max(min(initial_guess, ub(1:7)), lb(1:7)); % Ensure initial guess is within bounds
        initial_guess = [initial_guess, pos_amp1, pos_amp2, neg_amp];

        % Run optimization
        [params, error] = fmincon(@objective_function, initial_guess, [], [], Aeq, beq, lb, ub, [], options);
        
        % Update best parameters if current error is lower
        if error < best_error
            best_error = error;
            best_params = params;
        end
    end
    
    % Extract the best fitted durations and amplitudes
    t1 = best_params(1);
    t2 = best_params(2);
    t3 = best_params(3);
    t4 = best_params(4);
    t5 = best_params(5);
    t6 = best_params(6);
    t7 = best_params(7);
    pos_amp1 = best_params(8);
    pos_amp2 = best_params(9);
    neg_amp = best_params(10);

    % Generate the fitted signal for RMSE calculation
    [t_fit, fitted_signal] = generate_triangular_signal_v5(t1, t2, t3, t4, t5, t6, t7, pos_amp1, pos_amp2, neg_amp, c1, c_end, step);
    ideal_signal_interp = interp1(t_fit, fitted_signal, time, 'linear', 'extrap');
    
    % Calculate RMSE
    rmse = sqrt(mean((force_data - ideal_signal_interp).^2));
end
