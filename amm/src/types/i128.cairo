use traits::{Into, TryInto, Rem};
use integer::{U128Mul, U128Div, U128Rem, u128_try_from_felt252, u128_overflowing_sub};
use option::OptionTrait;
use result::ResultTrait;
use hash::LegacyHash;

////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Copy, Drop, Serde, storage_access::StorageAccess)]
struct i128 {
    val: u128,
    sign: bool
}

////////////////////////////////
// METHODS
////////////////////////////////

trait I128Trait {
    fn new(val: u128, sign: bool) -> i128;
    fn one() -> i128;
}

impl I128Zeroable of Zeroable<i128> {
    #[inline(always)]
    fn zero() -> i128 {
        I128Trait::new(0_u128, false)
    }

    #[inline(always)]
    fn is_zero(self: i128) -> bool {
        self.val == 0_u128
    }

    #[inline(always)]
    fn is_non_zero(self: i128) -> bool {
        self.val != 0_u128
    }
}

impl I128Impl of I128Trait {
    #[inline(always)]
    fn new(val: u128, sign: bool) -> i128 {
        i128 { val, sign: if val == 0 {
            false
        } else {
            sign
        } }
    }

    #[inline(always)]
    fn one() -> i128 {
        I128Trait::new(1_u128, false)
    }
}

impl I128IntoFelt252 of Into<i128, felt252> {
    #[inline(always)]
    fn into(self: i128) -> felt252 {
        let mag_felt: felt252 = self.val.into();
        if self.sign {
            mag_felt * -1
        } else {
            mag_felt
        }
    }
}

impl Felt252TryIntoI128 of TryInto<felt252, i128> {
    #[inline(always)]
    fn try_into(self: felt252) -> Option<i128> {
        let abs: u128 = self.try_into().unwrap();
        Option::Some(I128Trait::new(abs, false))
    }
}

impl I128PartialOrd of PartialOrd<i128> {
    #[inline(always)]
    fn le(lhs: i128, rhs: i128) -> bool {
        if rhs.sign != lhs.sign {
            lhs.sign
        } else {
            if lhs.sign {
                lhs.val >= rhs.val
            } else {
                lhs.val <= rhs.val
            }
        }
    }
    #[inline(always)]
    fn ge(lhs: i128, rhs: i128) -> bool {
        if lhs.sign != rhs.sign {
            !lhs.sign
        } else {
            if lhs.sign {
                lhs.val <= rhs.val
            } else {
                lhs.val >= rhs.val
            }
        }
    }
    #[inline(always)]
    fn lt(lhs: i128, rhs: i128) -> bool {
        if lhs.sign != rhs.sign {
            lhs.sign
        } else {
            if lhs.sign {
                lhs.val > rhs.val
            } else {
                lhs.val < rhs.val
            }
        }
    }
    #[inline(always)]
    fn gt(lhs: i128, rhs: i128) -> bool {
        if lhs.sign != rhs.sign {
            !lhs.sign
        } else {
            if lhs.sign {
                lhs.val < rhs.val
            } else {
                lhs.val > rhs.val
            }
        }
    }
}

impl I128PartialEq of PartialEq<i128> {
    #[inline(always)]
    fn eq(lhs: @i128, rhs: @i128) -> bool {
        lhs.sign == rhs.sign && lhs.val == rhs.val
    }
    #[inline(always)]
    fn ne(lhs: @i128, rhs: @i128) -> bool {
        lhs.sign != rhs.sign || lhs.val != rhs.val
    }
}

impl LegacyHashI128 of LegacyHash<i128> {
    #[inline(always)]
    fn hash(state: felt252, value: i128) -> felt252 {
        LegacyHash::<felt252>::hash(state, value.into())
    }
}

impl I128Add of Add<i128> {
    #[inline(always)]
    fn add(lhs: i128, rhs: i128) -> i128 {
        if lhs.sign == rhs.sign {
            i128 { val: lhs.val + rhs.val, sign: lhs.sign }
        } else if lhs.sign {
            if lhs.val > rhs.val {
                i128 { val: lhs.val - rhs.val, sign: true }
            } else {
                i128 { val: rhs.val - lhs.val, sign: false }
            }
        } else {
            if lhs.val >= rhs.val {
                i128 { val: lhs.val - rhs.val, sign: false }
            } else {
                i128 { val: rhs.val - lhs.val, sign: true }
            }
        }
    }
}

impl I128Sub of Sub<i128> {
    #[inline(always)]
    fn sub(lhs: i128, rhs: i128) -> i128 {
        if lhs.sign == rhs.sign {
            if lhs.val > rhs.val {
                i128 { val: lhs.val - rhs.val, sign: lhs.sign }
            } else if lhs.val < rhs.val {
                i128 { val: rhs.val - lhs.val, sign: !lhs.sign }
            } else {
                i128 { val: 0, sign: false }
            }
        } else if lhs.sign {
            i128 { val: lhs.val + rhs.val, sign: true }
        } else {
            i128 { val: lhs.val + rhs.val, sign: false }
        }
    }
}

impl I128Mul of Mul<i128> {
    #[inline(always)]
    fn mul(lhs: i128, rhs: i128) -> i128 {
        let res_sign: bool = lhs.sign ^ rhs.sign;
        let mag: u128 = U128Mul::mul(lhs.val, rhs.val);
        I128Trait::new(mag, res_sign)
    }
}

impl I128Div of Div<i128> {
    #[inline(always)]
    fn div(lhs: i128, rhs: i128) -> i128 {
        let res_sign = lhs.sign ^ rhs.sign;
        let mag: u128 = U128Div::div(lhs.val, rhs.val);
        I128Trait::new(mag, res_sign)
    }
}

impl I128Rem of Rem<i128> {
    #[inline(always)]
    fn rem(lhs: i128, rhs: i128) -> i128 {
        let res_sign = lhs.sign;
        let mag: u128 = U128Rem::rem(lhs.val, rhs.val);
        I128Trait::new(mag, res_sign)
    }
}

impl I128AddEq of AddEq<i128> {
    #[inline(always)]
    fn add_eq(ref self: i128, other: i128) {
        self = I128Add::add(self, other)
    }
}

impl I128SubEq of SubEq<i128> {
    #[inline(always)]
    fn sub_eq(ref self: i128, other: i128) {
        self = I128Sub::sub(self, other)
    }
}
