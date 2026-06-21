function [regrCoeff, recThresh, RMSE] = MUimportance(spikes_g1, spikes_g2, all_force10, all_force20, fs, fs_force, plotFlag)
    % This function performs a MU importance analysis when using smoothed
    % MU discharge rates (DRs) as inputs for a force regression.
    % The function iterates over all trials of a single subject
    % Additionally, MUs coefficients/ weights are plotted against their
    % recruitment threshold
    % INPUTS
    % spiketrains_g1, spiketrains_g2: Spiketrain data for grids 1 and 2
    % all_force10, all_force20: Force data for 10% and 20% force levels
    % fs: Sampling frequency of spiketrains
    % fs_force: Sampling frequency of force data
    % plotFlag: 1 when plot should be generated
    % OUTPUTS
    % regrCoeff: cell array containing a column vector of regression coefficients gathered per condition
    % recThresh: cell array containing a column vector of recruitment thresholds gathered per condition
    % RMSE: matrix containing rmse values obtained from the regression per trial
    %
    % Author: Renato Mio
    % Created: 23.01.2025

% Parameters for finding MU active periods
firingThreshHz = 2; % minimum spiking frequency
restThresh = 0.5; % time in seconds between spikes to go from active to inactive
minActiveDuration = 1;

% For determining unimportant MUs
weightThreshold = 0.05; % Minimum importance/weight threshold


% Get dimensions
digits = size(spikes_g1, 1);
fLevels = size(spikes_g1, 2);
trials = size(spikes_g1, 3);

% Initialise variables to use
regrCoeff = cell(digits,fLevels);
recThresh = cell(digits,fLevels);
RMSE = zeros(digits,fLevels,trials);

% Iterate over all trials
for d = 1:digits
    for f = 1:fLevels
        for t = 1:trials
            disp(['Processing digit ', num2str(d), ', force level ', num2str(f), ', trial ', num2str(t)])
            % Get spiketrains for current trial
            spiketrain_g1 = spikes_g1{d, f, t};
            spiketrain_g2 = spikes_g2{d, f, t};

            % Get force for the trial
            if f == 1 % Force level 10%
                force = squeeze(all_force10(d, t, :, :));
            else % Force level 20%
                force = squeeze(all_force20(d, t, :, :));
            end
            
            % Get active periods from spike trains
            [activePeriods_g1] = find_MU_active_periods_v2(spiketrain_g1, firingThreshHz, fs, restThresh, minActiveDuration, 0);
            [activePeriods_g2] = find_MU_active_periods_v2(spiketrain_g2, firingThreshHz, fs, restThresh, minActiveDuration, 0);    
            
            % Find recruitment thresholds as the force at the time of activity
            recruitTimes_g1 = cellfun(@(x) min(x,[],"all"), activePeriods_g1);
            recruitTimes_g2 = cellfun(@(x) min(x,[],"all"), activePeriods_g2);
            recruitThresh_g1 = force(d,floor(recruitTimes_g1.*fs_force));
            recruitThresh_g2 = force(d,floor(recruitTimes_g2.*fs_force));
            
            % Make sure active periods have just one start and one end by joining them
            activePeriods_g1 = cellfun(@(x) [min(x), max(x)],activePeriods_g1,'UniformOutput',false);
            activePeriods_g2 = cellfun(@(x) [min(x), max(x)],activePeriods_g2,'UniformOutput',false);

            % Get smoothed DRs with standardised time vectors
            [smoothedDRs_stand_g1, ~, recruitThresh_g1] = smoothDRs_SVR_standardised(spiketrain_g1, activePeriods_g1, force(d,:), fs, fs_force, fs);
            [smoothedDRs_stand_g2, standTime, recruitThresh_g2] = smoothDRs_SVR_standardised(spiketrain_g2, activePeriods_g2, force(d,:), fs, fs_force, fs);
            
            % Join two grids data
            smoothedDRs = [smoothedDRs_stand_g1; smoothedDRs_stand_g2]'; % set samples as first dimension
            recruitThresh = [recruitThresh_g1, recruitThresh_g2];
            
            % We only keep the MUs with active periods over 55 seconds
            activeDurations = [cellfun(@(x) max(x,[],"all") - min(x,[],"all"), activePeriods_g1); cellfun(@(x) max(x,[],"all") - min(x,[],"all"), activePeriods_g2)];
            activeMUs = find(activeDurations>55);

            % Resample the force signal to match the standard time vector
            % (sampled at fs)
            timeForce = (0:length(force(d,:)) - 1) / fs_force; % Original time vector for force
            force_resamp = interp1(timeForce, force(d,:), standTime, 'linear', 0)'; % Pad missing values with zeros, samples as first dimension
            
            % Apply dynamic sampling to keep the focus on the edges where the force varies more
            fs_middle = 250;  % Reduced middle sampling frequency
            focus_duration = 12;  % High resolution duration in seconds
            [smoothedDRs_sampled, force_sampled] = dynamicSampling(smoothedDRs(:,activeMUs), force_resamp, fs, fs_middle, focus_duration);
            
            % Fit linear model using non-negative least squares regression
            % (MUs contribution cannot be negative)
            % b = lsqnonneg(smoothedDRs_sampled, force_sampled);

            % Iteratively remove low-importance MUs
            weightsChanged = true;
            while weightsChanged
                % Fit linear model
                b = lsqnonneg(smoothedDRs_sampled, force_sampled);
                
                % Identify MUs with weights below the threshold
                lowImportanceMUs = find(b < weightThreshold);

                % Check if there are changes to be made
                if isempty(lowImportanceMUs)
                    weightsChanged = false; % Stop if all weights are above the threshold
                else
                    % Remove low-importance MUs
                    smoothedDRs_sampled(:,lowImportanceMUs) = [];
                    activeMUs(lowImportanceMUs) = [];
                end
            end 
            
            % Predict the curve using the regression coefficients
            predictions = smoothedDRs_sampled * b;  % X is your design matrix, b are the regression coefficients
            
            % Get RMSE
            rmse = sqrt(mean((force_sampled - predictions).^2)); 
            
            % Save and append results
            RMSE(d,f,t) = rmse;
            regrCoeff{d,f} = [regrCoeff{d,f}; b];
            recThresh{d,f} = [recThresh{d,f}; recruitThresh(:,activeMUs)'];

        end
    end
end

% Plot if needed
if plotFlag
    % Plot scatter of recruitment thresholds vs regression
    % coefficients/weights per condition (digit x force level)
    figure;
    for d = 1:digits
        for f = 1:fLevels
            subplot(digits, fLevels, (d - 1) * fLevels + f);
            coeffs = regrCoeff{d, f};
            thresholds = recThresh{d, f};
            scatter(thresholds(:), coeffs(:), 'filled');
            xlabel('Recruitment Threshold (Force)');
            ylabel('Regression Coefficient');
            title(['Digit ', num2str(d), ', Force Level ', num2str(f)]);
            grid on;
        end
    end
end

end