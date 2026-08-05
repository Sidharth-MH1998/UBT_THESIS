function covDRs = computeCoVDRs(smoothedDRs, recruitThresh, cohortRanges)
    % Function to compute the coefficient of variation (CV) of smoothed DRs
    % for both grids, grouped by cohorts based on recruitment thresholds.

    % Inputs:
    % smoothedDRs - Cell array (1 x nMUs), each cell contains [time, smoothedDR]
    % recThresholds - Array of recruitment thresholds (1 x nMUs)
    % cohortRanges - Array (1 x numCohorts+1) specifying cohort threshold edges

    % Output:
    % covDRs - Cell array (1 x numCohorts), each cell containing a vector of CVs
    %             (for the MUs within that cohort) across both grids.

    % Number of cohorts
    numCohorts = length(cohortRanges) - 1;

    % Initialize cell array to store CV results
    covDRs = cell(1, numCohorts);

    % Loop through each cohort
    for cohortIdx = 1:numCohorts
        % Find MUs within the current cohort range
        cohortMask = recruitThresh >= cohortRanges(cohortIdx) & ...
                     recruitThresh < cohortRanges(cohortIdx + 1);
        mus = find(cohortMask);

        % Extract smoothed DRs for the MUs in this cohort
        cohortCVs = [];
        for muIdx = 1:length(mus)
            % Extract the smoothed DR (second column of the matrix)
            smoothedDR = smoothedDRs{mus(muIdx)}(:, 2);

            % Compute the CV for this MU
            muMean = mean(smoothedDR);
            muStd = std(smoothedDR);
            muCV = muStd / muMean;

            % Append to cohort CVs
            cohortCVs = [cohortCVs; muCV];
        end

        % Save results for the cohort
        covDRs{cohortIdx} = cohortCVs;
    end
end