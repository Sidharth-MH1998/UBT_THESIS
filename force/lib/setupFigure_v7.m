function [fig, ax_f, ax_emg, btnClose, btnZero, btnRecord, btnRecordTracking, forceChanDropdown, traceTypeDropdown, tWaitBox, tSlopeBox, tPlateauBox, forceTargetBox, forceSignLabel, forceSignCheckbox, participantIDBox, trialBox, sessionBox] = setupFigure_v7(toggleEMG)    % Create figure
    fig = figure('Name', 'Force and EMG Streaming', 'NumberTitle', 'off', 'Position', [20, 125, 2500, 1080]);
    
    if toggleEMG
        % Create force plot axes
        ax_f = subplot(2, 1, 1);
        set(ax_f, 'Position', [0.05, 0.55, 0.75, 0.35]); % This shrinks the axes horizontally
        title(ax_f, 'Force Data');
        xlabel(ax_f, 'Time (s)');
        ylabel(ax_f, 'Force (%)');
        grid(ax_f, 'on'); % Enable grid lines on force plot
        
        % Create EMG plot axes
        ax_emg = subplot(2, 1, 2);
        set(ax_emg, 'Position', [0.05, 0.1, 0.75, 0.35]);
        title(ax_emg, 'EMG Data');
        xlabel(ax_emg, 'Time (s)');
        ylabel(ax_emg, 'Amplitude (uV)');
        grid(ax_emg, 'on'); % Enable grid lines on EMG plot
    else % only create bigger force axes
        ax_f = subplot(1, 1, 1);
        set(ax_f, 'Position', [0.05, 0.1, 0.75, 0.75]); % This shrinks the axes horizontally
        title(ax_f, 'Force Data');
        xlabel(ax_f, 'Time (s)');
        ylabel(ax_f, 'Force (%)');
        grid(ax_f, 'on'); % Enable grid lines on force plot
        
        ax_emg = [];
    end
    
    % Create a control panel for buttons and inputs
    controlPanel = uipanel('Title', 'Controls', 'Position', [0.81, 0.1, 0.18, 0.85], 'Units', 'normalized');
    
    % Trial information
    uicontrol(controlPanel, 'Style', 'text', 'String', 'Trial information: Fill this first as it will be used to export the file.', 'Position', [10, 730, 320, 20]);

    % Participant ID Input Box
    uicontrol(controlPanel, 'Style', 'text', 'String', 'Participant ID:', 'Position', [10, 700, 100, 20]);
    participantIDBox = uicontrol(controlPanel, 'Style', 'edit', 'String', '', 'Position', [10, 680, 100, 20]);
    
    % Trial Input Box (must be an integer)
    uicontrol(controlPanel, 'Style', 'text', 'String', 'Trial:', 'Position', [120, 700, 100, 20]);
    trialBox = uicontrol(controlPanel, 'Style', 'edit', 'String', '', 'Position', [120, 680, 100, 20]);
    
    % Session Input Box (must be an integer)
    uicontrol(controlPanel, 'Style', 'text', 'String', 'Session:', 'Position', [240, 700, 100, 20]);
    sessionBox = uicontrol(controlPanel, 'Style', 'edit', 'String', '', 'Position', [240, 680, 100, 20]);

    % Force trace selection (dropdown for Trapezium or Triangular)
    uicontrol(controlPanel, 'Style', 'text', 'String', 'Select Trace Type:', 'Position', [8, 560, 100, 20]);
    traceTypeDropdown = uicontrol(controlPanel, 'Style', 'popupmenu', 'String', {'Trapezium', 'Triangular'}, 'Position', [10, 540, 100, 20]);

    % Force Channel Dropdown
    uicontrol(controlPanel, 'Style', 'text', 'String', 'Select force channel to control:', 'Position', [200, 560, 160, 20]);
    forceChanDropdown = uicontrol(controlPanel, 'Style', 'popupmenu', 'String', {'<HTML><FONT COLOR="red">Chan 1 (Thumb)</HTML>','<HTML><FONT COLOR="blue">Chan 2 (Index)</HTML>','<HTML><FONT COLOR="green">Chan 3 (Middle)</HTML>'}, 'Position', [200, 540, 120, 20]);

    % forceTarget Input Box
    uicontrol(controlPanel, 'Style', 'text', 'String', 'Force Target (%):', 'Position', [10, 480, 100, 20]);
    forceTargetBox = uicontrol(controlPanel, 'Style', 'edit', 'String', '20', 'Position', [10, 460, 100, 20]);

    % Add Force Sign Toggle Checkbox (New Control)
    uicontrol(controlPanel, 'Style', 'text', 'String', 'Reverse force?', 'Position', [10, 420, 80, 20]);
    forceSignLabel = uicontrol(controlPanel, 'Style', 'text', 'String', sprintf('%s\n%s','(+): Flexion', '(-): Extension '), 'Position', [50, 380, 100, 40]);
    forceSignCheckbox = uicontrol(controlPanel, 'Style', 'checkbox', 'Position', [30, 400, 20, 20], 'Value', 0); % Default is unchecked (Flexion Positive)

    % Record Force Tracking Button
    btnRecordTracking = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Record Force Tracking', 'Position', [10, 300, 150, 30], 'BackgroundColor', 'yellow');
        
    % tWait Input Box
    uicontrol(controlPanel, 'Style', 'text', 'String', 'tWait (s):', 'Position', [200, 480, 100, 20]);
    tWaitBox = uicontrol(controlPanel, 'Style', 'edit', 'String', '2', 'Position', [200, 460, 100, 20]);
    
    % tSlope Input Box
    uicontrol(controlPanel, 'Style', 'text', 'String', 'tSlope (s):', 'Position', [200, 420, 100, 20]);
    tSlopeBox = uicontrol(controlPanel, 'Style', 'edit', 'String', '3', 'Position', [200, 400, 100, 20]);
    
    % tPlateau Input Box
    uicontrol(controlPanel, 'Style', 'text', 'String', 'tPlateau (s):', 'Position', [200, 360, 100, 20]);
    tPlateauBox = uicontrol(controlPanel, 'Style', 'edit', 'String', '5', 'Position', [200, 340, 100, 20]);
    
    % Record Button (manual)
    btnRecord = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Record', 'Position', [120, 80, 100, 30], 'BackgroundColor', 'green');

    % Zero Force Button
    btnZero = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Zero Force', 'Position', [10, 80, 100, 30]);
    
    % Close button
    btnClose = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Close', 'Position', [10, 20, 100, 30], 'BackgroundColor', 'red');
end