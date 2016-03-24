#!/usr/local/bin/tclsh8.6
#

source expression.tcl
source rewriter.tcl


namespace eval evaluate {
    set binops { add + sub - mul * div / }
    foreach { name symb } $binops {
        proc $name { t1 t2 } [subst -nocommands { join [list [eval \$t1] [eval \$t2]] " $symb " }]
    }

    proc usub { t } {
        if { [nums-only? $t] } { expr { -$t }
        } else { return "-$t" }
    }

    proc pow  { base power } { return "[eval $base]**[eval $power]" }
    proc cos  { exp        } { return "cos([eval $exp])"            }
    proc sin  { exp        } { return "sin([eval $exp])"            }
    proc diff { exp var    } { return "diff([eval $exp], $var)"     }

    proc call { args } { {*}$args }

    proc eval { term } {
        # make sure term is not a single atom
        # puts "term: $term"
        if { [trs::term? $term] } { {*}$term
        } else { return $term }
    }
}

proc parse { term } { expression::parse $term $::tokens $expression::optable ident }

trs::rewrite-system -list rules -parser ::parse -eval ::evaluate
 
# rules
add-rule    (@c1 * x) + (@c2 * x)      -> (@c1 + @c2) * x
add-rule    (@c1 * x) - (@c2 * x)      -> (@c1 - @c2) * x
add-rule    x / x                        -> 1
add-rule    x * x**@c1                  -> x**(@c1 + 1)
add-rule    x**@c1 * x**@c2            -> x**(@c1 + @c2)
add-rule    x * x                        -> x**2
add-rule    @t1 * 0                     -> 0
add-rule    0 * @t1                     -> 0
add-rule    diff(sin(x), x)              -> cos(x)
add-rule    diff(x**@c1, x)             -> @c1 * x**(@c1 - 1)
add-rule    diff(@c1, y)                -> 0
add-rule    diff(x, x)                   -> 1
add-rule    diff(@c1 * x, x)            -> @c1
add-rule    diff(x * @c1, x)            -> @c1
add-rule    diff(@c1 * x**@c2, x)      -> @c1 * @c2 * x**(@c2 - 1)
add-rule    0 + @t1                     -> @t1
add-rule    0 - @t1                     -> -1 * (@t1)
add-rule    0 * @t1                     -> 0
add-rule    0 * @a1                     -> 0
add-rule    diff(@t1 * @t2, y)         -> diff(@t1, y) * @t2 + @t1 * diff(@t2, y)
add-rule    diff(cos(x), x)              -> -1 * sin(x)
add-rule    diff(@t1 + @t2, x)         -> diff(@t1, x) + diff(@t2, x)
add-rule    diff(@t1 - @t2, x)         -> diff(@t1, x) - diff(@t2, x)
add-rule    @c1 * (@t1 - @t2)         -> @c1 * @t1 - @c1 * @t2
add-rule    @c1 * (@t1 + @t2)         -> @c1 * @t1 + @c1 * @t2
add-rule    (@c1 * x) / (@c2 * x)      -> (@c1 / @c2) * (x / x)
add-rule    @c1 + @c2                  -> {[expr { 1.0 * @c1 + @c2 }]}
add-rule    @c1 - @c2                  -> {[expr { 1.0 * @c1 - @c2 }]}
add-rule    @c1 * @c2                  -> {[expr { 1.0 * @c1 * @c2 }]}
add-rule    @c1 / @c2                  -> {[expr { 1.0 * @c1 / @c2 }]}
add-rule    @c1 * 1                     -> @c1
add-rule    diff(@a1, y)                -> 0
add-rule    cos(@c1)                    -> {[expr { cos(@c1) }]}
add-rule    sin(@c1)                    -> {[expr { sin(@c1) }]}
add-rule    @a1 * @c1                  -> @c1 * @a1
add-rule    @c1 * x * @c2              -> @c1 * @c2 * x

add-rule    x * @c1 -> @c1 * x
add-rule    @c1 * x * x -> @c1 * x**2
add-rule    @c1 * @t1 * @c2 -> @c1 * @c2 * @t1
add-rule    @c1 * x**@c2 * x -> @c1 * x**(@c2 + 1)


set usage "usage: ./rewriter.tcl \[-e expression\]"

if { $argc } {
    switch [lindex $argv 0] {
        -e { puts [trs::eval-exp [trs::simplify [parse [lindex $argv 1]] $::rules]] }
        -i { trs::interact }
        default { puts $usage }
    }
}
