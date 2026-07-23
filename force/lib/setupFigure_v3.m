function [fig, ax_f, ax_emg, btnClose, btnCalibrate1, btnCalibrate2, btnCalibrate3, editCalibrate1, editCalibrate2, editCalibrate3, btnZero] = setupFigure_v3(numForceChannels)
    % Create the main figure
    fig = figure('Name', 'Force and EMG Data Streaming', 'Units', 'normalized', 'Position', [0.1 0.1 0.8 0.8]);

    % Create axes for Force and EMG
    ax_f = subplot(2,1,1, 'Parent', fig);
    ax_emg = subplot(2,1,2, 'Parent', fig);
    ylim(ax_f, [-250 250]);
    ylim(ax_emg, [-1000 1000]);
    xlabel(ax_f, 'Time (s)');
    ylabel(ax_f, 'Force (N)');
    xlabel(ax_emg, 'Time (s)');
    ylabel(ax_emg, 'EMG (µV)');

    % Adjust axes positions to make space for the panel
    set(ax_f, 'Position', [0.08 0.55 0.7 0.4]);
    set(ax_emg, 'Position', [0.08 0.1 0.7 0.4]);

    % Create a panel on the right side for UI controls
    panel = uipanel('Parent', fig, 'Title', 'Controls', 'Units', 'normalized', ...
                    'Position', [0.8 0.1 0.18 0.8]);

    % Place UI controls inside the panel
    btnClose = uicontrol('Parent', panel, 'Style', 'togglebutton', 'String', 'Close', ...
        'Units', 'normalized', 'Position', [0.1 0.05 0.8 0.1]);

    btnCalibrate1 = uicontrol('Parent', panel, 'Style', 'togglebutton', 'String', 'Calibrate Force 1', ...
        'Units', 'normalized', 'Position', [0.1 0.85 0.8 0.1]);  % Calibration button for Force 1
    editCalibrate1 = uicontrol('Parent', panel, 'Style', 'edit', 'String', '10', ...
        'Units', 'normalized', 'Position', [0.1 0.75 0.8 0.1]);  % Input for Force 1 Calibration

    btnCalibrate2 = uicontrol('Parent', panel, 'Style', 'togglebutton', 'String', 'Calibrate Force 2', ...
        'Units', 'normalized', 'Position', [0.1 0.6 0.8 0.1]);  % Calibration button for Force 2
    editCalibrate2 = uicontrol('Parent', panel, 'Style', 'edit', 'String', '10', ...
        'Units', 'normalized', 'Position', [0.1 0.5 0.8 0.1]);  % Input for Force 2 Calibration
    
    if numForceChannels == 3
        btnCalibrate3 = uicontrol('Parent', panel, 'Style', 'togglebutton', 'String', 'Calibrate Force 3', ...
            'Units', 'normalized', 'Position', [0.1 0.35 0.8 0.1]);  % Calibration button for Force 3
        editCalibrate3 = uicontrol('Parent', panel, 'Style', 'edit', 'String', '10', ...
            'Units', 'normalized', 'Position', [0.1 0.25 0.8 0.1]);  % Input for Force 3 Calibration
    else
        btnCalibrate3 = []; % If less than 3 channels, these are not needed
        editCalibrate3 = [];
    end
    
    btnZero = uicontrol('Parent', panel, 'Style', 'togglebutton', 'String', 'Zero', ...
        'Units', 'normalized', 'Position', [0.1 0.15 0.8 0.1]);  % Zero button
end
