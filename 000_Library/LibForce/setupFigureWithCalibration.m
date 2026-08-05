function [fig, ax_f, ax_emg, btnClose, btnCalibrate1, btnCalibrate2, btnCalibrate3, editCalibrate1, editCalibrate2, editCalibrate3, btnZero, btnReverse1, btnReverse2, btnReverse3, btnMaxMode1, btnMaxMode2, btnMaxMode3] = setupFigureWithCalibration(numForceChan, numEMGChanToPlot)
    % Create figure
    fig = figure('Name', 'Force and EMG Streaming', 'NumberTitle', 'off', 'Position', [100, 100, 1200, 600]);
    
    % Create force plot axes
    ax_f = subplot(2, 1, 1);
    title(ax_f, 'Force Data');
    xlabel(ax_f, 'Time (s)');
    ylabel(ax_f, 'Force (N)');
    grid(ax_f, 'on');  % Enable grid lines on force plot
    
    % Create EMG plot axes
    ax_emg = subplot(2, 1, 2);
    title(ax_emg, ['EMG Data (Plotting ', num2str(numEMGChanToPlot), ' Channels)']);
    xlabel(ax_emg, 'Time (s)');
    ylabel(ax_emg, 'Amplitude (uV)');
    grid(ax_emg, 'on');  % Enable grid lines on EMG plot
    
    % Create a control panel for buttons and inputs
    controlPanel = uipanel('Title', 'Controls', 'Position', [0.8, 0.1, 0.18, 0.8]);

    % Close button
    btnClose = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Close', 'Position', [10, 300, 100, 30], 'BackgroundColor', 'red');
    
    % Calibrate Force Channel 1
    if numForceChan >= 1
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Calibrate Force 1', 'Position', [10, 260, 100, 20]);
        editCalibrate1 = uicontrol(controlPanel, 'Style', 'edit', 'String', '10', 'Position', [120, 260, 60, 30]);
        btnCalibrate1 = uicontrol(controlPanel, 'Style', 'pushbutton', 'String', 'Apply', 'Position', [190, 260, 60, 30]);
    else
        editCalibrate1 = [];
        btnCalibrate1 = [];
    end
    
    % Calibrate Force Channel 2
    if numForceChan >= 2
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Calibrate Force 2', 'Position', [10, 220, 100, 20]);
        editCalibrate2 = uicontrol(controlPanel, 'Style', 'edit', 'String', '10', 'Position', [120, 220, 60, 30]);
        btnCalibrate2 = uicontrol(controlPanel, 'Style', 'pushbutton', 'String', 'Apply', 'Position', [190, 220, 60, 30]);
    else
        editCalibrate2 = [];
        btnCalibrate2 = [];
    end
    
    % Calibrate Force Channel 3
    if numForceChan == 3
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Calibrate Force 3', 'Position', [10, 180, 100, 20]);
        editCalibrate3 = uicontrol(controlPanel, 'Style', 'edit', 'String', '10', 'Position', [120, 180, 60, 30]);
        btnCalibrate3 = uicontrol(controlPanel, 'Style', 'pushbutton', 'String', 'Apply', 'Position', [190, 180, 60, 30]);
    else
        editCalibrate3 = [];
        btnCalibrate3 = [];
    end
    
    % Zero Force Button
    btnZero = uicontrol(controlPanel, 'Style', 'pushbutton', 'String', 'Zero Force', 'Position', [10, 140, 100, 30]);

    % Reverse Force Buttons
    if numForceChan >= 1
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Reverse Force 1', 'Position', [10, 100, 100, 20]);
        btnReverse1 = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Reverse', 'Position', [120, 100, 60, 30], 'BackgroundColor', 'yellow');
    else
        btnReverse1 = [];
    end
    
    if numForceChan >= 2
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Reverse Force 2', 'Position', [10, 60, 100, 20]);
        btnReverse2 = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Reverse', 'Position', [120, 60, 60, 30], 'BackgroundColor', 'yellow');
    else
        btnReverse2 = [];
    end

    if numForceChan == 3
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Reverse Force 3', 'Position', [10, 20, 100, 20]);
        btnReverse3 = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Reverse', 'Position', [120, 20, 60, 30], 'BackgroundColor', 'yellow');
    else
        btnReverse3 = [];
    end
    
    % Max Force Mode Buttons
    if numForceChan >= 1
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Max Force Mode 1', 'Position', [10, -20, 100, 20]);
        btnMaxMode1 = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Record', 'Position', [120, -20, 60, 30], 'BackgroundColor', 'green');
    else
        btnMaxMode1 = [];
    end
    
    if numForceChan >= 2
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Max Force Mode 2', 'Position', [10, -60, 100, 20]);
        btnMaxMode2 = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Record', 'Position', [120, -60, 60, 30], 'BackgroundColor', 'green');
    else
        btnMaxMode2 = [];
    end

    if numForceChan == 3
        uicontrol(controlPanel, 'Style', 'text', 'String', 'Max Force Mode 3', 'Position', [10, -100, 100, 20]);
        btnMaxMode3 = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Record', 'Position', [120, -100, 60, 30], 'BackgroundColor', 'green');
    else
        btnMaxMode3 = [];
    end
end