function [fig, ax_f, ax_emg, btnClose, btnZero, btnRecord, btnRecordTracking, forceChanDropdown, tWaitBox, tSlopeBox, tPlateauBox, forceTargetBox] = setupFigure_v5(numForceChan)
    % Create figure
    fig = figure('Name', 'Force and EMG Streaming', 'NumberTitle', 'off', 'Position', [20, 125, 2500, 1080]);

    % Create force plot axes
    ax_f = subplot(2, 1, 1);
    set(ax_f, 'Position', [0.05, 0.55, 0.75, 0.35]); % This shrinks the axes horizontally
    title(ax_f, 'Force Data');
    xlabel(ax_f, 'Time (s)');
    ylabel(ax_f, 'Force (%)');
    grid(ax_f, 'on');  % Enable grid lines on force plot

    % Create EMG plot axes
    ax_emg = subplot(2, 1, 2);
    set(ax_emg, 'Position', [0.05, 0.1, 0.75, 0.35]);
    title(ax_emg, 'EMG Data');
    xlabel(ax_emg, 'Time (s)');
    ylabel(ax_emg, 'Amplitude (uV)');
    grid(ax_emg, 'on');  % Enable grid lines on EMG plot

    % Create a control panel for buttons and inputs
    controlPanel = uipanel('Title', 'Controls', 'Position', [0.81, 0.1, 0.18, 0.85], 'Units', 'normalized');

    % Create an axes object for the image
    imageAxes = axes('Parent', controlPanel, 'Position', [0.01, 0.65, 0.9, 0.3], 'Units', 'normalized');
    
    % Load and display the image
    if exist("ForceTrace.png", 'file')
        [img, ~, alpha] = imread("ForceTrace.png");
        ftraceImg = imshow(img, 'Parent', imageAxes);
        ftraceImg.AlphaData = alpha;
    else
        text(0.5, 0.5, 'Image not found', 'Parent', imageAxes, 'HorizontalAlignment', 'center');
    end


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