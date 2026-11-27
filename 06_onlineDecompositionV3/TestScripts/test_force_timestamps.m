function test_force_timestamps()
%TEST_FORCE_TIMESTAMPS Buffered reads retain sensor intervals, not read timing.
addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))),'OnlineDecomposeSrc'));
[first,state] = map_arduino_force_time((10000:20:10080)',0.1,[]);
assert(max(abs(diff(first)-0.02))<1e-10);
assert(abs(first(end)-0.1)<1e-10);
% A late read must not move those samples to the late host receipt time.
[next,state] = map_arduino_force_time((10100:20:10180)',0.9,state);
assert(abs(next(1)-first(end)-0.02)<1e-10);
assert(max(abs(diff(next)-0.02))<1e-10);
[empty,unchanged] = map_arduino_force_time([],1,state);
assert(isempty(empty) && isequal(unchanged,state));
% Unsigned Arduino millis rollover preserves continuity.
[before,state] = map_arduino_force_time(2^32-10,1,[]);
[after,~] = map_arduino_force_time(10,1.2,state);
assert(abs(after-before-0.02)<1e-10);
% Actual slower sensor intervals remain visible rather than inventing 50 Hz.
[slow,~] = map_arduino_force_time([1000;1100;1200],0.3,[]);
assert(max(abs(diff(slow)-0.1))<1e-10);
disp('Arduino buffered force timing checks passed.');
end
