function serialObj = initializeArduinoForceStream(ard_port)
%INITIALIZEARDUINOSTREAM Open and prepare the Arduino serial connection.
%
% Checks that the requested serial port is currently available, opens the
% port at 115200 baud, configures line-feed termination, waits for the
% Arduino to finish resetting, and clears any incomplete or stale data from
% the input buffer.
%
% INPUT
%   ard_port :Serial-port name as 'COM4' or "COM4".
%
% OUTPUT
%   serialObj :Configured MATLAB serialport object used by the main acquisition loop.

    % Close an old MATLAB serialport object using this port.
    oldSerial = serialportfind("Port", ard_port);
    if ~isempty(oldSerial)
        delete(oldSerial);
        pause(0.2);
    end
    
    availablePorts = serialportlist("available");
    if ~any(strcmpi(availablePorts, ard_port))
        error('Arduino port %s is not available. Available ports: %s', ...
            ard_port, strjoin(cellstr(availablePorts), ', '));
    end

    serialObj = serialport(ard_port, 115200, 'Timeout', 2);
    configureTerminator(serialObj, "LF");
    pause(1);
    flush(serialObj, "input"); % This removes all bytes that arrived during the one-second startup pause.
    disp(['Arduino force stream connected on ', ard_port]);
end