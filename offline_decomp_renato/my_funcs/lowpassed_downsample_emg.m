function [downsampled_power, downsampled_time] = lowpassed_downsample_emg(signal, fs, downsample_factor, cutoff_freq)
    % Function to compute the low-passed power of a time series signal and downsample it.
    % signal: Input time series row-wise signal (channels x signal)
    % fs: Original sampling frequency of the signal 
    % downsample_factor: Factor by which to downsample the power signal
    % cutoff_freq: Cutoff frequency of the low-pass filter in Hz
    
    % Convert to column-wise for computations
    signal = signal';

    % Compute the instantaneous power of the signal
    power_signal = signal.^2;
    
    % Design a low-pass filter
    [b, a] = butter(4, cutoff_freq/(fs/2));  % 4th order Butterworth filter
    
    % Apply the low-pass filter to the power signal
    lowpassed_power = filtfilt(b, a, power_signal);
    
    % Downsample the low-passed power signal and convert to row-wise again
    downsampled_power = lowpassed_power(1:downsample_factor:end,:)';
    
    % Generate the corresponding downsampled time vector
    time = (0:length(signal)-1) / fs;
    downsampled_time = time(1:downsample_factor:end);
        
end
