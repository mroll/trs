source util.tcl

namespace eval trs {
    variable ops { add mul div sub pow diff cos sin call }
    variable evalspace
    variable evalcmd
    variable parseproc

    # set up the lambda expression that is customized for each rule.
    # names prefixed with '@' are specific to each rule.
    variable ruleproc { { term } {
        set match [regexp {^@pattern} $term __r__ @vars]
        if { $match } {
            set newterm [subst {@res}]
            if { [llength $newterm] == 1 } {
                lindex $newterm 0
            } else {
                return $newterm
            }
        }
    }}

    # lambda expression that is customized depending on the name of
    # the rules list.
    variable adderproc { { args } {
        set fields [lmap x [wsplit $args ->] { concat $x }]
        if { [llength $fields] ne 2 } {
            puts "bad rule: $fields"; return
        }

        lassign $fields redex contractum

        set redex_tree      [parse $redex]
        set contractum_tree [parse $contractum]

        uplevel [subst -nocommands { lappend rules [trs::rule {$redex_tree} -> {$contractum_tree}] }]
    }}

    proc parse { term } { variable parseproc; $parseproc $term }

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

    proc operator? { v } { variable ops; regexp [join [lmap op $ops {subst {^$op\$}}] |] $v }
    proc term?     { v } { expr { [llength $v] > 1 } }
    proc var?      { v } { regexp {^(?:__)?\w+$}   $v }
    proc constant? { v } { regexp {^[0-9]+$} $v }

    proc rule-matcher { redex } {
        set regex $redex
        set groups {}
        set vars   {}

        forindex i $regex {
            set t [lindex $regex $i]
            if { [operator? $t] || [constant? $t] } {
                lset    regex $i %s
                lappend groups $t
            } elseif { [term? $t] } {
                set  drill [rule-matcher $t]
                lset regex $i [lindex $drill 0]
                set  vars  [union $vars [lindex $drill 1]]
            } elseif { [var?  $t] } {
                lset regex $i %s
                set  backtrack [lsearch $vars $t]

                # backtrack will be index of the var in vars list, or -1 if not found.
                # If it exists, set the group to be the backtrack+1 expr of the existing
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

        list [format "$regex" {*}$groups] $vars
    }

    proc rule { redex -> contractum } {
        variable ruleproc

        lassign [rule-matcher $redex] pattern vars

        set names {@pattern @vars @res}
        set vals  [list $pattern $vars [dollarize $vars $contractum]]

        string map [interleave $names $vals] $ruleproc
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
        while { $input ne "quit" } {
            if { [valid $input] } {
                puts "expression tree: [parse $input]"
                puts [eval-exp [simplify [parse $input] $::rules]]
            }
            set input [prompt "> "]
        }
    }

    proc rewrite-system { -list list_name -parser _parseproc -eval _evalspace } {
        variable adderproc
        variable parseproc $_parseproc
        variable evalspace $_evalspace
        variable evalcmd [join [list $evalspace eval] ::]


        uplevel [list set $list_name {}]
        proc ::add-rule {*}[string map "rules $list_name" $adderproc]
    }

    proc valid    { expression } { expr { ! [string equal $expression ""] } }
    proc eval-exp { exp        } { variable evalcmd; $evalcmd $exp }
}

