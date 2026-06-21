function exportData = exportSmoothDRs(smoothedRates, timeVec, force, fs_force, recruitmentThresh)
    % EXPORTDRSFORPYTORCH Exports data formatted for PyTorch compatibility.
    %
    % Parameters:
    %   smoothedRates: Matrix (nMUs x nTimePoints) of smoothed discharge rates.
    %   timeVec: Vector (1 x nTimePoints) of time points corresponding to smoothedRates.
    %   force: Vector (nForceSamples x 1) of force signal.
    %   fs_force: Sampling frequency of the force signal (Hz).
    %   recruitmentThresh: Vector (1 x nMUs) of recruitment thresholds.
    %
    % Returns:
    %   exportData: Struct containing:
    %       - features: Combined matrix (nTimePoints x [nMUs + 1]) of smoothedRates and resampledForce.
    %       - timeVec: Resampled time vector (1 x nTimePoints).
    %       - recruitmentThresh: Recruitment thresholds for MUs (1 x nMUs).

    % Validate input dimensions
    [nMUs, nTimePoints] = size(smoothedRates);
    if length(timeVec) ~= nTimePoints
        error('timeVec length must match the number of columns in smoothedRates.');
    end
    if ~isvector(force)
        error('Force must be a vector.');
    end
    if numel(recruitmentThresh) ~= nMUs
        error('recruitmentThresh must have the same length as the number of MUs.');
    end

    % Resample the force signal to match timeVec
    timeForce = (0:length(force) - 1) / fs_force; % Original time vector for force
    resampledForce = interp1(timeForce, force, timeVec, 'linear', 0); % Pad missing values with zeros

    % Combine smoothedRates and resampledForce
    features = [smoothedRates', resampledForce']; % Shape: (nTimePoints, nMUs + 1)

    % Construct the export structure
    exportData = struct();
    exportData.features = features; % Combined features for PyTorch (time-major)
    exportData.timeVec = timeVec; % Time vector
    exportData.recruitmentThresh = recruitmentThresh; % Recruitment thresholds
end