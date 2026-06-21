function [segm_MUPulses, segm_fr, segm_mean_fr, segm_spikeTrain, segm_smoothedDRs] = segmentMUPulses(MUPulses, fr, spikeTrain)

% Segmentation of the MU Pulses, firing rates and mean firing rates
% depending on the stage in the force tracking motion

emg_len = length(spikeTrain);

% Standard EMG (no samples added) should be 25*2048 = 51200 samples long

if ~isequal(emg_len,51200)
    sample_add = (emg_len - 51200)/2; % number of samples added to the original signal at beginning and end
else
    sample_add = 0;
end

t_force = [5 7.5 10 12.5 15 17.5 20]; % stages start/end times in secs
t_emg = round(t_force*2048) + sample_add; % EMG timings, using force and EMG sampling freq, size 1x7

segm_MUPulses = cell( 6 , length(MUPulses)); % For the pulses in the 6 stages
segm_fr = cell( 6 , length(MUPulses)); % For the instantaneous firing rates in the 6 stages
segm_mean_fr = zeros( 6 , length(MUPulses)); % For the mean firing rates in the 6 stages
segm_spikeTrain = zeros( 6 , length(MUPulses), 2.5*2048);
segm_smoothedDRs = zeros( 6 , length(MUPulses), 2.5*2048);

smoothedDRs = smoothFirings(spikeTrain,2048); 
spikeTrain = full(spikeTrain)'; % convert to row-wise time series

for mu=1:length(MUPulses)

    temp_Pulses = MUPulses{1,mu};
    temp_fr = fr{1,mu};
    for st = 1:6 % Divide into six stages
        segm_MUPulses{st,mu} = temp_Pulses(temp_Pulses>t_emg(st) & temp_Pulses<t_emg(st+1));
        segm_fr{st,mu} = temp_fr(temp_Pulses>t_emg(st) & temp_Pulses<t_emg(st+1));
        segm_spikeTrain(st,mu,:) = spikeTrain(mu,t_emg(st)+1:t_emg(st+1));
        segm_smoothedDRs(st,mu,:) = smoothedDRs(mu,t_emg(st)+1:t_emg(st+1));
        % If no pulses are in the stage, then mean_fr will stay in 0
        if ~isempty(segm_MUPulses{st,mu})
            segm_mean_fr(st,mu) = mean(segm_fr{st,mu});
        end
    end

end