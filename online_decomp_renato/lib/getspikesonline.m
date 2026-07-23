function [PulseT, Distime, esample2] = getspikesonline(EMGtmp, extensionfactor, esample2, MUfilt, norm, noise_centroids, spike_centroids, nsamp, fsamp)
    esample1 = demean(extend(EMGtmp, extensionfactor));
    esample = esample1(:,1:nsamp);
    esample(:,1:extensionfactor-1) = esample(:,1:extensionfactor-1) + esample2;
    esample2 = esample1(:,nsamp+1:end);

    PulseT = ((MUfilt * esample) .* abs(MUfilt * esample)) ./ norm'; 
    [spikes1, ~] = islocalmax(PulseT', 1, 'MinSeparation', round(fsamp*0.02)); %20ms
    isSpikeClass = abs(PulseT' - noise_centroids) > abs(PulseT' - spike_centroids);
    Distime = spikes1 & isSpikeClass;
