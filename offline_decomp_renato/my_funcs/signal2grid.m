function gridSignal = signal2grid(signal, ElChannelMap)
    % Function to transform a vector or matrix signal to a 2D/3D channel map
    %
    % signal - a column vector or a matrix (channels x time series)
    % ElChannelMap - 2D map of channel indices
    %
    % Output:
    % mappedSignal - A 2D map if signal is a vector, or a 3D map if signal is a matrix
    
    % Get dimensions of the channel map
    [rows, cols] = size(ElChannelMap);
    
    % Initialize mapped signal
    if isvector(signal)
        % If the input is a vector, create a 2D matrix to hold the values
        gridSignal = zeros(rows, cols);
    else
        % If the input is a matrix, create a 3D matrix (rows x cols x time points)
        timePoints = size(signal, 2);
        gridSignal = zeros(rows, cols, timePoints);
    end
    
    % Iterate through each element of ElChannelMap
    for r = 1:rows
        for c = 1:cols
            channelIndex = ElChannelMap(r, c); % Get the channel index from the map
            
            % Check if the signal is a vector or matrix and assign values
            if isvector(signal)
                gridSignal(r, c) = signal(channelIndex);
            else
                gridSignal(r, c, :) = signal(channelIndex, :);
            end
        end
    end
end