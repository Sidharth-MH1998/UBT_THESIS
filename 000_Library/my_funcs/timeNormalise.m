function timeNorm_var = timeNormalise(var_in, t_in,t_out,fs)
    % Perform a time normalisation of each column in the variable 'var'
    % INPUTS:
    % var_in: Input time series data (each row is a separate time series)
    % t_in: Vector of start and end time of segments in the input signal (in seconds)
    % t_out: Vector of start and end time of segments to resample to for the output
    % OUTPUT:
    % timeNorm_var: time-normalised version of the variable
    
    % Get starting and ending indexes
    numSegments = length(t_in)-1;
    idx_in = round(t_in * fs);
    idx_out = round(t_out * fs);
    
    timeNorm_var = zeros(size(var_in));

    for seg = 1:numSegments
        len_in = idx_in(seg+1)-(idx_in(seg));
        len_out = idx_out(seg+1)-(idx_out(seg));
        resampSegment = resample( var_in((idx_in(seg)+1):idx_in(seg+1),:) , len_out, len_in );
        timeNorm_var(idx_out(seg)+1:idx_out(seg+1),:) = resampSegment;
    end

end