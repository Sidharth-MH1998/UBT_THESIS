function [fig, ax_f, ax_emg, btnClose, btnZero, btnRecord] = setupFigure_v4(numForceChan)
    % Create figure
    fig = figure('Name', 'Force and EMG Streaming', 'NumberTitle', 'off', 'Position', [200, 400, 1400, 800]);
    
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
    
    % Create a control panel for buttons
    controlPanel = uipanel('Title', 'Controls', 'Position', [0.81, 0.1, 0.18, 0.85]);

    % Close button
    btnClose = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Close', 'Position', [10, 300, 100, 30], 'BackgroundColor', 'red');

    % Zero Force Button
    btnZero = uicontrol(controlPanel, 'Style', 'pushbutton', 'String', 'Zero Force', 'Position', [10, 260, 100, 30]);

    % Record Button
    btnRecord = uicontrol(controlPanel, 'Style', 'togglebutton', 'String', 'Record', 'Position', [10, 220, 100, 30], 'BackgroundColor', 'green');
end