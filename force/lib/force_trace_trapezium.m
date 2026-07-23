function [t, f_trace] = force_trace_trapezium(tPlateau, tSlope, tWait, forceTarget, fs_force)

    % Time step based on the sampling frequency
    step = 1/fs_force;
    
    % Time vectors for the different segments
    t0 = step:step:tSlope;                      % Time for the slope up
    t1 = tSlope+step:step:tSlope+tPlateau;      % Time for the plateau
    t2 = t1(end)+step:step:t1(end)+tSlope;      % Time for the slope down
    
    % Force values for the different segments
    y0 = forceTarget * t0 / tSlope;             % Rising slope
    y1 = forceTarget * ones(size(t1));          % Plateau
    y2 = forceTarget - forceTarget * t0 / tSlope; % Falling slope
    
    % Time for the initial and final wait (flat line at zero force)
    tWaitInitial = 0:step:tWait-step;           % Time for initial wait
    tWaitFinal = t2(end)+step:step:t2(end)+tWait; % Time for final wait
    
    % Force for initial and final wait (zero force)
    yWaitInitial = zeros(size(tWaitInitial));   % Zero force during initial wait
    yWaitFinal = zeros(size(tWaitFinal));       % Zero force during final wait
    
    % Concatenate time and force values
    t = [tWaitInitial, t0+tWait, t1+tWait, t2+tWait, tWaitFinal+tWait];  % Adjust time for the wait periods
    f_trace = [yWaitInitial, y0, y1, y2, yWaitFinal];              % Full force trace with waits
end
