function fixedSignal = replaceBadChannels(gridSignal, ElChannelMap, badchan)
    % Function to replace bad channels in the mapped signal using bicubic interpolation
    % with proper handling of edge and corner cases
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
    
    % Get coordinates of valid channels
    [validRows, validCols] = find(validMask);
    [badRows, badCols] = find(badMask);
    
    % Extract values of valid channels
    validValues = gridSignal(validMask);
    
    if isempty(validValues)
        warning('No valid channels found.');
        return;
    end
    
    % Try bicubic interpolation first
    try
        % Create interpolation function using only valid points
        F = scatteredInterpolant(validCols, validRows, validValues, 'cubic', 'nearest');
        
        % Interpolate values for bad channels
        for i = 1:length(badRows)
            row = badRows(i);
            col = badCols(i);
            
            % Get interpolated value
            interpolatedValue = F(col, row);
            
            % Check if interpolation succeeded
            if ~isnan(interpolatedValue)
                fixedSignal(row, col) = interpolatedValue;
            else
                % If cubic interpolation failed, try nearest neighbor
                F.Method = 'nearest';
                nearestValue = F(col, row);
                
                if ~isnan(nearestValue)
                    fixedSignal(row, col) = nearestValue;
                else
                    % If nearest neighbor failed, use mean of valid neighbors
                    neighbors = [];
                    for r = max(1, row-2):min(rows, row+2)
                        for c = max(1, col-2):min(cols, col+2)
                            if validMask(r, c)
                                neighbors = [neighbors, gridSignal(r, c)];
                            end
                        end
                    end
                    
                    if ~isempty(neighbors)
                        fixedSignal(row, col) = mean(neighbors);
                    else
                        warning('No valid neighbors found for channel at position (%d, %d)', row, col);
                        % Use global mean of valid channels as last resort
                        fixedSignal(row, col) = mean(validValues);
                    end
                end
            end
        end
    catch ME
        warning('Interpolation failed: %s\nFalling back to nearest neighbor method.', ME.message);
        % Fallback to simple nearest neighbor interpolation
        for i = 1:length(badRows)
            row = badRows(i);
            col = badCols(i);
            
            % Find nearest valid channel
            distances = sqrt((validRows - row).^2 + (validCols - col).^2);
            [~, nearestIdx] = min(distances);
            fixedSignal(row, col) = gridSignal(validRows(nearestIdx), validCols(nearestIdx));
        end
    end
end