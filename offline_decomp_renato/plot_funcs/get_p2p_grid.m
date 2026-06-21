function p2p_grid = get_p2p_grid(MUAP_all, mu, gridSize)

p2ps = peak2peak(MUAP_all{mu},2);
p2p_grid = reshape(p2ps, gridSize(2),gridSize(1))';