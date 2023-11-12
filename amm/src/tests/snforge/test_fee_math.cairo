use integer::BoundedU256;
use amm::libraries::math::fee_math::{gross_to_net, net_to_fee};

use snforge_std::PrintTrait;

// Converts gross amount to net, then net to fee, and checks net plus fee never exceeds gross.
#[test]
fn test_gross_net_fee_invariant(gross_amount: u256, fee_rate: u16) {
    if fee_rate > 10000 { return; }

    let net_amount = gross_to_net(gross_amount, fee_rate);
    let fee_amount = net_to_fee(net_amount, fee_rate);
    
    assert(net_amount + fee_amount <= gross_amount, 'Net + fee > gross');
}