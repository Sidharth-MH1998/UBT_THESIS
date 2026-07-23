function cleanupResources(serialObj, tcpSocket, toggleEMG)
    % Close the serial object
    if ~isempty(serialObj) && isvalid(serialObj)
        fclose(serialObj);
        delete(serialObj);
    end

    % Close the TCP socket (if EMG is enabled)
    if toggleEMG && ~isempty(tcpSocket)
        fclose(tcpSocket);
        delete(tcpSocket);
    end
end