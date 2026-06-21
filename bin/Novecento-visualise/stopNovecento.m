% stopNovecento.m
% Run this script anytime to safely stop the Novecento+ data stream
% and close the TCP connection.
%
% Use cases:
%   1. After Ctrl+C interrupted the main script
%   2. If the device seems stuck streaming
%   3. Before starting a new session
%
% Usage:
%   >> stopNovecento

% Check if socket exists in workspace
if ~exist('tcpScoket', 'var')
    disp('No active TCP connection found in workspace.')
    disp('If device is still streaming, power cycle the Novecento+.')
    return
end

% Check if socket is still valid
try
    % Send stop command
    ConfString(1)  = bin2dec('00000000');    % Clear start bit → stop streaming
    ConfString(15) = CRC8(ConfString, 14);   % Recalculate CRC
    write(tcpScoket, ConfString, 'uint8');   % Send stop to device
    disp('Stop command sent to Novecento+.')
    
    pause(1)  % Give device time to process stop command
    
    % Close and destroy socket
    clear tcpScoket
    disp('TCP connection closed.')
    disp('Safe to start a new session.')

catch e
    % Socket exists but may already be broken
    disp('Warning: Could not send stop command (connection may already be broken).')
    disp(e.message)
    clear tcpScoket
    disp('TCP socket cleared.')
    disp('Power cycle the Novecento+ before starting a new session.')
end
