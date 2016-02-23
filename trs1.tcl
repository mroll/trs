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
        if { [llength $term] > 1 } { {*}$term
        } else { return $term }
    }
}

proc parse { term } { expression::parse $term $::tokens $expression::optable ident }

trs::rewrite-system -list rules -parser ::parse -eval ::evaluate
 
# rules
add-rule    (__c1 * x) + (__c2 * x)      -> (__c1 + __c2) * x
add-rule    (__c1 * x) - (__c2 * x)      -> (__c1 - __c2) * x
add-rule    x / x                        -> 1
add-rule    x * x**__c1                  -> x**(__c1 + 1)
add-rule    x**__c1 * x**__c2            -> x**(__c1 + __c2)
add-rule    x * x                        -> x**2
add-rule    __t1 * 0                     -> 0
add-rule    0 * __t1                     -> 0
add-rule    diff(sin(x), x)              -> cos(x)
add-rule    diff(x**__c1, x)             -> __c1 * x**(__c1 - 1)
add-rule    diff(__c1, y)                -> 0
add-rule    diff(x, x)                   -> 1
add-rule    diff(__c1 * x, x)            -> __c1
add-rule    diff(x * __c1, x)            -> __c1
add-rule    diff(__c1 * x**__c2, x)      -> __c1 * __c2 * x**(__c2 - 1)
add-rule    0 + __t1                     -> __t1
add-rule    0 - __t1                     -> -1 * (__t1)
add-rule    0 * __t1                     -> 0
add-rule    0 * __a1                     -> 0
add-rule    diff(__t1 * __t2, y)         -> diff(__t1, y) * __t2 + __t1 * diff(__t2, y)
add-rule    diff(cos(x), x)              -> -1 * sin(x)
add-rule    diff(__t1 + __t2, x)         -> diff(__t1, x) + diff(__t2, x)
add-rule    diff(__t1 - __t2, x)         -> diff(__t1, x) - diff(__t2, x)
add-rule    __c1 * (__t1 - __t2)         -> __c1 * __t1 - __c1 * __t2
add-rule    __c1 * (__t1 + __t2)         -> __c1 * __t1 + __c1 * __t2
add-rule    (__c1 * x) / (__c2 * x)      -> (__c1 / __c2) * (x / x)
add-rule    __c1 + __c2                  -> {[expr { 1.0 * __c1 + __c2 }]}
add-rule    __c1 - __c2                  -> {[expr { 1.0 * __c1 - __c2 }]}
add-rule    __c1 * __c2                  -> {[expr { 1.0 * __c1 * __c2 }]}
add-rule    __c1 / __c2                  -> {[expr { 1.0 * __c1 / __c2 }]}
add-rule    __c1 * 1                     -> __c1
add-rule    diff(__a1, y)                -> 0
add-rule    cos(__c1)                    -> {[expr { cos(__c1) }]}
add-rule    sin(__c1)                    -> {[expr { sin(__c1) }]}
add-rule    __a1 * __c1                  -> __c1 * __a1
add-rule    __c1 * x * __c2              -> __c1 * __c2 * x


set usage "usage: ./rewriter.tcl \[-e expression\]"

if { $argc } {
    switch [lindex $argv 0] {
        -e { puts [trs::eval-exp [trs::simplify [parse [lindex $argv 1]] $::rules]] }
        -i { trs::interact }
        default { puts $usage }
    }
}
