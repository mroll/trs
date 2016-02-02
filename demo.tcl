## Test single reductions
#

source trs.tcl


proc test { input correct } {
    set result [reduce $input $::rules]
    if { ! [string equal $result $correct] } {
        puts "Failed: $input"
        puts "Expected: $correct"
        puts "Got: $result"
    } else {
        puts "Succeeded: $input -> $result"
    }
}

#---------------------#
# Constant operations #
#---------------------#

# add constants
test {add 4 5} 9

# multiply constants
test {mul 4 5} 20

# subtract constants
test {sub 4 5} -1

# take a constant to a power
test {pow 4 5} 1024.0

#---------------------#
# Variable operations #
#---------------------#

# divide var by itself
test {div z z} 1

# multiply var by itself
test {mul z z} {pow z 2}

# multiply variable powers of same base
test {mul {pow z 4} {pow z 5}} {pow z 9}

#-----------------------#
# Derivative operations #
#-----------------------#

# derivative of sine
test {diff {sin y} y} {cos y}

# derivative of cosine
test {diff {cos y} y} {mul -1 {sin y}}

# derivative of a var to a constant power
test {diff {pow y 4} y} {mul 4 {pow y 3}}

# derivative of a sum of atoms
test {diff {add 7 x} x} {add {diff 7 x} {diff x x}}

# derivative of var wrt itself
test {diff u u} 1

# product rule
test {diff {mul {add 7 x} {sub y z}} x} {add {mul {diff {add 7 x} x} {sub y z}} {mul {add 7 x} {diff {sub y z} x}}}

# derivative of a constant
test {diff 17 x} {0}

#---------------------#
# Identity operations #
#---------------------#

# multiplicative identity on terms
test {mul {add 7 x} 1} {{add 7 x}}

# multiplicative identity on atoms
test {mul h 1} {h}

# identity of var to the first power
test {pow z 1} {z}

# additive identity on terms
test {add {add 7 x} 0} {{add 7 x}}

# additive identity on atoms
test {add h 0} {h}

# subtractive identity on terms
test {sub {add 7 x} 0} {{add 7 x}}

# subtractive identity on atoms
test {sub h 0} {h}

#------------------------------#
# Multiplicative associativity #
#------------------------------#

# multiply outer constants of terms
test {mul 4 {mul 5 {add 7 x}}} {mul 20 {add 7 x}}

# multiply outer constants of atoms
test {mul 4 {mul 5 g}} {mul 20 g}

# multiply outer vars if they are the same
test {mul x {mul x {add 7 x}}} {mul {pow x 2} {add 7 x}}

# increase powers of same var multiplied together
test {mul y {pow y 4}} {pow y 5}
