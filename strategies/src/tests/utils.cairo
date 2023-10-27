fn to_e18(x: u256) -> u256 {
    x * 1000000000000000000
}

fn to_e28(x: u256) -> u256 {
    x * 10000000000000000000000000000
}

fn approx_eq(a: u256, b: u256, threshold: u256) -> bool {
    if a > b {
        a - b < threshold
    } else {
        b - a < threshold
    }
}
