function [t1, t2, t3, t4, t5, t6, t7, rmse, pos_amp1, pos_amp2, neg_amp, c1, c_end] = fit_triangular_signal_v6(force_data, step)
    % Fits a noisy time series data to the ideal triangular signal with specified amplitudes and constants for the first and last segments, and calculates RMSE.
    %
    % Parameters:
    %    data: Real time series data (must be 2500 samples).
    %    step: Time step for sampling (default is 0.01 seconds).
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

    % Apply noise filtering using a Savitzky-Golay filter
    window_length = 81;  % Must be odd
    polynomial_order = 3;
    force_data = sgolayfilt(force_data, polynomial_order, window_length);

    % Number of samples
    num_samples = length(force_data);
    time = (0:num_samples-1) * step;

    % Advanced peak detection
    [pks, locs] = findpeaks(force_data, 'MinPeakProminence', 0.1 * (max(force_data) - min(force_data)));
    
    if length(pks) >= 2
        pos_amp1 = pks(1);
        pos_amp2 = pks(2);
    else
        % Fallback to previous method if not enough peaks detected
        sorted_data = sort(force_data);
        top_10_percent = sorted_data(round(0.9 * num_samples):end);
        pos_amp1 = mean(top_10_percent);
        pos_amp2 = mean(top_10_percent);
    end

    % Estimate negative amplitude (vectorized)
    sorted_data = sort(force_data);
    bottom_10_percent = sorted_data(1:round(0.1 * num_samples));
    neg_amp = mean(bottom_10_percent);

    % Estimate constants for the first and last segments
    first_10_percent = force_data(1:round(0.1 * num_samples));
    last_10_percent = force_data(end-round(0.1 * num_samples)+1:end);
    
    c1 = mean(first_10_percent);
    c_end = mean(last_10_percent);
    
    % Initial guesses for durations (can be refined based on expected values)
    t1_guess = 5; t2_guess = 2.5; t3_guess = 2.5; t4_guess = 2.5;
    t5_guess = 2.5; t6_guess = 2.5; t7_guess = 2.5;
    
    % Lower bounds for the time durations to ensure they are positive.
    % Positive amplitudes from 0 to Inf and the negatives from -Inf to 0
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
        error = rmse_error + 5 * peak_penalty; % Adjust the weight as necessary
    end
    
    % Constraints: sum of durations must be 24 seconds
    Aeq = [1, 1, 1, 1, 1, 1, 1, 0, 0, 0];
    beq = 23;
    
    % Perform the optimization with constraints
    options = optimoptions('fmincon', 'Display', 'iter', 'Algorithm', 'sqp','MaxIterations',2000,'StepTolerance',1e-12,'MaxFunctionEvaluations',2e4);
    fitted_params = fmincon(@objective_function, [t1_guess, t2_guess, t3_guess, t4_guess, t5_guess, t6_guess, t7_guess, pos_amp1, pos_amp2, neg_amp], [], [], Aeq, beq, lb, ub, [], options);
    
    % Extract the fitted durations and amplitudes
    t1 = fitted_params(1);
    t2 = fitted_params(2);
    t3 = fitted_params(3);
    t4 = fitted_params(4);
    t5 = fitted_params(5);
    t6 = fitted_params(6);
    t7 = fitted_params(7);
    pos_amp1 = fitted_params(8);
    pos_amp2 = fitted_params(9);
    neg_amp = fitted_params(10);

    % Generate the fitted signal for RMSE calculation
    [t_fit, fitted_signal] = generate_triangular_signal_v5(t1, t2, t3, t4, t5, t6, t7, pos_amp1, pos_amp2, neg_amp, c1, c_end, step);
    ideal_signal_interp = interp1(t_fit, fitted_signal, time, 'linear', 'extrap');
    
    % Calculate RMSE
    rmse = sqrt(mean((force_data - ideal_signal_interp).^2));
end
