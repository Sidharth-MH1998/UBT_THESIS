function [fig, ax_f, ax_emg, btnClose] = setupFigure()
    fig = figure('Name', 'Force and EMG Data Streaming');
    ax_f = subplot(2,1,1);
    ax_emg = subplot(2,1,2);
    ylim(ax_f, [-250 250]);
    ylim(ax_emg, [-1000 1000]);
    xlabel(ax_f, 'Time (s)');
    ylabel(ax_f, 'Force (N)');
    xlabel(ax_emg, 'Time (s)');
    ylabel(ax_emg, 'EMG (µV)');
    btnClose = uicontrol('Style', 'togglebutton', 'String', 'Close', ...
        'Units', 'normalized', 'Position', [0.9 0.02 0.08 0.05]);
end