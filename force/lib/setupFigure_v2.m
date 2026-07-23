function [fig, ax_f, ax_emg, btnClose, btnCalibrate1, btnCalibrate2, editCalibrate1, editCalibrate2, btnZero] = setupFigure_v2()
    fig = figure('Name', 'Force and EMG Data Streaming');
    
    % Setup Axes
    ax_f = subplot(2,1,1);
    ax_emg = subplot(2,1,2);
    ylim(ax_f, [-250 250]);
    ylim(ax_emg, [-1000 1000]);
    xlabel(ax_f, 'Time (s)');
    ylabel(ax_f, 'Force (N)');
    xlabel(ax_emg, 'Time (s)');
    ylabel(ax_emg, 'EMG (µV)');
    
    % Setup Buttons
    btnClose = uicontrol('Style', 'togglebutton', 'String', 'Close', ...
        'Units', 'normalized', 'Position', [0.9 0.02 0.08 0.05]);
    btnCalibrate1 = uicontrol('Style', 'togglebutton', 'String', 'Calibrate Force 1', ...
        'Units', 'normalized', 'Position', [0.7 0.1 0.15 0.05]);  % Calibration button for Force 1
    btnCalibrate2 = uicontrol('Style', 'togglebutton', 'String', 'Calibrate Force 2', ...
        'Units', 'normalized', 'Position', [0.7 0.02 0.15 0.05]);  % Calibration button for Force 2
    btnZero = uicontrol('Style', 'togglebutton', 'String', 'Zero', ...
        'Units', 'normalized', 'Position', [0.9 0.1 0.08 0.05]);  % Zero button
    
    % Setup Textboxes for Calibration
    editCalibrate1 = uicontrol('Style', 'edit', 'String', '10', ...
        'Units', 'normalized', 'Position', [0.6 0.1 0.08 0.05]);  % Input for Force 1 Calibration
    editCalibrate2 = uicontrol('Style', 'edit', 'String', '10', ...
        'Units', 'normalized', 'Position', [0.6 0.02 0.08 0.05]);  % Input for Force 2 Calibration
end