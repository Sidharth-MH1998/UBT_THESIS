function normalisedMatrix = normaliseMatrix(matrix)
    % Normalize the entire matrix so that all values fall within the range [0, 1].
    % Input:
    %   - matrix: A 2D matrix of any size.
    % Output:
    %   - normalizedMatrix: A 2D matrix where all values are normalized between 0 and 1.

    % Get the minimum and maximum values from the entire matrix
    minVal = min(matrix(:));
    maxVal = max(matrix(:));
    
    % Normalize the matrix
    normalisedMatrix = (matrix - minVal) / (maxVal - minVal);
end
