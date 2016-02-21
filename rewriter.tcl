#!/usr/local/bin/tclsh8.6
#


source expression.tcl
source util.tcl

namespace eval trs {
    variable operators { add mul div sub pow diff cos sin call }


    proc reduce { term rules } {
        foreach rule $rules {
            set contractum [apply $rule $term]
            if { $contractum ne "" } {
                return $contractum
            }
        }
    }

    proc recurse-reduce { term rules lvl } {
        # puts "[string repeat " " [expr { $lvl * 4 }]]reducing $term"
        # puts "[string repeat " " [expr { $lvl * 4 }]]--------------"
        for {set i 1} {$i <= [llength $term]} {incr i} {
            set contractum [reduce $term $rules]

            if { [llength $contractum] } {
                # puts "[string repeat " " [expr { $lvl * 4 + 4 }]]replaced $term -> $contractum"
                return $contractum
            }

            set redex [lindex $term $i]
            if { [term? $redex] } {
                set contractum [recurse-reduce $redex $rules [expr { $lvl + 1 }]]
            }

            if { [llength $contractum] } {
                set redex $term
                lset term $i [concat $contractum]
                # puts "[string repeat " " [expr { $lvl * 4 + 4 }]]replaced $redex -> $term"
            }
        }

        # puts ""
        set term
    }

    proc group { v } {
        switch -regexp -matchvar m -- $v {
            {^__c\d+$}     { return {(\-?(?:\d+|\d+\.\d+))} }
            {^__t\d+$}     { return {({.*}|(?:\-?(?:\d+|\d+\.\d+))|[a-zA-Z0-9]+)} }
            {^__a\d+$}     { return (\[a-zA-Z0-9\]+) }
            {^[a-zA-Z]+$}  { return (\[a-zA-Z\]+) }
        }
    }

    proc operator? { v } { regexp [join [lmap op $trs::operators {subst {^$op\$}}] |] $v }
    proc term?     { v } { expr { [llength $v] > 1 } }
    proc var?      { v } { regexp {^(?:__)?\w+$}   $v }
    proc constant? { v } { regexp {^[0-9]+$} $v }

    proc rule-pattern { redex vars lvl } {
        set regex $redex
        set groups {}

        forindex i $regex {
            set t [lindex $regex $i]
            if { [operator? $t] } {
                lset regex $i %s
                lappend groups $t
            } elseif { [term? $t] } {
                set drill [rule-pattern $t $vars [expr {$lvl + 1}]]
                lset regex $i [lindex $drill 0]
                set vars [union $vars [lindex $drill 1]]
            } elseif { [constant? $t] } {
                lset regex $i %s
                lappend groups $t
            } elseif { [var?  $t] } {
                lset regex $i %s
                set  backtrack [lsearch $vars $t]

                # backtrack will be index+1 of the var in vars list, or -1 if not found.
                # If it exists, set the group to be the backtrack expr of the existing
                # var.
                #
                if { $backtrack != -1 } {
                    lappend groups "\\[expr {$backtrack+1}]"
                } else {
                    lappend groups [group $t]
                    lappend vars   $t
                }
            }
        }

        if { $lvl == 1 } {
            set pattern [format "^$regex" {*}$groups]
        } else {
            set pattern [format "$regex" {*}$groups]
        }

        list $pattern $vars
    }

    # return a mapping to pass to [string map] that will turn plain
    # variable names into dollar references.
    proc dollarize { varnames } {
        set pairs {}
        foreach name $varnames {
            lappend pairs $name
            lappend pairs $$name
        }

        set pairs
    }

    proc rule { redex -> contractum } {
        lassign [rule-pattern $redex {} 1] pattern vars

        subst { { term } {
                    set match \[regexp {$pattern} \$term __r__ $vars\]
                    if { \$match } {
                        set res "[subst {[string map [dollarize $vars] $contractum]}]"
                        if { \[constantterm \$res\] } { concat \$res
                        } elseif { \[llength \$res\] == 1 } { lindex \$res 0
                        } else { return \$res }
                    }
                }
        }
    }

    proc simplify { term rules } {
        set old $term
        set new [recurse-reduce $term $rules 1]

        while { $old ne $new } {
            set old $new
            set new [recurse-reduce $new $rules 1]
        }

        set new
    }

    proc interact { } {
        set input [prompt "> "]
        while { ! [string equal $input quit] } {
            if { [valid $input] } {
                # puts "expression tree: [parse $input]"
                set tmp [simplify [parse $input] $::rules]
                # puts "tmp: $tmp"
                puts [eval-exp $tmp]
            }
            set input [prompt "> "]
        }
    }
}

proc constantterm { term } { expr { [llength $term] == 1 && [string is double [first $term]] } }

proc add-rule { args } {
    set fields [lmap x [wsplit $args ->] { concat $x }]
    if { [llength $fields] ne 2 } {
        puts "bad rule: $fields"; return
    }

    foreach { redex contractum } $fields { }

    set redex_tree      [parse $redex]
    set contractum_tree [parse $contractum]

    uplevel [subst -nocommands { lappend rules [trs::rule {$redex_tree} -> {$contractum_tree}] }]
}

proc prompt { msg } {
    puts -nonewline $msg
    flush stdout
    gets stdin
}

proc valid { expression } { expr { ! [string equal $expression ""] } }
proc ident { args }       { set args }

set rules {}

# Process the operator table to create the string map table that suffices
# for the lexical analyzer.
#
set tokens [expression::prep-tokens $expression::optable]

proc cmd? { x } {
    expr { [lsearch [namespace inscope evaluate { info procs }] $x] != -1 }
}

proc cmds-only? { args } {
    foreach cmd $args {
        if { [llength $cmd] > 1 } { set test [lindex $cmd 0]
        } else { set test $cmd }

        if { ! [cmd? $test] } { return 0 }
    }
    return 1
}

proc nums-only? { args } {
    foreach x $args {
        if { ! [string is integer $x] } { return 0 }
    }
    return 1
}

proc single-cmd? { term } {
    foreach el $term {
        if { [string is list $el] } { return 0 }
    }
    return 1
}

proc eval-exp { exp } {
    if { [cmds-only? $exp] || [single-cmd? $exp] } {
        namespace inscope evaluate $exp
    } else {
        return $exp
    }
}

proc parse { term } { expression::parse $term $::tokens $expression::optable ident }

namespace eval evaluate {
    set binops { add + sub - mul * div / }
    foreach { name symb } $binops {
        set body [subst -nocommands { join [list [eval \$t1] [eval \$t2]] " $symb " }]
        proc $name { t1 t2 } $body
    }

    proc usub { t } {
        if { [nums-only? $t] } { expr { -$t }
        } else { return "-$t" }
    }

    proc pow  { base power } { return "[eval $base]**[eval $power]" }
    proc cos  { exp        } { return "cos([eval $exp])"            }
    proc sin  { exp        } { return "sin([eval $exp])"            }
    proc diff { exp var    } { return "diff([eval $exp], $var)"     }

    proc eval { term } {
        if { [cmds-only? $term] } { {*}$term
        } else { return $term }
    }

    proc call { args } { {*}$args }
}

 
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

set usage "usage: ./rewriter.tcl \[-e expression\]"

if { $argc } {
    switch [lindex $argv 0] {
        -e { puts [eval-exp [trs::simplify [parse [lindex $argv 1]] $::rules]] }
        -i { trs::interact }
        default { puts $usage }
    }
}
