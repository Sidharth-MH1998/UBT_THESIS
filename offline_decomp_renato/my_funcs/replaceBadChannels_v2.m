function fixedSignal = replaceBadChannels_v2(gridSignal, ElChannelMap, badchan)
    % Function to replace bad channels using bicubic interpolation with extended neighbor search
    %
    % Inputs:
    % gridSignal - 2D matrix of the signal in spatial map format
    % ElChannelMap - 2D map of channel indices
    % badchan - vector of bad channel indices
    %
    % Output:
    % fixedSignal - 2D matrix with bad channels replaced by interpolated values

    % Get the size of the map
    [rows, cols] = size(ElChannelMap);

    % Initialize the output signal
    fixedSignal = gridSignal;

    % Create masks for bad and valid channels
    badMask = false(size(ElChannelMap));
    for i = 1:length(badchan)
        [row, col] = find(ElChannelMap == badchan(i));
        if ~isempty(row) && ~isempty(col)
            badMask(row, col) = true;
        end
    end
    validMask = ~badMask;

    % Get coordinates of valid and bad channels
    [validRows, validCols] = find(validMask);
    [badRows, badCols] = find(badMask);

    % Extract values of valid channels
    validValues = gridSignal(validMask);

    if isempty(validValues)
        warning('No valid channels found.');
        return;
    end

    % Bicubic interpolation
    try
        % Create interpolation function using valid points only
        F = scatteredInterpolant(validCols, validRows, validValues, 'cubic', 'nearest');

        % Interpolate values for bad channels
        interpolatedValues = F(badCols, badRows);

        % Assign interpolated values to bad channels
        fixedSignal(badMask) = interpolatedValues;

    catch ME
        warning('Bicubic interpolation failed: %s\nFalling back to neighbor-based interpolation.', ME.message);
    end

    % Handle any remaining bad channels (e.g., at edges or corners)
    remainingBadMask = isnan(fixedSignal) | badMask;
    [remainingRows, remainingCols] = find(remainingBadMask);

    for i = 1:length(remainingRows)
        row = remainingRows(i);
        col = remainingCols(i);

        % Extended neighborhood search (up to 2 spaces away)
        neighbors = [];
        for r = max(1, row-2):min(rows, row+2)
            for c = max(1, col-2):min(cols, col+2)
                if validMask(r, c)
                    neighbors = [neighbors, gridSignal(r, c)];
                end
            end
        end

        % Replace bad channel value
        if ~isempty(neighbors)
            fixedSignal(row, col) = mean(neighbors, 'omitnan'); % Use mean of neighbors
        else
            % Fallback: Use global mean of valid values
            fixedSignal(row, col) = mean(validValues, 'omitnan');
        end
    end

    % OPTIONAL: Apply smoothing filter to mitigate residual artifacts
    smoothingKernel = fspecial('gaussian', [5, 5], 1); % Larger kernel to ensure smoother transitions
    fixedSignal = imfilter(fixedSignal, smoothingKernel, 'replicate');
end
