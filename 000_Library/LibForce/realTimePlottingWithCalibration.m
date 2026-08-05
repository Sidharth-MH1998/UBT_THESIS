function realTimePlottingWithCalibration(port)
    % Open the serial port
    % s = serialport("/dev/cu.usbmodem1301", 115200);
    s = serialport(port, 115200);
    configureTerminator(s, "LF");
    flush(s);

    % Create a figure with "Close", "Zero", and "Calibrate" buttons
    fig = figure('Name', 'Real-Time Data Plot', 'CloseRequestFcn', @closeFigure);
    uicontrol('Style', 'pushbutton', 'String', 'Close', 'Position', [20 20 60 20], 'Callback', @closeFigure);
    uicontrol('Style', 'pushbutton', 'String', 'Zero', 'Position', [100 20 60 20], 'Callback', @zeroSensors);
    
    % Textboxes and calibrate buttons
    uicontrol('Style', 'text', 'Position', [200 40 100 20], 'String', 'Calibration Force 1 (g):');
    calibrateBox1 = uicontrol('Style', 'edit', 'Position', [310 40 100 20], 'String', '');
    uicontrol('Style', 'pushbutton', 'String', 'Calibrate 1', 'Position', [420 40 80 20], 'Callback', @(~, ~) calibrateSensor(1));

    uicontrol('Style', 'text', 'Position', [200 10 100 20], 'String', 'Calibration Force 2 (g):');
    calibrateBox2 = uicontrol('Style', 'edit', 'Position', [310 10 100 20], 'String', '');
    uicontrol('Style', 'pushbutton', 'String', 'Calibrate 2', 'Position', [420 10 80 20], 'Callback', @(~, ~) calibrateSensor(2));
    
    % Variables to store data
    force1 = [];
    force2 = [];
    time = [];
    zeroOffset = [0, 0]; % Zero offsets for both sensors
    calibrationFactor = [1, 1]; % Calibration factors for both sensors
    
    % Initialize plot
    h1 = plot(NaN, NaN, 'b');
    hold on;
    h2 = plot(NaN, NaN, 'r');
    xlabel('Time (s)');
    ylabel('Force (N)');
    legend('Force 1', 'Force 2');
    drawnow;
    
    % Timer to track elapsed time
    startTime = tic;
    
    % Continuously read data
    while ishandle(fig)
        % Read a line of data as a string
        str = readline(s);
        
        % Split the string into individual numbers using comma as the delimiter
        strData = split(str, ',');
        
        % Convert strings to numbers
        numData = str2double(strData);
        
        % Store in data arrays
        if numel(numData) == 2
            elapsedTime = toc(startTime);
            time(end + 1) = elapsedTime; %#ok<*AGROW>
            % Apply zeroing and calibration
            force1(end + 1) = (numData(1) - zeroOffset(1)) * calibrationFactor(1);
            force2(end + 1) = (numData(2) - zeroOffset(2)) * calibrationFactor(2);
            
            % Update plots
            set(h1, 'XData', time, 'YData', force1);
            set(h2, 'XData', time, 'YData', force2);
            
            % Adjust x-axis to show only the last 20 seconds of data
            if elapsedTime > 20
                xlim([elapsedTime - 20, elapsedTime]);
            else
                xlim([0, 20]);
            end
            
            drawnow;
        end
        
        pause(0.01); % Small pause to control the loop speed
    end
    
    % Close the serial port
    clear s;
    
    % Callback function to close the figure
    function closeFigure(~, ~)
        delete(fig);
    end

    % Callback function to zero the sensors
    function zeroSensors(~, ~)
        if ~isempty(force1)
            zeroOffset(1) = force1(end);
        end
        if ~isempty(force2)
            zeroOffset(2) = force2(end);
        end
    end

    % Callback function to calibrate the sensors
    function calibrateSensor(sensorIndex)
        if sensorIndex == 1
            calibrationValue = str2double(calibrateBox1.String);
        elseif sensorIndex == 2
            calibrationValue = str2double(calibrateBox2.String);
        end
        
        % Convert grams to Newtons (1 g = 0.00980665 N)
        calibrationValue = calibrationValue * 0.00980665;
        
        if ~isempty(calibrationValue) && calibrationValue > 0
            % Update calibration factor
            if sensorIndex == 1
                calibrationFactor(1) = calibrationValue / (force1(end) - zeroOffset(1));
            elseif sensorIndex == 2
                calibrationFactor(2) = calibrationValue / (force2(end) - zeroOffset(2));
            end
        end
    end
end
