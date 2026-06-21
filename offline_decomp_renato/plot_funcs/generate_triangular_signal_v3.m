function [t, f_trace] = generate_triangular_signal_v3(t1, t2, t3, t4, t5, t6, t7, pos_amp, neg_amp, step)
% Generates a triangular shaped time series signal with specified amplitudes.
%
% Parameters:
%    t1, t2, t3, t4, t5, t6, t7: Duration of each segment in seconds.
%    pos_amp: Positive amplitude.
%    neg_amp: Negative amplitude.
%    step: Time step for sampling (default is 0.01 seconds).
%
% Returns:
%    t: Time array.
%    f_trace: Force values for the time series.

    if nargin < 10
        step = 0.01; % Default step size if not provided
    end
    
    % Generate time arrays for each segment
    t0 = 0:step:t1-step;
    t_up1 = t1:step:t1+t2-step;
    t_down1 = t1+t2:step:t1+t2+t3-step;
    t_down2 = t1+t2+t3:step:t1+t2+t3+t4-step;
    t_up2 = t1+t2+t3+t4:step:t1+t2+t3+t4+t5-step;
    t_up3 = t1+t2+t3+t4+t5:step:t1+t2+t3+t4+t5+t6-step;
    t_down3 = t1+t2+t3+t4+t5+t6:step:t1+t2+t3+t4+t5+t6+t7-step;
    t_end = t1+t2+t3+t4+t5+t6+t7:step:25;

    % Generate force values for each segment
    y0 = zeros(size(t0));
    y_up1 = linspace(0, pos_amp, numel(t_up1));
    y_down1 = linspace(pos_amp, 0, numel(t_down1));
    y_down2 = linspace(0, neg_amp, numel(t_down2));
    y_up2 = linspace(neg_amp, 0, numel(t_up2));
    y_up3 = linspace(0, pos_amp, numel(t_up3));
    y_down3 = linspace(pos_amp, 0, numel(t_down3));
    y_end = zeros(size(t_end));

    % Concatenate all time and force values
    t = [t0, t_up1, t_down1, t_down2, t_up2, t_up3, t_down3, t_end];
    f_trace = [y0, y_up1, y_down1, y_down2, y_up2, y_up3, y_down3, y_end];
end