function updateLiveEMGPlot(ax_emg, emgData, currentEMGIndex,fs_emg, displayTime, previewRows, emgChannelLabels, displayDecimation)

    if currentEMGIndex < 1
        return;
    end

    previewRows = previewRows(previewRows >= 1 & previewRows <= size(emgData, 1));
    if isempty(previewRows)
        return;
    end
    nVisible = min(currentEMGIndex, round(displayTime * fs_emg));
    firstSample = currentEMGIndex - nVisible + 1;
    displayIndices = firstSample:displayDecimation:currentEMGIndex;
    visibleEMG = emgData(previewRows, displayIndices);
    labels = emgChannelLabels(previewRows);
    displayFs = fs_emg / displayDecimation;
    firstDisplaySample = (displayIndices(1) - 1) / displayDecimation + 1;

    updateStackedEMGPreview(ax_emg, visibleEMG, labels, displayFs, firstDisplaySample, displayTime);
end

function updateStackedEMGPreview(ax, block, channelLabels, fs,firstSample, visibleWindowSec)
% Smooth local EMG preview used only by StreamForceAndEmgV2.
    plotBlock = double(block);
    nChannels = size(plotBlock, 1);
    offset = max(max(std(plotBlock, 0, 2) * 6), 1);
    xSec = ((firstSample - 1):(firstSample + size(plotBlock, 2) - 2)) / fs;

    plotState = getappdata(ax, 'StreamForceEMGPlotState');
    needsInitialization = isempty(plotState) || ...
        ~isfield(plotState, 'lines') || ...
        numel(plotState.lines) ~= nChannels || ...
        ~all(isgraphics(plotState.lines));

    if needsInitialization
        hold(ax, 'on');
        plotState.lines = gobjects(nChannels, 1);
        for ch = 1:nChannels
            plotState.lines(ch) = plot(ax, nan, nan, 'LineWidth', 0.8);
        end
        hold(ax, 'off');
        setappdata(ax, 'StreamForceEMGPlotState', plotState);
    end

    for ch = 1:nChannels
        set(plotState.lines(ch), 'XData', xSec, ...
            'YData', plotBlock(ch,:) + offset * (ch - 1));
    end

    xEnd = max(xSec(end), visibleWindowSec);
    xlim(ax, [xEnd - visibleWindowSec xEnd]);
    yticks(ax, offset * (0:(nChannels - 1)));
    yticklabels(ax, cellstr(num2str(channelLabels(:))));
    ylim(ax, [-offset offset * nChannels]);
end
