proc wsplit {str sep} {
  split [string map [list $sep \0] $str] \0
} ;# RS

proc first { list } { lindex $list 0 }

proc forindex { i list body } {
    set len [llength $list]
    set script [subst { for {set $i 0} {$$i < $len} {incr $i} { $body } }]

    uplevel $script
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

proc interleave {args} {
    if {[llength $args] == 0} {return {}}

    set data {}
    set idx  0
    set head {}
    set body "lappend data"

    foreach arg $args {
        lappend head v$idx $arg
        append  body " \$v$idx"
        incr idx
    }

    eval foreach $head [list $body]
    return $data
} ;# AMG

# return a mapping to pass to [string map] that will turn plain
# variable names into dollar references.
proc dollarize { varnames string } {
    set pairs {}
    foreach name $varnames {
        lappend pairs $name
        lappend pairs $$name
    }

    string map $pairs $string
}

proc nums-only? { args } {
    foreach x $args {
        if { ! [string is integer $x] } { return 0 }
    }
    return 1
}

proc prompt { msg } {
    puts -nonewline $msg
    flush stdout
    gets stdin
}

proc ident { args }       { set args }
