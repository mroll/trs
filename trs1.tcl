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
add-rule    @c1 + @c2        -> {[expr { 1.0 * @c1 + @c2 }]}
add-rule    @c1 - @c2        -> {[expr { 1.0 * @c1 - @c2 }]}
add-rule    @c1 * @c2        -> {[expr { 1.0 * @c1 * @c2 }]}
add-rule    @c1 / @c2        -> {[expr { 1.0 * @c1 / @c2 }]}
add-rule    @c1 * 1          -> @c1
add-rule    x * x            -> x**2
add-rule    x * x**@c1         -> x**(@c1 + 1)

puts [lindex $rules end]

set usage "usage: ./rewriter.tcl \[-e expression\]"

if { $argc } {
    switch [lindex $argv 0] {
        -e { puts [trs::eval-exp [trs::simplify [parse [lindex $argv 1]] $::rules]] }
        -i { trs::interact }
        default { puts $usage }
    }
}
