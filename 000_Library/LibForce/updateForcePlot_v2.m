function updateForcePlot_v2(ax, data, fs_force)
    time = (0:size(data,1)-1) / fs_force;
    plot(ax, time, data(:,1), 'r', ...
              time, data(:,2), 'b'); % Plot both force streams
    ylim(ax, [-2.5 2.5] * max(abs(data(:))));
    xlim(ax, [max(0, time(end)-10), time(end)]);
    legend(ax, 'Force 1', 'Force 2');
end
