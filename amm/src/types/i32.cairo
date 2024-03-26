////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Copy, Drop, Serde, storage_access::StorageAccess)]
pub struct i32 {
    pub val: u32,
    pub sign: bool
}

////////////////////////////////
// METHODS
////////////////////////////////

pub trait I32Trait {
    fn new(val: u32, sign: bool) -> i32;
    fn one() -> i32;
}

impl I32Impl of I32Trait {
    #[inline(always)]
    fn new(val: u32, sign: bool) -> i32 {
        i32 { val, sign: if val == 0 {
            false
        } else {
            sign
        } }
    }

    #[inline(always)]
    fn one() -> i32 {
        I32Trait::new(1_u32, false)
    }
}

impl I32PartialOrd of PartialOrd<i32> {
    #[inline(always)]
    fn le(lhs: i32, rhs: i32) -> bool {
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
    fn ge(lhs: i32, rhs: i32) -> bool {
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
    fn lt(lhs: i32, rhs: i32) -> bool {
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
    fn gt(lhs: i32, rhs: i32) -> bool {
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

impl I32PartialEq of PartialEq<i32> {
    #[inline(always)]
    fn eq(lhs: @i32, rhs: @i32) -> bool {
        lhs.sign == rhs.sign && lhs.val == rhs.val
    }
    #[inline(always)]
    fn ne(lhs: @i32, rhs: @i32) -> bool {
        lhs.sign != rhs.sign || lhs.val != rhs.val
    }
}

impl I32Add of Add<i32> {
    #[inline(always)]
    fn add(lhs: i32, rhs: i32) -> i32 {
        if lhs.sign == rhs.sign {
            i32 { val: lhs.val + rhs.val, sign: lhs.sign }
        } else if lhs.sign {
            if lhs.val > rhs.val {
                i32 { val: lhs.val - rhs.val, sign: true }
            } else {
                i32 { val: rhs.val - lhs.val, sign: false }
            }
        } else {
            if lhs.val >= rhs.val {
                i32 { val: lhs.val - rhs.val, sign: false }
            } else {
                i32 { val: rhs.val - lhs.val, sign: true }
            }
        }
    }
}

impl I32Sub of Sub<i32> {
    #[inline(always)]
    fn sub(lhs: i32, rhs: i32) -> i32 {
        if lhs.sign == rhs.sign {
            if lhs.val > rhs.val {
                i32 { val: lhs.val - rhs.val, sign: lhs.sign }
            } else if lhs.val < rhs.val {
                i32 { val: rhs.val - lhs.val, sign: !lhs.sign }
            } else {
                i32 { val: 0, sign: false }
            }
        } else if lhs.sign {
            i32 { val: lhs.val + rhs.val, sign: true }
        } else {
            i32 { val: lhs.val + rhs.val, sign: false }
        }
    }
}

impl I32Mul of Mul<i32> {
    #[inline(always)]
    fn mul(lhs: i32, rhs: i32) -> i32 {
        let res_sign: bool = lhs.sign ^ rhs.sign;
        let mag: u32 = lhs.val * rhs.val;
        I32Trait::new(mag, res_sign)
    }
}

impl I32Div of Div<i32> {
    #[inline(always)]
    fn div(lhs: i32, rhs: i32) -> i32 {
        let res_sign = lhs.sign ^ rhs.sign;
        let mag: u32 = lhs.val / rhs.val;
        I32Trait::new(mag, res_sign)
    }
}

impl I32Rem of Rem<i32> {
    #[inline(always)]
    fn rem(lhs: i32, rhs: i32) -> i32 {
        let res_sign = lhs.sign;
        let mag: u32 = lhs.val % rhs.val;
        I32Trait::new(mag, res_sign)
    }
}

impl I32AddEq of AddEq<i32> {
    #[inline(always)]
    fn add_eq(ref self: i32, other: i32) {
        self = I32Add::add(self, other)
    }
}

impl I32SubEq of SubEq<i32> {
    #[inline(always)]
    fn sub_eq(ref self: i32, other: i32) {
        self = I32Sub::sub(self, other)
    }
}
