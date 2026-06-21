function f_trace = force_trace()

% This functions generates a triangular force trace as the one in paper
% X. Jiang et al., "Open Access Dataset, Toolbox and Benchmark Processing Results of 
% High-Density Surface Electromyogram Recordings," in IEEE Transactions on Neural Systems and Rehabilitation Engineering,
% vol. 29, pp. 1035-1046, 2021, doi: 10.1109/TNSRE.2021.3082551.
% 
% @author: Renato Mio

step = 0.01;
t0 = step:step:5;
t1 = 5+step:step:7.5;
t2 = 7.5+step:step:12.5;
t3 = 12.5+step:step:17.5;
t4 = 17.5+step:step:20;
t5 = 20+step:step:25;

y0 = zeros(size(t0));
y1 = -0.6+0.3.*t1/2.5;
y2 = 1.2-0.3*t2/2.5;
y3 = -1.8+0.3.*t3/2.5;
y4 = 2.4-0.3*t4/2.5;
y5 = zeros(size(t5));

t = [t0 t1 t2 t3 t4 t5];

f_trace = [y0 y1 y2 y3 y4 y5];

% figure
% plot(t,f_trace)
