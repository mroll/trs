source util.tcl

namespace eval trs {
    variable ops { add mul div sub pow diff cos sin call }
    variable evalspace
    variable evalcmd
    variable parseproc

    proc match-tree { inst symb symboltable } {
        set n [llength $symb]

        for {set i 0} {$i < $n} {incr i} {
            set subexpr [lindex $inst $i]
            set rulexpr [lindex $symb $i]

            set instclass [inst2class $subexpr]
            set ruleclass [symb2class $rulexpr]

            if { [llength $rulexpr] > 1 } {
                set recursivetable [match-tree $subexpr $rulexpr $symboltable]

                if { $recursivetable eq "" } {
                    return {}
                } else {
                    set symboltable [dict merge $symboltable $recursivetable]
                }
            } elseif { $instclass eq $ruleclass } {
                if { [group $rulexpr] } {
                    set exists [dict keys $symboltable $rulexpr]
                    if { $exists ne "" } {
                        set prev [dict get $symboltable $rulexpr]
                        if { $prev ne $subexpr } {
                            return {}
                        }
                    }

                    dict set symboltable $rulexpr [list $subexpr]
                }
            } else {
                return {}
            }
        }

        return $symboltable
    }

    proc group { symb } { variable ops; expr { [lsearch $ops $symb] == -1 } }

    proc inst2class { inst } {
        if { [string is double $inst] } {
            return constant
        } elseif { [string is alpha $inst] } {
            switch -regexp -- $inst {
                {^mul$}          { return MulOp }
                {^div$}          { return DivOp }
                {^add$}          { return AddOp }
                {^sub$}          { return SubOp }
                {^pow$}          { return PowOp }
                {^diff$}         { return DiffOp }
                {^[a-zA-Z]+$}    { return variable }
                {^[a-zA-Z0-9]+$} { return atom }
                default          { return nomatch }
            }
        } elseif { [string is list $inst] } {
            return subexpr
        } else {
            return nomatch
        }
    }

    proc symb2class { symb } {
        if { [llength $symb] > 1 } {
            return subexpr
        }
        switch -regexp -- $symb {
            {^@c\d+$}      { return constant }
            {^@t\d+$}      { return subexpr  }
            {^@a\d+$}      { return atom     }
            {^mul$}        { return MulOp }
            {^div$}        { return DivOp }
            {^add$}        { return AddOp }
            {^sub$}        { return SubOp }
            {^pow$}        { return PowOp }
            {^diff$}       { return DiffOp }
            {^[a-zA-Z]+$}  { return variable }
            default        { return nomatch  }
        }
    }


    # set up the lambda expression that is customized for each rule.
    # names prefixed with '@' are specific to each rule.
    variable ruleproc { { term } {
        set symboltable [trs::match-tree $term {@redex} [dict create]]
        if { $symboltable ne "" } {

            set result [subst -novariables [string map $symboltable {@contractum}]]
            return $result
            # return [string map $symboltable {@contractum}]
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

        uplevel [subst -nocommands { lappend rules [trs::rule-v2 {$redex_tree} -> {$contractum_tree}] }]
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

    proc preorder-reduce { term rules } {
        if { [llength $term] == 1 } { return $term }

        for {set i 0} {$i < [llength $term]} {incr i} {
            set current [lindex $term $i]
            set reduction [preorder-reduce $current $rules]

            lset term $i $reduction
            if { $reduction ne $current } { set i 0 }
        } 

        set reduction [reduce $term $rules]

        if { $reduction ne "" } {
            return $reduction
        } else {
            return $term
        }
    }

    proc rule { redex -> contractum } {
        variable ruleproc
        return [string map [list @redex $redex @contractum $contractum] $ruleproc]
    }

    proc simplify { term rules } {
        set old $term
        set new [preorder-reduce $term $rules]

        while { $old ne $new } {
            set old $new
            set new [preorder-reduce $new $rules]
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

    proc valid    { expression } { expr { $expression ne "" } }
    proc eval-exp { exp        } { variable evalcmd; $evalcmd $exp }
}

