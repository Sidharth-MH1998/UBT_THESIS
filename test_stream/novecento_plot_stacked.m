function novecento_plot_stacked(ax, block, channelLabels, fs, firstSample, visibleWindowSec)
%NOVECENTO_PLOT_STACKED Plot normalized traces around channel-number y values.

cla(ax);
if isempty(block)
    return;
end

plotBlock = double(block);
plotBlock = plotBlock - median(plotBlock, 2);
channelScale = std(plotBlock, 0, 2);
channelScale(channelScale < eps) = 1;
plotBlock = 0.35 * plotBlock ./ channelScale;
plotBlock = max(min(plotBlock, 0.45), -0.45);

xSec = ((firstSample - 1):(firstSample + size(plotBlock, 2) - 2)) / fs;

hold(ax, 'on');
for ch = 1:size(plotBlock, 1)
    plot(ax, xSec, plotBlock(ch, :) + channelLabels(ch), 'LineWidth', 0.8);
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

yticks(ax, channelLabels);
ylim(ax, [min(channelLabels) - 1 max(channelLabels) + 1]);

end
