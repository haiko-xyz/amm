use amm::libraries::math::bit_math::msb;

#[test]
#[available_gas(2000000000)]
fn test_msb_cases() {
    let mut i = 0x8000000000000000000000000000000000000000000000000000000000000000;
    let mut pos = 255;
    loop {
        if pos == 0 {
            break ();
        }
        assert(msb(i) == pos, 'msb');
        i /= 2;
        pos -= 1;
    };
    assert(msb(0) == 0, 'msb(0)');
}
