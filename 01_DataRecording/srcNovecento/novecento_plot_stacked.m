function novecento_plot_stacked(ax, block, channelLabels, fs, firstSample, visibleWindowSec)
%NOVECENTO_PLOT_STACKED Plot raw converted traces with stacked offsets.

cla(ax);
if isempty(block)
    return;
end

plotBlock = double(block);
offset = max(max(std(plotBlock, 0, 2) * 6), 1);

xSec = ((firstSample - 1):(firstSample + size(plotBlock, 2) - 2)) / fs;

hold(ax, 'on');
for ch = 1:size(plotBlock, 1)
    plot(ax, xSec, plotBlock(ch, :) + offset * (ch - 1), 'LineWidth', 0.8);
end
hold(ax, 'off');

grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Channel');

if isinf(visibleWindowSec)
    xlim(ax, [xSec(1) max(xSec(end), 1 / fs)]);
else
    xEnd = max(xSec(end), visibleWindowSec);
    xlim(ax, [xEnd - visibleWindowSec xEnd]);
end

yticks(ax, offset * (0:(numel(channelLabels) - 1)));
yticklabels(ax, cellstr(num2str(channelLabels(:))));
ylim(ax, [-offset offset * numel(channelLabels)]);

end
