function [pulse, discharges, states] = decode_online_grid_window(emg, states, fs)
%DECODE_ONLINE_GRID_WINDOW Decode one shared window with independent grid states.
% EMG rows follow cfg.calibChannels order after selecting cfg.emgChannels.
% Outputs combine MUs in grid order; each state's muIndices selects its MUs.

nSamples = size(emg,2);
nMU = sum(cellfun(@(state) state.nMU, states));
pulse = zeros(nMU,nSamples);
discharges = false(nSamples,nMU);
for gridIdx = 1:numel(states)
    state = states{gridIdx};
    if state.nMU == 0
        continue;
    end
    gridEMG = emg(state.channelRows,:);
    goodEMG = gridEMG(~state.mask,:);
    noiseCenters = repmat(state.centroid(:,1)', nSamples, 1);
    spikeCenters = repmat(state.centroid(:,2)', nSamples, 1);
    [gridPulse, gridDischarges, state.overlap] = getspikesonline( ...
        goodEMG, state.extensionfactor, state.overlap, state.MUfilt, ...
        state.normval, noiseCenters, spikeCenters, nSamples, fs);
    pulse(state.muIndices,:) = gridPulse;
    discharges(:,state.muIndices) = gridDischarges;
    states{gridIdx} = state;
end
end
