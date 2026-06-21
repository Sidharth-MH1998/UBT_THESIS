function crc = CRC8(vector, len)
%CRC8 Calculate the CRC used by Novecento+ commands.

crc = 0;
index = 1;

while len > 0
    value = vector(index);

    for bit = 8:-1:1 %#ok<NASGU>
        sumBit = xor(mod(crc, 2), mod(value, 2));
        crc = floor(crc / 2);

        if sumBit > 0
            crc = bitxor(crc, 140);
        end

        value = floor(value / 2);
    end

    len = len - 1;
    index = index + 1;
end

end
