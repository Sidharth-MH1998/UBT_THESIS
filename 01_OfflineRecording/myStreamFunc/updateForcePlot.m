function updateForcePlot(ax_f, forceLines, forceData, fs_force, numForceChan, ...
    displayTime, bufferTime, ~, ~, currentForceIndex)

    if currentForceIndex < 1 % first sample
        return
    end

    currentTime = currentForceIndex / fs_force;
    idxStart = max(1, currentForceIndex - round(displayTime * fs_force));
    idx = idxStart:currentForceIndex;
    t = idx / fs_force;

    for i = 1:numForceChan
        clearpoints(forceLines(i));
        addpoints(forceLines(i), t, forceData(idx, i));
    end

    xlim(ax_f, [currentTime - displayTime, currentTime + bufferTime]);
    ylim(ax_f, [-10 110]);
end