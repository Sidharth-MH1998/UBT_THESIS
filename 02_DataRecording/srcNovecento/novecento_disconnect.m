function novecento_disconnect(dev)
%NOVECENTO_DISCONNECT Stop streaming and close the Novecento connection.

try
    stopString = dev.ConfString;
    stopString(1) = uint8(bin2dec('00000000'));
    stopString(15) = uint8(CRC8(double(stopString), 14));
    write(dev.tcpSocket, stopString, 'uint8');
    pause(0.5);
catch
end

try
    clear dev.tcpSocket
catch
end

disp('Novecento connection closed.');

end
