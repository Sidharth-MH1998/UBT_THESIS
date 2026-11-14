function test_quadrant_references()
%TEST_QUADRANT_REFERENCES Edited means, padding, fixed unequal axes and PPS cursor.
signal = struct('fsamp',100,'Pulsetrain',{{zeros(2,100),zeros(1,100)}}, ...
    'Dischargetimes',{{[1 11 21],[1 6 11];[1 21 41],[]}});
edition.mean_fr = {12,24,999;6,[],999}; % Ignore padded MU columns.
rates = get_mu_reference_rates(signal,edition);
assert(isequal(rates,[12 24 6]));
edition.mean_fr{1,2} = NaN;
assert(isequal(get_mu_reference_rates(signal,edition),[12 20 6]));
assert(isequal(get_mu_reference_rates(signal),[10 20 5]));
signal.onlineMUReferenceRates = rates;
assert(isequal(get_mu_reference_rates(signal),rates));

fig = figure('Visible','off');
cleanup = onCleanup(@() delete(fig));
ax = axes(fig);
cfg = struct('quadrantXMU',1,'quadrantYMU',2, ...
    'quadrantReferenceRates',[10 20],'quadrantAxisScale',1.5, ...
    'quadrantRateWindowSec',1,'quadrantSmoothingWindows',4);
state = ispin_quadrant_feedback('init',2,2000,0.1,cfg,ax);
assert(isequal(ax.XLim,[0 15]) && isequal(ax.YLim,[0 30]));
assert(isequal(ax.PlotBoxAspectRatio,[1 1 1]) && ~state.autoAxis);
assert(max(abs(state.lowerRay.XData-[0 15])) < 1e-12);
assert(max(abs(state.lowerRay.YData-[0 30*tan(pi/6)])) < 1e-12);
assert(max(abs(state.upperRay.XData-[0 15*tan(pi/6)])) < 1e-12);
assert(isequal(state.upperRay.YData,[0 30]));
spikes = false(200,2);
spikes(20,1) = true;
spikes([30 130],2) = true;
for idx = 1:12, state = ispin_quadrant_feedback('update',state,spikes,idx*0.1); end
assert(abs(state.cursor.XData-10) < 1e-10 && abs(state.cursor.YData-20) < 1e-10);
% Even rates above the display range must not expand reference-based axes.
state = ispin_quadrant_feedback('update',state,true(200,2),1.3);
assert(isequal(ax.XLim,[0 15]) && isequal(ax.YLim,[0 30]));
exported = ispin_quadrant_feedback('export',state);
assert(isequal(exported.referenceRates,[10 20]));
cfg.quadrantXMU = 2;
cfg.quadrantYMU = 1;
state = ispin_quadrant_feedback('init',2,2000,0.1,cfg,ax);
assert(isequal(state.axisMaxima,[30 15]));
disp('I-Spin reference means, fixed axis limits, scaled boundaries and PPS coordinates passed.');
end
