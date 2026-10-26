function test_emg_preview()
%TEST_EMG_PREVIEW Check selected electrodes with a permuted channel mapping.
app = OnlineDecompositionApp();
appCleanup = onCleanup(@() delete(app));
app.Figure.Visible = 'off';
cfg = app.getConfig();
cfg.fs = 2000;
cfg.calibChannels = [65:128 1:64];
cfg.emgPreviewChannels = [1 66];
cfg.quadrantXMU = 2;
cfg.quadrantYMU = 5;
fig = uifigure('Visible','off');
figureCleanup = onCleanup(@() delete(fig));
display = OnlineAppDashboard(fig);
displayCleanup = onCleanup(@() delete(display));
display.initialize(cfg,{'G1 MU1','G1 MU2','G1 MU3','G2 MU1','G2 MU2','G2 MU3'});
n = 256;
wave = sin(2*pi*(0:n-1)/n);
emg = cfg.calibChannels(:)+wave;
spikes = false(n,6);
for mu = 1:6, spikes(10*mu+1,mu) = true; end
frame = struct('time',n/cfg.fs,'sampleCursor',n, ...
    'pulse',zeros(6,n),'spikes',spikes,'emg',emg, ...
    'force',struct('data',zeros(0,3),'sessionTime',zeros(0,1)));
display.update(frame);
ax = findall(fig,'Tag','liveEMGAxes');
assert(isequal(cellstr(ax.YTickLabel),{'G1 Ch1';'G2 Ch2'}));
traces = findall(ax,'Type','line');
assert(numel(traces) == 2);
[~,order] = sort(arrayfun(@(trace) mean(trace.YData),traces));
stride = ceil(cfg.fs/500);
selected = [1;66]+wave(1:stride:end);
offset = max(max(std(selected,0,2)*6),1);
assert(max(abs(traces(order(1)).YData-selected(1,:))) < 1e-10);
assert(max(abs(traces(order(2)).YData-selected(2,:)-offset)) < 1e-10);
assert(max(abs(traces(order(1)).XData-(0:stride:n-1)/cfg.fs)) < 1e-10);
assert(isempty(findall(groot,'Tag','OnlineAppRasterWindow')));
button = findall(fig,'Tag','openQuadrant');
callback = button.ButtonPushedFcn;
callback(button,[]);
popup = findall(groot,'Tag','OnlineAppQuadrantWindow');
raster = findall(popup,'Tag','quadrantSelectedMURaster');
assert(isequal(cellstr(raster.YTickLabel),{'X: G1 MU2';'Y: G2 MU2'}));
traces = findall(raster,'Type','line');
assert(numel(traces) == 2);
for idx = 1:2
    row = traces(idx).YData;
    assert(isscalar(row));
    if row == 1, expected = 20/cfg.fs; else, expected = 50/cfg.fs; end
    assert(isscalar(traces(idx).XData) && abs(traces(idx).XData-expected) < 1e-12);
end
disp('Selected EMG electrode mapping and raw stacked preview checks passed.');
end
