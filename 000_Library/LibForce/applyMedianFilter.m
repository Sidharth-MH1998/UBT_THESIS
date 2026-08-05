function filteredForce = applyMedianFilter(forceData, currentIdx, medianFilterLength)
    % This function applies a real-time median filter with a specified window length
    % Inputs:
    %   - forceData: Force data buffer (2D array, [samples x channels])
    %   - currentIndex: Current index in the data stream
    %   - filterLength: Length of the median filter window (must be odd)
    %
    % Output:
    %   - filteredForce: Median-filtered force data for each channel
    
    % Step 1: Get the valid range of indices for the filter window
    windowStart = max(1, currentIdx - medianFilterLength + 1);  % Start of the window
    windowData = forceData(windowStart:currentIdx, :);  % Data window for all channels

    % Step 2: Handle cases where the current index is less than the filter length
    if currentIdx < medianFilterLength
        % Replicate the first available sample to pad the data
        padding = repmat(windowData(1, :), medianFilterLength - size(windowData, 1), 1);  % Replicate the first valid sample
        windowData = [padding; windowData];  % Append replicated padding at the start
    end

    % Step 3: Apply median filter across the first dimension (rows correspond to time samples)
    filteredForce = median(windowData, 1);  % Take median across the rows (time window) for each channel
end