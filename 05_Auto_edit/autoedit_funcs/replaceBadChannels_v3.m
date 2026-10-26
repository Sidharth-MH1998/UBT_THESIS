function fixedSignal = replaceBadChannels_v3(gridSignal, ElChannelMap, badchan)
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

    % Get initial MU loc (used in final filtering)
    [~,I] = max(gridSignal,[],"all");
    [centroidRow, centroidCol] = ind2sub(size(gridSignal),I);

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

    % Apply smoothing filter to mitigate residual artifacts
    smoothingKernel = fspecial('gaussian', [3, 3], 1); % Larger kernel to ensure smoother transitions
    smoothedSignal = imfilter(fixedSignal, smoothingKernel, 'replicate');

    % Cross-correlation re-alignment after smoothing (the Gaussian might cause a lateral shift in the overall map distribution)
    % Compute normalised cross-correlation between smoothed and original signal
    xcorrMap = normxcorr2(smoothedSignal, fixedSignal);
    
    % Find the peak in cross-correlation map
    [~, maxIdx] = max(xcorrMap(:));
    [peakRow, peakCol] = ind2sub(size(xcorrMap), maxIdx);
    
    % Compute the required shift
    [origRows, origCols] = size(fixedSignal);
    rowShift = peakRow - origRows;
    colShift = peakCol - origCols;
    
    % Apply circular shift only if needed
    if rowShift ~= 0 || colShift ~= 0
        shiftedSignal = circshift(smoothedSignal, [rowShift, colShift]);
        
        % After shift, edges may wrap incorrectly — set them to NaN
        [rows, cols] = size(shiftedSignal);
        edgeMask = false(rows, cols);
        
        if rowShift > 0
            edgeMask(1:rowShift, :) = true;
        elseif rowShift < 0
            edgeMask((rows + rowShift + 1):rows, :) = true;
        end
        
        if colShift > 0
            edgeMask(:, 1:colShift) = true;
        elseif colShift < 0
            edgeMask(:, (cols + colShift + 1):cols) = true;
        end
        
        shiftedSignal(edgeMask) = NaN;
        
        % Interpolate missing (NaN) values using scattered interpolation
        [X, Y] = meshgrid(1:cols, 1:rows);
        nanMask = isnan(shiftedSignal);
        
        if any(nanMask(:))
            validX = X(~nanMask);
            validY = Y(~nanMask);
            validValues = shiftedSignal(~nanMask);
            
            F = scatteredInterpolant(validX(:), validY(:), validValues(:), 'linear', 'nearest');
            
            nanX = X(nanMask);
            nanY = Y(nanMask);
            
            interpolatedValues = F(nanX(:), nanY(:));
            shiftedSignal(nanMask) = interpolatedValues;
        end
        
        fixedSignal = shiftedSignal;
    else
        fixedSignal = smoothedSignal;
    end
end
