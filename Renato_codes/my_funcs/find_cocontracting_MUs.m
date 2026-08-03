function [cocontractingMUs, inactiveMUs] = find_cocontracting_MUs(spikeTrains, fs)

firingThreshHz = 5; % minimum spiking frequency
restThresh = 0.5; % time in seconds between spikes to go from active to inactive
minActiveDuration = 1;

[activePeriods] = find_MU_active_periods_v2(spikeTrains, firingThreshHz, fs, restThresh, minActiveDuration, 0);

totalActiveTimes = zeros(length(activePeriods),1);
for period=1:length(activePeriods)
    if not(isempty(activePeriods{period,1}))
        totalActiveTimes(period,1) = sum(activePeriods{period,1}(:,2)-activePeriods{period,1}(:,1));
    else
        totalActiveTimes(period,1) = 0;
    end
end

trialDuration = size(spikeTrains,1)/fs; % total trial duration to which we compare the active period

cocontractingMUs = find(trialDuration - totalActiveTimes < 8); % the target force is 0 during 10 seconds, so we consider 8 to be our threshold
inactiveMUs = find(totalActiveTimes == 0);