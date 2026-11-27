function [times,state] = map_arduino_force_time(ticks,receiptTime,state)
%MAP_ARDUINO_FORCE_TIME Preserve Arduino millis spacing across buffered reads.
% Anchor the first batch to the session clock once; later batches retain the
% device intervals even when MATLAB reads them late. This is approximate
% clock alignment, not hardware synchronization with EMG.
if nargin < 3 || isempty(state)
    state = struct('lastTick',[],'wrap',0,'originTick',[],'offset',[]);
end
ticks = double(ticks(:));
times = zeros(size(ticks));
if isempty(ticks), return; end
for k = 1:numel(ticks)
    if ~isempty(state.lastTick) && ticks(k)-state.lastTick < -2^31
        state.wrap = state.wrap+2^32;
    end
    times(k) = ticks(k)+state.wrap;
    state.lastTick = ticks(k);
end
if isempty(state.offset)
    % Avoid a negative initial session time if the first buffered batch is long.
    state.originTick = times(1);
    state.offset = max(0,receiptTime-(times(end)-times(1))/1000);
end
times = (times-state.originTick)/1000+state.offset;
end
