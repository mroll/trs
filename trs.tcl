source expression.tcl


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

proc recurse_reduce { term rules lvl } {
    # puts "[string repeat " " [expr { $lvl * 4 }]]reducing $term"
    # puts "[string repeat " " [expr { $lvl * 4 }]]--------------"
    for {set i 1} {$i < [llength $term]} {incr i} {
        set contractum [reduce $term $rules]
        if { [llength $contractum] } {
            # puts "[string repeat " " [expr { $lvl * 4 + 4 }]]replaced $term -> $contractum"
            return $contractum
        }

        set redex [lindex $term $i]
        if { [term? $redex] } {
            set contractum [recurse_reduce $redex $rules [expr { $lvl + 1 }]]
        }

        if { [llength $contractum] } {
            # puts -nonewline "[string repeat " " [expr { $lvl * 4 + 4 }]]replaced $term -> "
            set term [lreplace $term $i $i $contractum]
            # puts $term
        }
    }

    # puts ""
    set term
}


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
        {^__c\d+$}     { return {(\d+|\d+\.\d+)} }
        {^__t\d+$}     { return {({.*})} }
        {^__a\d+$}     { return (\[a-zA-Z0-9\]+) }
        {^__f\d+$}     { return ([join $::functions |]) }
        {^[a-zA-Z]+$} { return (\[a-zA-Z\]+) }
    }
}

set  functions { cos sin }
set  operators { add mul div sub pow diff cos sin }
proc operator? { v } { regexp [join [lmap op $::operators {subst {^$op\$}}] |] $v }
proc term?     { v } { expr { [llength $v] > 1 } }
proc var?      { v } { regexp {^(?:__)?\w+$}   $v }
proc constant? { v } { regexp {^[0-9]+$} $v }

proc make_regex { redex vars lvl } {
    set regex $redex
    set groups {}

    forindex i $regex {
        set t [lindex $regex $i]
        if { [operator? $t] } {
            lset regex $i %s
            lappend groups $t
        } elseif { [term? $t] } {
            set drill [make_regex $t $vars [expr {$lvl + 1}]]
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
                # lappend vars   [newvar $t $i]
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
    lassign [make_regex $redex {} 1] pattern vars

    subst { { term } {
            set match \[regexp {$pattern} \$term __r__ $vars\]
            if { \$match } { subst {[string map [dollarize $vars] $contractum]} }
            }
    }
}

proc simplify { term rules } {
    set old $term
    set new [recurse_reduce $term $rules 1]

    while { $old ne $new } {
        set old $new
        set new [recurse_reduce $new $rules 1]
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

proc add_rule { redex -> contractum } {
    set redex_tree [expression::parse $redex $::tokens $expression::optable ident]
    set contractum_tree [expression::parse $contractum $::tokens $expression::optable ident]

    uplevel [subst -nocommands { lappend rules [rule {$redex_tree} -> {$contractum_tree}] }]
}

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

proc numsonly? { args } {
    # puts $args
    foreach x $args {
        if { ! [string is digit $x] } { return 0 }
    }
    return 1
}

proc guard { args } {
    set guarded ""
    foreach el $args {
        if { [string is list $el] } {
            lappend guarded [list $el]
        } else {
            lappend guarded $el
        }
    }

    return $guarded
}

proc parse { term } { expression::parse $term $::tokens $expression::optable ident }


add_rule {x / x}                -> 1
add_rule {x * x**__c1}          -> {x**(__c1 + 1)}
add_rule {x**__c1 * x**__c2}    -> {x**(__c1 + __c2)}
add_rule {x * x}                -> {x**2}
add_rule {diff(sin(x), x)}      -> {cos(x)}
add_rule {diff(cos(x), x)}      -> {-1 * sin(x)}
add_rule {diff(x**__c1, x)}     -> {__c1 * x**(__c1 - 1)}
add_rule {diff(__c1, y)}        -> 0
add_rule {diff(__a1 + __a2, x)} -> {diff(__a1, x) + diff(__a2, x)}
add_rule {diff(x, x)}           -> 1
add_rule {diff(__t1 * __t2, y)} -> {diff(__t1, y)*__t2 + diff(__t2, y)*__t1}

set term "diff((y+1) * (x+2), y)"
# puts $term

set parsed [parse $term]
# puts $parsed

set tree [simplify $parsed $rules]
puts $tree

# interact
