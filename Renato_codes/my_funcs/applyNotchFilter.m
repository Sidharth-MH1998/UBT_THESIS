% Function to apply the notch filter to multi-channel EMG data
function filteredEMG = applyNotchFilter(emgSignal, fsamp, filterType)
    [numRows, numCols] = size(emgSignal);
    filteredEMG = zeros(size(emgSignal));
    
    for i = 1:numRows
        if strcmpi(filterType, 'butterworth')
            filteredEMG(i,:) = butterworthNotchCascade(emgSignal(i,:), fsamp);
        elseif strcmpi(filterType, 'chebyshev')
            filteredEMG(i,:) = chebyshevNotchCascade(emgSignal(i,:), fsamp);
        else
            error('Invalid filter type. Choose "butterworth" or "chebyshev".');
        end
    end
end

function filteredsignal = butterworthNotchCascade(signal, fsamp)
    % Apply Butterworth notch filters at 50 Hz and harmonics up to 450 Hz
    notchFreqs = 50:50:450;
    bandwidth = 4;  % Bandwidth of 4 Hz for each notch
    
    filteredsignal = signal;
    for freq = notchFreqs
        [b, a] = butter(2, [freq-bandwidth/2, freq+bandwidth/2] / (fsamp/2), 'stop');
        filteredsignal = filtfilt(b, a, filteredsignal);
    end
end

function filteredsignal = chebyshevNotchCascade(signal, fsamp)
    % Apply Chebyshev notch filters at 50 Hz and harmonics up to 450 Hz
    notchFreqs = 50:50:450;
    bandwidth = 4;  % Bandwidth of 4 Hz for each notch
    
    filteredsignal = signal;
    for freq = notchFreqs
        [b, a] = cheby2(4, 20, [freq-bandwidth/2, freq+bandwidth/2] / (fsamp/2), 'stop');
        filteredsignal = filtfilt(b, a, filteredsignal);
    end
end


