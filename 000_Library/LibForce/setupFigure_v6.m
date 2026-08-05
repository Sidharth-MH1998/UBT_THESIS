function [fig, ax_f, ax_emg, btnClose, btnZero, btnRecord, btnRecordTracking, forceChanDropdown, tWaitBox, tSlopeBox, tPlateauBox, forceTargetBox, participantIDBox, trialBox, sessionBox] = setupFigure_v6(toggleEMG)
    % Create figure
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
    
    % Participant ID Input Box
    uicontrol(controlPanel, 'Style', 'text', 'String', 'Participant ID:', 'Position', [10, 300, 100, 20]);
    participantIDBox = uicontrol(controlPanel, 'Style', 'edit', 'String', '', 'Position', [10, 280, 100, 20]);
    
    % Trial Input Box (must be an integer)
    uicontrol(controlPanel, 'Style', 'text', 'String', 'Trial:', 'Position', [120, 300, 100, 20]);
    trialBox = uicontrol(controlPanel, 'Style', 'edit', 'String', '', 'Position', [120, 280, 100, 20]);
    
    % Session Input Box (must be an integer)
    uicontrol(controlPanel, 'Style', 'text', 'String', 'Session:', 'Position', [240, 300, 100, 20]);
    sessionBox = uicontrol(controlPanel, 'Style', 'edit', 'String', '', 'Position', [240, 280, 100, 20]);
    
%     % Force Target Input Box
%     uicontrol(controlPanel, 'Style', 'text', 'String', 'Force Target:', 'Position', [10, 260, 100, 20]);
%     forceTargetBox = uicontrol(controlPanel, 'Style', 'edit', 'String', '', 'Position', [10, 240, 100, 20]);
    
    % Record Force Tracking Button
    btnRecordTracking = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Record Force Tracking', 'Position', [10, 500, 150, 30], 'BackgroundColor', 'yellow');
    
    % Force Channel Dropdown
    uicontrol(controlPanel, 'Style', 'text', 'String', 'Select Force Channel:', 'Position', [10, 440, 120, 20]);
    forceChanDropdown = uicontrol(controlPanel, 'Style', 'popupmenu', 'String', {'Channel 1', 'Channel 2', 'Channel 3'}, 'Position', [10, 420, 100, 20]);
    
    % forceTarget Input Box
    uicontrol(controlPanel, 'Style', 'text', 'String', 'Force Target (%):', 'Position', [10, 380, 100, 20]);
    forceTargetBox = uicontrol(controlPanel, 'Style', 'edit', 'String', '20', 'Position', [10, 360, 100, 20]); 
    
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
    btnZero = uicontrol(controlPanel, 'Style', 'pushbutton', 'String', 'Zero Force', 'Position', [10, 80, 100, 30]);
    
    % Close button
    btnClose = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Close', 'Position', [10, 20, 100, 30], 'BackgroundColor', 'red');
end