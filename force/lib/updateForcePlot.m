function updateForcePlot(ax, data, calibration_value, fs_force)
    time = (0:length(data)-1) / fs_force;
    plot(ax, time, data);
    ylim(ax, [-2.5 2.5] * calibration_value);
    xlim(ax, [max(0, time(end)-10), time(end)]);
end