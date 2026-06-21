function t = plot2MUAPs(t, MUAPs_mu1, MUAPs_mu2, mu_index1, mu_index2, grid_rows, grid_cols)
%{
This function recieves two MUAPs of two MUs and plots them overlapped.
First MU in blue and the second in red.
%}

chan = size(MUAPs_mu1{1}, 1);
MUAP1 = MUAPs_mu1{mu_index1};
MUAP2 = MUAPs_mu2{mu_index2};

t.Padding = "compact";
t.TileSpacing = "compact";
t.GridSize = [grid_rows grid_cols];
ylims = [];
for i = 1:chan
    ax = nexttile(t);
    plot(ax,MUAP1(i,:),'b','LineWidth',1.5); hold on;
    plot(ax,MUAP2(i,:),'r','LineWidth',1.5); hold off;
    ax.Box = "off";
    ax.XAxis.Visible = "off";
    ax.Title.String = "Channel " + string(i);
    ylims = [ylims ax.YLim];
end
ylim_max = max(ylims);
ylim_min = min(ylims);
for i = 1:chan
    ax = nexttile(t,i);
    ax.YLim = [ylim_min ylim_max];
end

end