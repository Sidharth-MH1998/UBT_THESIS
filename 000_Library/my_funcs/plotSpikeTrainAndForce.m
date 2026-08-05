function plotSpikeTrainAndForce

plot_spikeTrain(decomp_results(6,1).spikeTrain,2048,decomp_results(6,1).sil_all, 0.9)

% figure

hold on
t_f = (1:length(force))*2048/100;
plot(t_f, force(:,2).*3.5,'LineWidth',2)