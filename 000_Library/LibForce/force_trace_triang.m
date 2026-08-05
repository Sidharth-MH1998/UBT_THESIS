function [t, f_trace] = force_trace_triang(fs_force)
% Generates a triangular force trace
step = 1/fs_force;
t0 = step:step:5;
t1 = 5+step:step:7.5;
t2 = 7.5+step:step:12.5;
t3 = 12.5+step:step:17.5;
t4 = 17.5+step:step:20;
t5 = 20+step:step:25;

y0 = zeros(size(t0));
y1 = -0.6 + 0.3 .* t1 / 2.5;
y2 = 1.2 - 0.3 * t2 / 2.5;
y3 = -1.8 + 0.3 .* t3 / 2.5;
y4 = 2.4 - 0.3 * t4 / 2.5;
y5 = zeros(size(t5));

t = [t0 t1 t2 t3 t4 t5];
f_trace = [y0 y1 y2 y3 y4 y5].*100;
end
