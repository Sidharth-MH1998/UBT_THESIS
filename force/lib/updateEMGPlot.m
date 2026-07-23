function updateEMGPlot(ax, data, OffsetEMG, numEMGChannels, fs_emg)
    time = (0:length(data)-1) / fs_emg;
    offset = OffsetEMG * (0:numEMGChannels-1)';
    plot(ax, time, data + offset);
    ylim(ax, [-OffsetEMG OffsetEMG*numEMGChannels]);
    xlim(ax, [max(0, time(end)-10), time(end)]);
end