source expression.tcl

proc wsplit {str sep} {
  split [string map [list $sep \0] $str] \0
} ;# RS

proc first { list } { lindex $list 0 }

proc forindex { i list body } {
    set len [llength $list]
    set script [subst { for {set $i 0} {$$i < $len} {incr $i} { $body } }]

    uplevel $script
}

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


# inefficient union, I know, but it has to maintain ordering
proc union { a b } {
    set u {}
    foreach el [concat $a $b] {
        if { [lsearch $u $el] == -1 } { lappend u $el }
    }

    set u
}

proc newvar { v i } { join [list $v $i] _ }

proc group { v } {
    switch -regexp -matchvar m -- $v {
        {^__c\d+$}     { return {(\-?(?:\d+|\d+\.\d+))} }
        {^__t\d+$}     { return {({.*}|(?:\-?(?:\d+|\d+\.\d+))|[a-zA-Z0-9]+)} }
        {^__a\d+$}     { return (\[a-zA-Z0-9\]+) }
        {^[a-zA-Z]+$}  { return (\[a-zA-Z\]+) }
    }
}

set  operators { add mul div sub pow diff cos sin call }
proc operator? { v } { regexp [join [lmap op $::operators {subst {^$op\$}}] |] $v }
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

proc constantterm { term } { expr { [llength $term] == 1 && [string is double [first $term]] } }

proc rule { redex -> contractum } {
    lassign [rule-pattern $redex {} 1] pattern vars

    subst { { term } {
                set match \[regexp {$pattern} \$term __r__ $vars\]
                if { \$match } {
                    set res "[subst {[string map [dollarize $vars] $contractum]}]"
                    if { \[constantterm \$res\] } { concat \$res
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

proc fprime { term } {
    switch [lindex $term 0] {
        cos { return [subst { {mul -1 {sin [lindex $term 1]}} }] }
        sin { return [subst { {cos [lindex $term 1]} }] }
    }
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

proc add-rule { args } {
    set fields [lmap x [wsplit $args ->] { concat $x }]
    if { [llength $fields] ne 2 } {
        puts "bad rule: $fields"; return
    }

    foreach { redex contractum } $fields { }

    set redex_tree      [parse $redex]
    set contractum_tree [parse $contractum]

    uplevel [subst -nocommands { lappend rules [rule {$redex_tree} -> {$contractum_tree}] }]
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

namespace eval evaluate {
    proc add { t1 t2 } { reduce2 $t1 $t2 + }
    proc sub { t1 t2 } { reduce2 $t1 $t2 - }
    proc mul { t1 t2 } { reduce2 $t1 $t2 * }
    proc div { t1 t2 } { reduce2 $t1 $t2 / }

    proc usub { t } {
        if { [nums-only? $t] } { expr { -$t }
        } else { return "-$t" }
    }

    proc pow { base power } {
        if { [nums-only? $base $power] } { expr { pow($base, $power) }
        } else { return "[eval $base]**[eval $power]" }
    }

    proc cos { exp } {
        if { [nums-only? $exp] } { expr { cos($exp) }
        } else { return "cos($exp)" }
    }

    proc sin { exp } {
        if { [nums-only? $exp] } { expr { sin($exp) }
        } else { return "sin($exp)" }
    }

    proc diff { exp var } {
        if { [cmds-only? $exp] } { return "diff([{*}$exp], $var)"
        } else { return "diff($exp, $var)" }
    }

    proc reduce2 { t1 t2 op } {
        if { [nums-only? $t1 $t2] } { {*}[subst {expr { $t1 $op $t2 }}]
        } else { return "[eval $t1] $op [eval $t2]" }
    }

    proc eval { term } {
        if { [cmds-only? $term] } { {*}$term
        } else { return $term }
    }

    proc call { args } { {*}$args }
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
# add-rule    0 + __t1                     -> __t1
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

# puts [eval-exp [simplify [parse "diff(8 * x**3, x)"] $::rules]]

# interact
