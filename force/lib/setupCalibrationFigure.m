function [fig, ax_f, btnClose, btnCalibrate1, btnCalibrate2, btnCalibrate3, editCalibrate1, editCalibrate2, editCalibrate3, btnZero, btnReverse1, btnReverse2, btnReverse3, btnSaveZero] = setupCalibrationFigure(numForceChan)
    % Create figure
    fig = figure('Name', 'Force Calibration', 'NumberTitle', 'off', 'Position', [100, 100, 800, 600]);
    
    % Create force plot axes
    ax_f = axes('Position', [0.1, 0.4, 0.65, 0.55]); % Adjusted for better layout
    title(ax_f, 'Force Data (Calibration)');
    xlabel(ax_f, 'Time (s)');
    ylabel(ax_f, 'Force (N)');
    grid(ax_f, 'on');  % Enable grid lines on force plot
    
    % Create a control panel for buttons and inputs
    controlPanel = uipanel('Title', 'Controls', 'Position', [0.8, 0.1, 0.18, 0.8]);

    % Close button
    btnClose = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Close', 'Position', [10, 300, 100, 30], 'BackgroundColor', 'red');
    
    % Calibrate Force Channel 1
    if numForceChan >= 1
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Calibrate Force 1', 'Position', [10, 260, 100, 20]);
        editCalibrate1 = uicontrol(controlPanel, 'Style', 'edit', 'String', 'Value', 'Position', [120, 260, 60, 30]);
        btnCalibrate1 = uicontrol(controlPanel, 'Style', 'pushbutton', 'String', 'Calibrate', 'Position', [190, 260, 70, 30]);
    else
        editCalibrate1 = [];
        btnCalibrate1 = [];
    end
    
    % Calibrate Force Channel 2
    if numForceChan >= 2
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Calibrate Force 2', 'Position', [10, 220, 100, 20]);
        editCalibrate2 = uicontrol(controlPanel, 'Style', 'edit', 'String', 'Value', 'Position', [120, 220, 60, 30]);
        btnCalibrate2 = uicontrol(controlPanel, 'Style', 'pushbutton', 'String', 'Calibrate', 'Position', [190, 220, 70, 30]);
    else
        editCalibrate2 = [];
        btnCalibrate2 = [];
    end
    
    % Calibrate Force Channel 3
    if numForceChan == 3
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Calibrate Force 3', 'Position', [10, 180, 100, 20]);
        editCalibrate3 = uicontrol(controlPanel, 'Style', 'edit', 'String', 'Value', 'Position', [120, 180, 60, 30]);
        btnCalibrate3 = uicontrol(controlPanel, 'Style', 'pushbutton', 'String', 'Calibrate', 'Position', [190, 180, 70, 30]);
    else
        editCalibrate3 = [];
        btnCalibrate3 = [];
    end
    
    % Zero Force Button
    btnZero = uicontrol(controlPanel, 'Style', 'pushbutton', 'String', 'Zero Force', 'Position', [10, 140, 100, 30]);

    % Reverse Force Buttons
    if numForceChan >= 1
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Reverse Force 1', 'Position', [10, 100, 100, 20]);
        btnReverse1 = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Reverse', 'Position', [120, 100, 70, 30], 'BackgroundColor', 'yellow');
    else
        btnReverse1 = [];
    end
    
    if numForceChan >= 2
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Reverse Force 2', 'Position', [10, 60, 100, 20]);
        btnReverse2 = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Reverse', 'Position', [120, 60, 70, 30], 'BackgroundColor', 'yellow');
    else
        btnReverse2 = [];
    end

    if numForceChan == 3
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Reverse Force 3', 'Position', [10, 20, 100, 20]);
        btnReverse3 = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Reverse', 'Position', [120, 20, 70, 30], 'BackgroundColor', 'yellow');
    else
        btnReverse3 = [];
    end
    
    % Save Zero Button
    btnSaveZero = uicontrol(controlPanel, 'Style', 'pushbutton', 'String', 'Save Zero', 'Position', [10, 350, 100, 30], 'BackgroundColor', 'cyan');
end
