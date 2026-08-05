function serialObj = initializeArduinoStream(ard_port)
    serialObj = serialport(ard_port, 115200);
    serialObj.InputBufferSize = 8192; % 5 seconds of data aprox
    configureTerminator(serialObj, 'LF');
end