function t_force = getForceTimings_Hyser(force,digit,force_fs)

%{
    Get timings to divide the force signal on Hyser 1 DoF dataset into 6 stages: 
    
    Stage 1: increasing extension - first (positive values +)
    Stage 2: decreasing extension - first (positive values +)
    Stage 3: increasing flexion (negative values +)
    Stage 4: increasing flexion (negative values +)
    Stage 5: increasing flexion - second (positive values +)
    Stage 6: increasing flexion - second (positive values +)

    X. Jiang et al., "Open Access Dataset, Toolbox and Benchmark Processing Results of 
    High-Density Surface Electromyogram Recordings," in IEEE Transactions on Neural Systems and Rehabilitation Engineering,
    vol. 29, pp. 1035-1046, 2021, doi: 10.1109/TNSRE.2021.3082551.

    @author: Renato Mio
    Created: 03.11.2023

    INPUT:
    force: force time series
    digit: analysed digit
    force_fs: sampling frequency of the force signal

    OUTPUT:
    t_force: times to divide the 6 stages (1x7 double)

%}

% Low-pass signal
sig = force(:,digit);
fpass = 5; % Hz
y = lowpass(sig,fpass,force_fs);
% This creates the standard force trace (triangular signal) that subjects had to follow
f_trace = force_trace();

% We find the delay between the signals
dd = finddelay(y,f_trace);

% figure
% plot(f_trace)
% hold on 
% plot(y)

% The new timings for segmenting stages, in samples:
t_force = [500 750 1000 1250 1500 1750 2000] + dd;

