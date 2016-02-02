source expression.tcl


proc forindex { i list body } {
    set len [llength $list]
    set script [subst { for {set $i 0} {$$i < $len} {incr $i} { $body } }]

    uplevel $script
}

proc unpack { vals args } {
    set script {}
    forindex i $vals {
        lappend script [list set [lindex $args $i] [lindex $vals $i]]
    }

    uplevel [join $script "; "]
}

proc term? { expr } { expr { [llength $expr] > 1 } }

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

proc operator? { term } {
    set operators { add mul div sub pow deriv cos sin }
    regexp [join [lmap op $operators {subst {^$op\$}}] |] $term
}

proc union { a b } {
    set u {}
    foreach el [concat $a $b] {
        if { [lsearch $u $el] == -1 } { lappend u $el }
    }

    set u
}

proc regexp_cmd { redex contractum vars lvl } {
    set regex $redex
    set groups {}

    forindex i $regex {
        set t [lindex $regex $i]
        if { [operator? $t] } {
            lset regex $i %s
            lappend groups $t
        } elseif { [term? $t] } {
            set drill [regexp_cmd $t $contractum $vars [expr {$lvl + 1}]]
            lset regex $i [lindex $drill 0]
            set vars [union $vars [lindex $drill 1]]
        } elseif { [regexp {^term_\d+} $t] } {
            lset regex $i %s
            lappend groups {({.*})}
            lappend vars $t
        } elseif { [regexp {^const_\d+} $t] } {
            lset regex $i %s
            lappend groups {(\d+|\d+\.\d+)}
            lappend vars $t
        } elseif { [regexp {^\w+$} $t] }  {
            lset regex $i %s
            set exists [lsearch $vars $t]
            if { $exists != -1 } {
                lappend groups "\\[expr {$exists+1}]"
                lappend vars [join [list $t $i] _]
            } else {
                lappend groups (\[a-zA-Z\]+)
                lappend vars $t
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

proc mapper { varnames } {
    set pairs {}
    foreach name $varnames {
        lappend pairs $name
        lappend pairs $$name
    }

    set pairs
}

proc rule { redex -> contractum } {
    unpack [regexp_cmd $redex $contractum {} 1] regex vars

    return [subst { { term } {
                set match \[regexp {$regex} \$term __r__ $vars\]
                if { \$match } { subst {[string map [mapper $vars] $contractum]} }
               } }]
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

proc add_rule { redex -> contractum } { uplevel [subst -nocommands { lappend rules [rule {$redex} -> {$contractum}] }] }

set rules {}
add_rule {div {mul const_1 y} {mul const_2 z}} -> {mul {div const_1 const_2} {div y z}}
add_rule {div y y}                             -> 1
add_rule {add const_1 const_2}                 -> {[expr {1.0 * const_1 + const_2}]}
add_rule {mul const_1 const_2}                 -> {[expr {const_1 * const_2 * 1.0}]}
add_rule {pow const_1 const_2}                 -> {[expr {pow(const_1, const_2) * 1.0}]}
add_rule {deriv {pow y const_1}}               -> {mul const_1 {pow y [expr {const_1 - 1}]}}
add_rule {div const_1 const_2}                 -> {[expr {1.0 * const_1 / const_2}]}
add_rule {mul const_1 {mul const_2 term_1}}    -> {mul [expr {const_1 * const_2}] term_1}
add_rule {mul {pow y const_1} {pow y const_2}} -> {pow y [expr {const_1 + const_2}]}
add_rule {deriv {mul term_1 term_2}}           -> {add {mul {deriv term_1} term_2} {mul term_1 {deriv term_2}}}
add_rule {deriv {sin y}}                       -> {cos y}
add_rule {deriv {cos y}}                       -> {mul -1 {sin y}}
add_rule {sub const_1 const_2}                 -> {[expr {const_1 - const_2}]}
add_rule {mul y y}                             -> {pow y 2}
add_rule {mul {pow y const_1} y}               -> {pow y [expr {const_1 + 1}]}
add_rule {mul y {pow y const_1}}               -> {pow y [expr {const_1 + 1}]}
add_rule {mul {mul y z} y}                     -> {mul {pow y 2} z}
add_rule {mul z {mul y z}}                     -> {mul {pow y 2} z}
add_rule {mul z {mul term_1 z}}                -> {mul {pow z 2} term_1}
add_rule {mul {mul term_1 z} z}                -> {mul {pow z 2} term_1}
add_rule {mul {mul const_1 y} y}               -> {mul {pow y 2} const_1}
add_rule {mul {pow y const_1} {mul const_2 y}} -> {mul {pow y [expr {const_1 + 1.0}]} const_2}

proc prompt { msg } {
    puts -nonewline $msg
    flush stdout
    gets stdin
}

proc valid { expression } { expr { ! [string equal $expression ""] } }

proc ident { args } { set args }

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

simplify {deriv {sin matt}} $rules

# interact
