source expression.tcl


proc forindex { i list body } {
    set len [llength $list]
    set script [subst { for {set $i 0} {$$i < $len} {incr $i} { $body } }]

    uplevel $script
}

proc reduce { term rules } {
    foreach rule $rules {
        set contractum [apply $rule $term]
        if { [string length $contractum] } {
            return $contractum
        }
    }
}

proc recurse_reduce { term rules lvl } {
    puts "[string repeat " " [expr { $lvl * 4 }]]reducing $term"
    puts "[string repeat " " [expr { $lvl * 4 }]]--------------"
    for {set i 1} {$i < [llength $term]} {incr i} {
        set contractum [reduce $term $rules]
        if { [llength $contractum] } {
            puts "[string repeat " " [expr { $lvl * 4 + 4 }]]replaced $term -> $contractum"
            return $contractum
        }

        set redex [lindex $term $i]
        if { [term? $redex] } {
            set contractum [recurse_reduce $redex $rules [expr { $lvl + 1 }]]
        }

        if { [llength $contractum] } {
            puts -nonewline "[string repeat " " [expr { $lvl * 4 + 4 }]]replaced $term -> "
            set term [lreplace $term $i $i $contractum]
            puts $term
        }
    }

    puts ""
    set term
}


proc union { a b } {
    set u {}
    foreach el [concat $a $b] {
        if { [lsearch $u $el] == -1 } { lappend u $el }
    }

    set u
}

proc makevar { v i } { join [list $v $i] _ }

proc group { v } {
    switch -regexp -matchvar m -- $v {
        {^const_\d+$} { return {(\d+|\d+\.\d+)} }
        {^term_\d+$}  { return {({.*})} }
        {^atom_\d+$}  { return (\[a-zA-Z0-9\]+) }
        {^[a-zA-Z]+$} { return (\[a-zA-Z\]+) }
    }
}

set  operators { add mul div sub pow deriv cos sin }
proc operator? { v } { regexp [join [lmap op $::operators {subst {^$op\$}}] |] $v }
proc term?     { v } { expr { [llength $v] > 1 } }
proc var?      { v } { regexp {^\w+$}    $v }
proc constant? { v } { regexp {^[0-9]+$} $v }

proc make_regex { redex contractum vars lvl } {
    set regex $redex
    set groups {}

    forindex i $regex {
        set t [lindex $regex $i]
        if { [operator? $t] } {
            lset regex $i %s
            lappend groups $t
        } elseif { [term? $t] } {
            set drill [make_regex $t $contractum $vars [expr {$lvl + 1}]]
            lset regex $i [lindex $drill 0]
            set vars [union $vars [lindex $drill 1]]
        } elseif { [constant? $t] } {
            lset regex $i %s
            lappend groups $t
        } elseif { [var?  $t] } {
            lset regex $i %s
            set  backtrack [lsearch $vars $t]

            # backtrack will be index+1 of the var in vars, or -1 if not found.
            # If it exists, set the group to be the backtrack expr of the existing
            # var.
            #
            if { $backtrack != -1 } {
                lappend groups "\\[expr {$backtrack+1}]"
                lappend vars   [makevar $t $i]
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
    lassign [make_regex $redex $contractum {} 1] pattern vars

    subst { { term } {
            set match \[regexp {$pattern} \$term __r__ $vars\]
            if { \$match } { subst {[string map [dollarize $vars] $contractum]} }
            }
    }
}

proc simplify { term rules } {
    set old $term
    set new [recurse_reduce $term $rules 1]

    while { ! [string equal $old $new] } {
        set old $new
        set new [recurse_reduce $new $rules 1]
    }

    puts "t = $new"
}

proc add_rule { redex -> contractum } {
    uplevel [subst -nocommands { lappend rules [rule {$redex} -> {$contractum}] }]
}

set rules {}

## constant add, sub, mul, pow (no division yet, just to avoid long floating points)
add_rule {add const_1 const_2}                 -> {[expr {const_1 + const_2 * 1.0}]}
add_rule {mul const_1 const_2}                 -> {[expr {const_1 * const_2 * 1.0}]}
add_rule {sub const_1 const_2}                 -> {[expr {const_1 - const_2 * 1.0}]}
add_rule {pow const_1 const_2}                 -> {[expr {pow(const_1, const_2) * 1.0}]}

## simple variable rules
add_rule {div y y}                             -> 1
add_rule {mul y y}                             -> {pow y 2}
add_rule {mul {pow y const_1} {pow y const_1}} -> {pow y [expr {const_1 + const_1}]}

## simple derivative rules
add_rule {deriv {sin y} y}                     -> {cos y}
add_rule {deriv {cos y} y}                     -> {mul -1 {sin y}}
add_rule {deriv {pow y const_1} y}             -> {mul const_1 {pow y [expr {const_1 - 1}]}}
add_rule {deriv {add atom_1 atom_2} y}         -> {add {deriv atom_1 y} {deriv atom_2 y}}
add_rule {deriv y y}                           -> 1
add_rule {deriv {mul term_1 term_2}}           -> {add {mul {deriv term_1} term_2} {mul term_1 {deriv term_2}}}
add_rule {deriv const_1 y}                     -> 0

## identity
add_rule {mul term_1 1}                        -> term_1
add_rule {mul atom_1 1}                        -> atom_1
add_rule {pow y 1}                             -> y
add_rule {add term_1 0}                        -> term_1
add_rule {add y 0}                             -> y
add_rule {sub term_1 0}                        -> term_1
add_rule {sub y 0}                             -> y

## multiplicative associativity
add_rule {mul const_1 {mul const_2 term_1}}    -> {mul [expr {const_1 * const_2}] term_1}
add_rule {mul z {mul y z}}                     -> {mul {pow y 2} z}
add_rule {mul {mul y z} y}                     -> {mul {pow y 2} z}
add_rule {mul y {pow y const_1}}               -> {pow y [expr {const_1 + 1}]}
add_rule {mul z {mul term_1 z}}                -> {mul {pow z 2} term_1}
add_rule {mul {mul const_1 y} y}               -> {mul {pow y 2} const_1}
add_rule {mul {pow y const_1} {mul const_2 y}} -> {mul {pow y [expr {const_1 + 1.0}]} const_2}
add_rule {mul const_1 {mul const_2 y}}         -> {mul [expr {const_1 * const_2}] y}
add_rule {div {mul const_1 y} {mul const_2 z}} -> {mul {div const_1 const_2} {div y z}}

## move constants to the front
add_rule {mul y const_1}                       -> {mul const_1 y}
add_rule {add y const_1}                       -> {add const_1 y}

proc prompt { msg } {
    puts -nonewline $msg
    flush stdout
    gets stdin
}

proc valid { expression } { expr { ! [string equal $expression ""] } }
proc ident { args }       { set args }

# Process the operator table to create the string map table that suffices
# for the lexical analyzer.
#
set tokens [expression::prep-tokens $expression::optable]

proc interact { } {
    set input [prompt "> "]
    while { ! [string equal $input quit] } {
        set term [expression::parse $input $::tokens $expression::optable ident]
        if { [valid $term] } {
            puts "expression tree: $term"
            puts [simplify $term $::rules]
        }
        set input [prompt "> "]
    }
}

interact
